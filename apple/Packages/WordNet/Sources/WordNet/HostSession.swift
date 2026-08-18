import Foundation
import WordCore

/// How long a dropped mid-game seat is held before the game counts that player
/// out (spec §5). The web's 30s; the plan expects to tune this from phase-4
/// device data, since iOS backgrounding drops a player the instant they switch
/// apps.
public let RECONNECT_GRACE_SECONDS: TimeInterval = 30

/// The host broadcasts a heartbeat this often. GKMatch's player-state callbacks
/// mostly replace it, but their timeliness for a half-dead link isn't
/// documented, so the slow app-level beat stays (plan §7.2).
public let PING_INTERVAL_SECONDS: TimeInterval = 15

/// Silence this long means a dead link, whatever the transport thinks.
public let STALE_LINK_SECONDS: TimeInterval = 25

/// The largest volley the host will pass on, however big a client claims.
public let ATTACK_CLAMP = 50

/// What the host tells its own game layer. The host plays too, so its own
/// attacks and state arrive through callbacks rather than the wire.
public struct HostEvents {
    public var onState: ((BattleState) -> Void)?
    public var onStart: ((String) -> Void)?
    public var onStop: (() -> Void)?
    /// The host's own share of a rival's volley.
    public var onAttack: ((Int) -> Void)?

    public init(
        onState: ((BattleState) -> Void)? = nil,
        onStart: ((String) -> Void)? = nil,
        onStop: (() -> Void)? = nil,
        onAttack: ((Int) -> Void)? = nil
    ) {
        self.onState = onState
        self.onStart = onStart
        self.onStop = onStop
        self.onAttack = onAttack
    }
}

/// The referee. Owns the roster, the seat grace clock, attack splitting, the
/// elimination order, and the verdict — the transport-independent half of
/// `battleSession.ts`'s `HostSession`, which is nearly all of it (spec §2).
///
/// Time is injected: `tick(at:)` drives grace expiry, pings and staleness, so
/// a 30-second grace period is one line in a test rather than half a minute of
/// CI (plan §11).
public final class HostSession {
    public private(set) var state: BattleState
    public var events = HostEvents()

    private let transport: BattleTransport
    private let displayName: (PlayerID) -> String
    private let makeSeed: () -> String
    /// The session never reads the wall clock itself: grace expiry, staleness
    /// and the heartbeat all run off this, so a test can play 30 seconds in a
    /// microsecond and the app can hand over a clock of its own.
    private let clock: () -> Date

    /// Write-once elimination stamps, monotonic per game (spec §2).
    private var outCounter = 0
    /// The rotating offset that spreads an attack's remainder tile fairly.
    private var attackSpread = 0
    /// When each seat was last heard from, for the staleness sweep.
    private var lastSeen: [PlayerID: Date] = [:]
    /// Seats holding open for a dropped player, and when their grace runs out.
    private var graceUntil: [PlayerID: Date] = [:]
    private var lastPing: Date?

    public init(
        transport: BattleTransport,
        displayName: @escaping (PlayerID) -> String,
        makeSeed: @escaping () -> String = { randomSeed() },
        clock: @escaping () -> Date = { .now }
    ) {
        self.transport = transport
        self.displayName = displayName
        self.makeSeed = makeSeed
        self.clock = clock
        state = BattleState(
            phase: .lobby,
            players: [
                BattlePlayer(
                    id: transport.localPlayerID,
                    name: displayName(transport.localPlayerID),
                    host: true)
            ],
            game: 0,
            winnerId: nil)
        lastPing = clock()

        transport.onReceive = { [weak self] data, sender in
            self?.receive(data, from: sender)
        }
        transport.onPlayerConnected = { [weak self] player in
            // A late arrival can't know who referees a mesh, so tell them.
            self?.announceHost(to: [player])
        }
        transport.onPlayerDisconnected = { [weak self] player in
            guard let self else { return }
            drop(player, at: clock())
        }
    }

    public var selfID: PlayerID { transport.localPlayerID }

    /// Broadcast "I am the referee" — on match formation, and again to every
    /// later-connecting player (plan §7.2).
    public func announceHost(to players: [PlayerID]? = nil) {
        guard let data = Wire.encode(HostMessage.host(proto: PROTOCOL_VERSION)) else { return }
        if let players {
            transport.send(data, to: players)
        } else {
            transport.broadcast(data)
        }
    }

    // MARK: Receiving

    private func receive(_ data: Data, from sender: PlayerID) {
        // Any traffic at all proves the link is alive.
        lastSeen[sender] = clock()
        guard let message = Wire.decode(ClientMessage.self, from: data) else { return }

        switch message {
        case let .hello(proto):
            handleHello(from: sender, proto: proto)
        case let .progress(score, buried, tiles):
            handleProgress(from: sender, score: score, buried: buried, tiles: tiles)
        case let .attack(count):
            relayAttack(from: sender, count: count)
        case .pong:
            break  // lastSeen is the whole point of it
        case .leave:
            // A deliberate exit gets no grace period.
            remove(sender)
        }
    }

    private func handleHello(from sender: PlayerID, proto: Int) {
        // The version gate: no Game Center sandbox means a prerelease build
        // can meet a released one (TN2417), so mismatches are refused loudly.
        guard proto == PROTOCOL_VERSION else {
            reject(sender, reason: "This player is on a different version of the game.")
            return
        }

        if let index = state.players.firstIndex(where: { $0.id == sender }) {
            // A known seat re-attaches: cancel its grace, and if the game
            // already counted them out, bring them back as a spectator dealt
            // into the next game (spec §5).
            graceUntil[sender] = nil
            state.players[index].connected = true
            if state.players[index].left {
                state.players[index].left = false
                state.players[index].waiting = true
            }
            publish()
            return
        }

        // Seats are capped at eight; the ninth hello is turned away.
        let seated = state.players.filter { !$0.left }.count
        guard seated < BATTLE_MAX_PLAYERS else {
            reject(sender, reason: "That battle is full.")
            return
        }

        state.players.append(
            BattlePlayer(
                id: sender,
                name: displayName(sender),
                host: false,
                // Joining mid-game means spectating until the next deal.
                waiting: state.phase == .playing))
        publish()
    }

    private func handleProgress(from sender: PlayerID, score: Int, buried: Bool, tiles: Int) {
        guard state.phase == .playing,
            let index = state.players.firstIndex(where: { $0.id == sender }),
            !state.players[index].waiting
        else { return }

        state.players[index].score = max(0, score)
        state.players[index].tiles = max(0, tiles)
        // Clients self-report burial; the host merely records it — and the
        // stamp is write-once, so a regressing report can't corrupt standings.
        if buried, !state.players[index].buried {
            state.players[index].buried = true
            markOut(index)
        }
        checkOver()
        publish()
    }

    /// A volley: clamp it, split it across everyone still standing, and hand
    /// each target only its own share (spec §2).
    private func relayAttack(from sender: PlayerID, count: Int) {
        guard state.phase == .playing, count > 0,
            let attacker = state.players.first(where: { $0.id == sender }),
            !attacker.waiting, !attacker.buried, !attacker.left
        else { return }

        let targets = state.players.filter {
            $0.id != sender && !$0.waiting && !$0.buried && !$0.left
        }
        guard !targets.isEmpty else { return }

        let total = min(count, ATTACK_CLAMP)
        let shares = splitAttackTiles(
            count: Double(total), targets: targets.count, from: attackSpread)
        attackSpread += 1

        for (target, share) in zip(targets, shares) where share > 0 {
            if target.id == selfID {
                // The host plays too; its share never touches the wire.
                events.onAttack?(share)
            } else if let data = Wire.encode(HostMessage.attack(count: share)) {
                transport.send(data, to: [target.id])
            }
        }
    }

    // MARK: Host controls

    /// Deal a fresh game to everyone present. Anyone disconnected or counted
    /// out is purged first: a new game deals in only who's actually here.
    public func start() {
        let now = clock()
        let seed = makeSeed()
        state.players.removeAll { !$0.connected || $0.left }
        for index in state.players.indices {
            state.players[index].score = 0
            state.players[index].buried = false
            state.players[index].waiting = false
            state.players[index].tiles = 0
            state.players[index].outOrder = nil
        }
        graceUntil = [:]
        outCounter = 0
        attackSpread = 0
        state.phase = .playing
        state.game += 1
        state.winnerId = nil

        // `start` before `state`, relying on per-sender ordering — which
        // `.reliable` guarantees (spec §6).
        if let data = Wire.encode(HostMessage.start(seed: seed)) {
            transport.broadcast(data)
        }
        publish()
        events.onStart?(seed)
        lastPing = now
    }

    /// Everyone back to the lobby. Same roster reset, no seed.
    public func stop() {
        state.players.removeAll { !$0.connected || $0.left }
        for index in state.players.indices {
            state.players[index].score = 0
            state.players[index].buried = false
            state.players[index].waiting = false
            state.players[index].tiles = 0
            state.players[index].outOrder = nil
        }
        graceUntil = [:]
        outCounter = 0
        attackSpread = 0
        state.phase = .lobby
        state.winnerId = nil

        if let data = Wire.encode(HostMessage.stop) {
            transport.broadcast(data)
        }
        publish()
        events.onStop?()
    }

    /// The host's own board reporting in, the local equivalent of `progress`.
    public func reportSelf(score: Int, buried: Bool, tiles: Int) {
        handleProgress(from: selfID, score: score, buried: buried, tiles: tiles)
    }

    /// The host's own volley, which still goes through the same split.
    public func sendSelfAttack(_ count: Int) {
        relayAttack(from: selfID, count: count)
    }

    /// Ask a graced seat back in. On GameKit this pairs with
    /// `GKMatchmaker.addPlayers(to:)`, the documented re-entry path (§7.4);
    /// here it just reports who is still holdable.
    public var gracedSeats: [PlayerID] {
        graceUntil.keys.sorted()
    }

    // MARK: The clock

    /// Drive grace expiry, the heartbeat and the staleness sweep. Called from
    /// a timer in the app; called directly in tests.
    public func tick(at now: Date) {
        var changed = false

        for (player, deadline) in graceUntil where now >= deadline {
            graceUntil[player] = nil
            guard let index = state.players.firstIndex(where: { $0.id == player }) else { continue }
            // Grace ran out: their standing is fixed at this moment, and the
            // game plays on — a battle never pauses for a drop.
            state.players[index].left = true
            state.players[index].connected = false
            markOut(index)
            changed = true
        }

        // Silence outlasting the staleness cutoff is a dead link, whatever the
        // transport believes.
        for player in state.players where player.id != selfID && player.connected {
            guard let seen = lastSeen[player.id] else {
                lastSeen[player.id] = now
                continue
            }
            if now.timeIntervalSince(seen) > STALE_LINK_SECONDS {
                drop(player.id, at: now)
                changed = true
            }
        }

        if let last = lastPing, now.timeIntervalSince(last) >= PING_INTERVAL_SECONDS {
            lastPing = now
            if let data = Wire.encode(HostMessage.ping) {
                transport.broadcast(data)
            }
        }

        if changed {
            checkOver()
            publish()
        }
    }

    // MARK: Roster mechanics

    /// A link went down. Mid-game the seat is held; anywhere else the player
    /// simply leaves the roster (spec §5).
    private func drop(_ player: PlayerID, at now: Date) {
        guard let index = state.players.firstIndex(where: { $0.id == player }) else { return }
        lastSeen[player] = nil

        guard state.phase == .playing, !state.players[index].waiting else {
            remove(player)
            return
        }

        state.players[index].connected = false
        graceUntil[player] = now.addingTimeInterval(RECONNECT_GRACE_SECONDS)
        publish()
    }

    private func remove(_ player: PlayerID) {
        guard let index = state.players.firstIndex(where: { $0.id == player }) else { return }
        graceUntil[player] = nil
        lastSeen[player] = nil

        if state.phase == .playing, !state.players[index].waiting {
            // Mid-game a leaver keeps their entry so they still place in the
            // standings.
            state.players[index].connected = false
            state.players[index].left = true
            markOut(index)
        } else {
            state.players.remove(at: index)
        }
        checkOver()
        publish()
    }

    /// Stamp the elimination order — once, and monotonically.
    private func markOut(_ index: Int) {
        guard state.players[index].outOrder == nil else { return }
        outCounter += 1
        state.players[index].outOrder = outCounter
    }

    /// Decided when at least two contestants started and one at most is still
    /// standing; a simultaneous fall is a draw.
    private func checkOver() {
        guard state.phase == .playing else { return }
        let contestants = state.players.filter { !$0.waiting }
        guard battleOver(contestants) else { return }
        state.phase = .finished
        state.winnerId = battleWinner(contestants)?.id
    }

    private func reject(_ player: PlayerID, reason: String) {
        guard let data = Wire.encode(HostMessage.reject(reason: reason)) else { return }
        transport.send(data, to: [player])
    }

    /// One full snapshot to everyone, on every change. No deltas, no
    /// sequence numbers — correct because delivery is ordered (spec §6).
    private func publish() {
        if let data = Wire.encode(HostMessage.state(state)) {
            transport.broadcast(data)
        }
        events.onState?(state)
    }
}
