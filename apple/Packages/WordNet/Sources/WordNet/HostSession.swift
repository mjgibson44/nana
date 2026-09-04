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

/// How often the host repeats "I am the referee" to a connected player who
/// still hasn't taken a seat. A player whose first hello landed before the
/// host session existed — or whose copy of the announcement was lost in a
/// hand-off — is picked up on the next repeat rather than never.
public let HOST_REANNOUNCE_SECONDS: TimeInterval = 1

/// How a random match deals itself: nobody in a lobby of strangers presses
/// START, so the host's session watches the roster and starts on a rule.
public enum AutoStartRule: Equatable {
    /// Two players, dealt the moment the second is seated.
    case duel
    /// Three or more asked for; dealt once the door has been quiet for
    /// `PARTY_IDLE_SECONDS` — and with two if a third came and went, rather
    /// than stranding the pair.
    case party
}

/// How long a party's door stays open after the last arrival.
public let PARTY_IDLE_SECONDS: TimeInterval = 20

/// The countdown every screen shows once a self-starting lobby is decided.
public let START_COUNTDOWN_SECONDS = 5

/// What the host tells its own game layer. The host plays too, so its own
/// attacks and state arrive through callbacks rather than the wire.
public struct HostEvents {
    public var onState: ((BattleState) -> Void)?
    public var onStart: ((String) -> Void)?
    public var onStop: (() -> Void)?
    /// The host's own share of a rival's volley.
    public var onAttack: ((Int) -> Void)?
    /// Another player with a *lower* id is also refereeing. Lowest id wins,
    /// so this session should stand down and become that player's client.
    public var onYield: ((PlayerID) -> Void)?

    public init(
        onState: ((BattleState) -> Void)? = nil,
        onStart: ((String) -> Void)? = nil,
        onStop: (() -> Void)? = nil,
        onAttack: ((Int) -> Void)? = nil,
        onYield: ((PlayerID) -> Void)? = nil
    ) {
        self.onState = onState
        self.onStart = onStart
        self.onStop = onStop
        self.onAttack = onAttack
        self.onYield = onYield
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
    /// When each unseated player was last told who referees, for the repeat.
    private var announcedAt: [PlayerID: Date] = [:]
    /// Players this lobby turned away: not worth announcing to again.
    private var rejected: Set<PlayerID> = []

    /// The rule this lobby deals itself by, if it does.
    public let autoStart: AutoStartRule?
    /// How long a dropped mid-game seat is held. The web's 30 seconds by
    /// default; a match of strangers holds for less, since there is no road
    /// back in for them anyway.
    public let graceSeconds: TimeInterval
    /// Whether a player who arrives mid-game is seated to spectate until the
    /// next deal. True for friends; a random match turns them away instead,
    /// since a stranger shouldn't sit through a game they never saw start.
    public let admitsMidGame: Bool
    /// When the roster last grew — the party door's clock.
    private var lastArrival: Date
    /// When the running countdown deals, if one is running.
    private var countdownEndsAt: Date?

    public init(
        transport: BattleTransport,
        displayName: @escaping (PlayerID) -> String,
        makeSeed: @escaping () -> String = { randomSeed() },
        clock: @escaping () -> Date = { .now },
        autoStart: AutoStartRule? = nil,
        graceSeconds: TimeInterval = RECONNECT_GRACE_SECONDS,
        admitsMidGame: Bool = true
    ) {
        self.transport = transport
        self.displayName = displayName
        self.makeSeed = makeSeed
        self.clock = clock
        self.autoStart = autoStart
        self.graceSeconds = graceSeconds
        self.admitsMidGame = admitsMidGame
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
        let now = clock()
        lastPing = now
        lastArrival = now

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
        let now = clock()
        if let players {
            transport.send(data, to: players)
            for player in players { announcedAt[player] = now }
        } else {
            transport.broadcast(data)
            for player in transport.remotePlayerIDs { announcedAt[player] = now }
        }
    }

    // MARK: Receiving

    private func receive(_ data: Data, from sender: PlayerID) {
        // Any traffic at all proves the link is alive.
        lastSeen[sender] = clock()
        guard let message = Wire.decode(ClientMessage.self, from: data) else {
            // Not a client speaking: perhaps another referee. Two hosts can
            // only meet in a match with no natural owner, and the rule every
            // client already applies settles it — the lowest id referees.
            if case let .host(proto)? = Wire.decode(HostMessage.self, from: data),
                proto == PROTOCOL_VERSION, sender < selfID
            {
                events.onYield?(sender)
            }
            return
        }

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
        // A stranger who lands after the deal has nothing to watch for.
        guard admitsMidGame || state.phase == .lobby else {
            reject(sender, reason: "That battle already started.")
            return
        }

        state.players.append(
            BattlePlayer(
                id: sender,
                name: displayName(sender),
                host: false,
                // Joining mid-game means spectating until the next deal.
                waiting: state.phase == .playing))
        announcedAt[sender] = nil
        lastArrival = clock()
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
        countdownEndsAt = nil
        state.countdown = nil

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
        countdownEndsAt = nil
        state.countdown = nil
        // Reopening the lobby gives a party its breather again rather than
        // dealing the instant everyone is back.
        lastArrival = clock()

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

        // Anyone connected but still standing in the doorway is told again
        // who referees: their hello may have beaten this session into
        // existence, or their copy of the announcement may have been lost.
        let seated = Set(state.players.map(\.id))
        let unseated = transport.remotePlayerIDs.filter {
            !seated.contains($0) && !rejected.contains($0)
        }
        let due = unseated.filter { player in
            guard let last = announcedAt[player] else { return true }
            return now.timeIntervalSince(last) >= HOST_REANNOUNCE_SECONDS
        }
        if !due.isEmpty {
            announceHost(to: due)
        }

        if changed {
            checkOver()
            publish()
        }

        if autoStart != nil {
            advanceAutoStart(at: now)
        }
    }

    // MARK: Dealing itself

    /// The random-match rule: decide, count down, deal. Runs on the host's
    /// tick, in the lobby only, off the injected clock.
    private func advanceAutoStart(at now: Date) {
        guard let autoStart, state.phase == .lobby else { return }
        let seated = state.players.filter { $0.connected && !$0.left }.count

        if let endsAt = countdownEndsAt {
            // Counting down. A field that shrinks below a battle stops it;
            // nobody is dealt a game against no one.
            guard seated >= BATTLE_MIN_PLAYERS else {
                countdownEndsAt = nil
                state.countdown = nil
                publish()
                return
            }
            let remaining = endsAt.timeIntervalSince(now)
            guard remaining > 0 else {
                start()
                return
            }
            let shown = Int(remaining.rounded(.up))
            if state.countdown != shown {
                state.countdown = shown
                publish()
            }
            return
        }

        let ready: Bool
        switch autoStart {
        case .duel:
            ready = seated >= BATTLE_MIN_PLAYERS
        case .party:
            // The door has been quiet long enough, and there's a battle's
            // worth of people behind it — two if a third came and went.
            ready = seated >= BATTLE_MIN_PLAYERS
                && now.timeIntervalSince(lastArrival) >= PARTY_IDLE_SECONDS
        }
        guard ready else { return }
        countdownEndsAt = now.addingTimeInterval(TimeInterval(START_COUNTDOWN_SECONDS))
        state.countdown = START_COUNTDOWN_SECONDS
        publish()
    }

    // MARK: Roster mechanics

    /// A link went down. Mid-game the seat is held; anywhere else the player
    /// simply leaves the roster (spec §5).
    private func drop(_ player: PlayerID, at now: Date) {
        announcedAt[player] = nil
        rejected.remove(player)
        guard let index = state.players.firstIndex(where: { $0.id == player }) else { return }
        lastSeen[player] = nil

        guard state.phase == .playing, !state.players[index].waiting else {
            remove(player)
            return
        }

        state.players[index].connected = false
        graceUntil[player] = now.addingTimeInterval(graceSeconds)
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
        rejected.insert(player)
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
