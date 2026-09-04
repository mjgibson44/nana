import Foundation
import WordCore

/// How long a client waits for the host's announcement before electing one
/// itself. Short: the announcement is one broadcast on match formation, so
/// silence past this means the announcement was missed or never sent (an older
/// build, a party formed without a lobby creator).
public let HOST_ANNOUNCE_TIMEOUT_SECONDS: TimeInterval = 3

/// The shorter wait for a match with no natural host at all — strangers
/// paired by automatch, where nobody opened the room. Everyone starts as a
/// client, and the lowest id claims the referee's chair once this passes with
/// no announcement heard. Two repeats of the host's once-a-second re-announce,
/// so an established host in a match being backfilled is heard first.
public let HOST_CLAIM_TIMEOUT_SECONDS: TimeInterval = 2

public struct ClientEvents {
    public var onState: ((BattleState) -> Void)?
    public var onStart: ((String) -> Void)?
    public var onStop: (() -> Void)?
    public var onAttack: ((Int) -> Void)?
    /// The host refused us — a version mismatch or a full lobby. Terminal.
    public var onRejected: ((String) -> Void)?
    /// Which player is refereeing, once known.
    public var onHostElected: ((PlayerID) -> Void)?
    /// Occupy: our word numbered `serial` is down, or isn't.
    public var onPlaced: ((Int) -> Void)?
    public var onRefused: ((Int, String) -> Void)?
    /// Nobody announced and this player has the lowest id: it should be the
    /// one refereeing. The app stands up a host session in this one's place.
    public var onShouldHost: (() -> Void)?

    public init(
        onState: ((BattleState) -> Void)? = nil,
        onStart: ((String) -> Void)? = nil,
        onStop: (() -> Void)? = nil,
        onAttack: ((Int) -> Void)? = nil,
        onRejected: ((String) -> Void)? = nil,
        onHostElected: ((PlayerID) -> Void)? = nil,
        onPlaced: ((Int) -> Void)? = nil,
        onRefused: ((Int, String) -> Void)? = nil,
        onShouldHost: (() -> Void)? = nil
    ) {
        self.onState = onState
        self.onStart = onStart
        self.onStop = onStop
        self.onAttack = onAttack
        self.onRejected = onRejected
        self.onHostElected = onHostElected
        self.onPlaced = onPlaced
        self.onRefused = onRefused
        self.onShouldHost = onShouldHost
    }
}

/// A non-host seat. Talks only to the host — which is how the star topology
/// survives GKMatch's full mesh — and holds the host's latest snapshot.
///
/// The one genuinely new piece of protocol lives here (plan §7.2): on the web
/// the join code *is* the host's address, but a party-code match is a mesh with
/// no marked owner. So a client waits briefly for a `host` announcement and,
/// hearing none, falls back to the lowest player id — a rule every client
/// computes identically, so they all agree without talking about it.
public final class ClientSession {
    public private(set) var state: BattleState?
    public private(set) var hostID: PlayerID?
    public private(set) var isRejected = false
    public var events = ClientEvents()

    private let transport: BattleTransport
    /// Injected rather than read from the wall clock, so the election timeout
    /// is deterministic in tests.
    private let clock: () -> Date
    /// How long to listen for an announcement before electing.
    private let announceTimeout: TimeInterval
    /// When we started listening, for the election timeout.
    private var listeningSince: Date
    /// True once we've said hello to the current host.
    private var greeted = false
    /// True once the app has been told to host, so it's told once per election.
    private var askedToHost = false
    /// Dropped while re-entering, exactly like the web: a send that can't be
    /// delivered is silently skipped rather than queued (spec §6).
    public private(set) var isReconnecting = false

    public init(
        transport: BattleTransport,
        clock: @escaping () -> Date = { .now },
        announceTimeout: TimeInterval = HOST_ANNOUNCE_TIMEOUT_SECONDS
    ) {
        self.transport = transport
        self.clock = clock
        self.announceTimeout = announceTimeout
        listeningSince = clock()

        transport.onReceive = { [weak self] data, sender in
            self?.receive(data, from: sender)
        }
        transport.onPlayerConnected = { [weak self] _ in
            // A new face can't change who referees; if we have no host yet the
            // election timeout will settle it.
            guard let self else { return }
            electIfNeeded(at: clock())
        }
        transport.onPlayerDisconnected = { [weak self] player in
            self?.hostDisappeared(player)
        }
    }

    public var selfID: PlayerID { transport.localPlayerID }

    // MARK: The clock

    /// Drives the host-election timeout. The app calls this from the same
    /// timer that runs its heartbeat.
    public func tick(at now: Date) {
        electIfNeeded(at: now)
    }

    /// Elect the lowest player id when no announcement has arrived in time.
    /// Deterministic and identical on every client, so nobody has to agree
    /// out loud.
    private func electIfNeeded(at now: Date) {
        // A mid-game loss holds the seat and waits; it never elects.
        guard hostID == nil, !isRejected, !isReconnecting else { return }
        guard now.timeIntervalSince(listeningSince) >= announceTimeout else { return }
        let candidates = ([selfID] + transport.remotePlayerIDs).sorted()
        guard let elected = candidates.first, elected != selfID else {
            // We are the lowest id: this session should be the host. The app
            // layer stands one up in its place — told once per election.
            guard !askedToHost else { return }
            askedToHost = true
            events.onShouldHost?()
            return
        }
        adopt(host: elected)
    }

    // MARK: Receiving

    private func receive(_ data: Data, from sender: PlayerID) {
        guard !isRejected, let message = Wire.decode(HostMessage.self, from: data) else { return }

        switch message {
        case let .host(proto):
            // The announcement settles the election, whenever it lands: a late
            // joiner gets its own copy.
            guard proto == PROTOCOL_VERSION else {
                fail("This battle is running a different version of the game.")
                return
            }
            // Two referees can only meet in a match nobody opened, and then
            // the lowest id wins — the rule the timeout fallback already
            // applies, so every device lands on the same answer. A live host
            // is only ever traded for a lower one.
            if let hostID, sender > hostID, transport.remotePlayerIDs.contains(hostID) {
                return
            }
            adopt(host: sender)

        case let .state(state):
            // Only the host's word counts, and a snapshot is adopted whole:
            // no deltas, no sequence numbers, correct under ordered delivery.
            guard sender == hostID || hostID == nil else { return }
            if hostID == nil { adopt(host: sender) }
            self.state = state
            events.onState?(state)

        case let .start(seed):
            guard sender == hostID else { return }
            events.onStart?(seed)

        case .stop:
            guard sender == hostID else { return }
            events.onStop?()

        case let .attack(count):
            guard sender == hostID else { return }
            // Only a count crosses the wire; the letters are drawn locally
            // from this player's private stream (spec §3).
            events.onAttack?(max(0, count))

        case .ping:
            guard sender == hostID else { return }
            send(.pong)

        case let .reject(reason):
            guard sender == hostID else { return }
            fail(reason)

        case let .placed(serial):
            guard sender == hostID else { return }
            events.onPlaced?(serial)

        case let .refused(serial, reason):
            guard sender == hostID else { return }
            events.onRefused?(serial, reason)
        }
    }

    private func adopt(host: PlayerID) {
        guard hostID != host else {
            // Re-announced (a reconnect, a late broadcast, the host's repeat
            // to whoever hasn't sat down): greet again unless the host's own
            // snapshot already seats us. A hello that landed before the host
            // session existed is retried this way rather than never.
            if !greeted || !isSeated { greet() }
            return
        }
        hostID = host
        greeted = false
        askedToHost = false
        events.onHostElected?(host)
        greet()
    }

    /// Whether the host's latest snapshot has a seat for us.
    private var isSeated: Bool {
        state?.players.contains { $0.id == selfID } == true
    }

    private func greet() {
        guard hostID != nil else { return }
        greeted = true
        send(.hello(proto: PROTOCOL_VERSION))
    }

    /// The host vanished. Mid-game there is no host migration in this
    /// protocol — the lobby dies with its referee — but GameKit tells us in
    /// seconds instead of the web's 115-second redial budget (plan §7.4). In
    /// the lobby nothing is lost by choosing again, so the election simply
    /// re-runs: whoever is lowest among those left takes the chair.
    private func hostDisappeared(_ player: PlayerID) {
        guard player == hostID else { return }
        hostID = nil
        greeted = false
        askedToHost = false
        isReconnecting = state?.phase == .playing
        listeningSince = clock()
    }

    /// Take a known referee without waiting to be told: a host that has just
    /// stood down in favour of a lower id already knows who that is.
    public func follow(host: PlayerID) {
        guard !isRejected else { return }
        adopt(host: host)
    }

    /// A player id came back — the same-id re-entry that reclaims a graced
    /// seat. Say hello again with the same identity and the host re-attaches.
    public func reattach() {
        let now = clock()
        isReconnecting = false
        listeningSince = now
        if hostID != nil {
            greet()
        } else {
            electIfNeeded(at: now)
        }
    }

    private func fail(_ reason: String) {
        isRejected = true
        hostID = nil
        events.onRejected?(reason)
    }

    // MARK: Sending

    /// Report this board's score, burial and pile size. Stateful-latest: only
    /// the newest matters, so a lost one is harmless.
    public func reportProgress(score: Int, buried: Bool, tiles: Int) {
        send(.progress(score: score, buried: buried, tiles: tiles))
    }

    /// Send a volley. Fire-and-forget by design — the host clamps and splits.
    public func sendAttack(_ count: Int) {
        guard count > 0 else { return }
        send(.attack(count: count))
    }

    /// Occupy: a word let go of. The host answers with `placed` or `refused`
    /// by the same serial — after a snapshot, if it went down.
    public func sendPlacement(serial: Int, placement: OccupyPlacement) {
        send(.place(serial: serial, placement: placement))
    }

    public func leave() {
        send(.leave)
    }

    private func send(_ message: ClientMessage) {
        // While the link is down, sends are dropped rather than queued: a
        // replayed attack after a reconnect would hit a game that has moved on.
        guard let hostID, !isReconnecting, !isRejected else { return }
        guard let data = Wire.encode(message) else { return }
        transport.send(data, to: [hostID])
    }
}
