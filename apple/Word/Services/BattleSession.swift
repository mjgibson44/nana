import Foundation
import Observation
import WordCore
import WordNet

/// The app's side of a battle — or an Occupy game, which shares the room:
/// owns whichever `WordNet` session this player is (host or client), drives
/// its clock, and wires it to the board.
///
/// `WordNet` deliberately knows nothing about transports beyond
/// `BattleTransport`, and nothing about the game beyond scores and counts.
/// This is where those two halves meet — which is also why it takes a
/// transport rather than making one: a `MemoryMesh` here makes a whole battle
/// playable in tests, and the GameKit adapter becomes a drop-in that changes
/// nothing below this line (plan §7.5 — only the adapter needs devices).
///
/// The role can change. A match of strangers has no natural host, so everyone
/// starts as a client and the lowest id is told to take the chair
/// (`becomeHost`); if two ever claim it, the higher one stands down
/// (`yield`). A friends' lobby never does either — its host opened the room.
@Observable @MainActor
final class BattleSession {
    /// Who this player is in the match.
    enum Role: Equatable {
        case host
        case client
    }

    /// How long a random lobby's host sits with nobody else in it before the
    /// app is told to look for another match instead.
    static let aloneSeconds: TimeInterval = 10
    /// How long a random match holds a dropped mid-game seat. Strangers have
    /// no road back in, so a shorter grace than friends get.
    static let strangerGraceSeconds: TimeInterval = 10

    /// Which game this room plays: a Battle, or Occupy. The host's rules and
    /// the lobby's size follow from it.
    let mode: GameMode
    /// The rule a random match deals itself by; nil for a friends' lobby,
    /// where the host presses START.
    let autoStart: AutoStartRule?
    private(set) var role: Role
    private(set) var state: BattleState?
    private(set) var hostID: PlayerID?
    /// Set when the host refuses us — a version mismatch or a full lobby.
    private(set) var rejection: String?
    private(set) var isReconnecting = false
    /// The seed of the game in progress, if any.
    private(set) var seed: String?

    private let clock: () -> Date
    private let transport: BattleTransport
    private let displayName: (PlayerID) -> String
    private let makeSeed: () -> String
    private let announceTimeout: TimeInterval
    private var host: HostSession?
    private var client: ClientSession?
    private weak var model: GameModel?
    private var ticker: Task<Void, Never>?
    /// The phase the last snapshot was in, so the finish is handled once, on
    /// the way in, rather than on every broadcast after it.
    private var lastPhase: BattlePhase?
    /// Likewise for the countdown: its beginning is an event, its ticks are not.
    private var lastCountdown: Int?
    /// Since when this random lobby has had nobody in it but its host.
    private var aloneSince: Date?
    private var abandonedReported = false

    /// Told when a game starts, so the router can show the board.
    var onGameStart: (() -> Void)?
    /// Told when the host gathers everyone back to the lobby.
    var onReturnToLobby: (() -> Void)?
    /// Told the moment a self-starting lobby begins counting down — the door
    /// closes here, on every device.
    var onCountdownBegin: (() -> Void)?
    /// Told when this player takes the chair in a match nobody opened.
    var onBecameHost: (() -> Void)?
    /// Told when a random lobby has been empty but for us for a while: the
    /// door is shut, so the only way on is another search.
    var onAbandoned: (() -> Void)?

    init(
        role: Role,
        mode: GameMode = .battle,
        transport: BattleTransport,
        model: GameModel,
        displayName: @escaping (PlayerID) -> String = { _ in "Player" },
        makeSeed: @escaping () -> String = { randomSeed() },
        /// One clock for the whole battle — the sessions' graces and pings,
        /// and the board's drip. Injectable so a test can play a three-minute
        /// battle without waiting three minutes.
        clock: @escaping () -> Date = { .now },
        autoStart: AutoStartRule? = nil,
        announceTimeout: TimeInterval = HOST_ANNOUNCE_TIMEOUT_SECONDS
    ) {
        self.role = role
        self.mode = mode
        self.transport = transport
        self.model = model
        self.displayName = displayName
        self.makeSeed = makeSeed
        self.clock = clock
        self.autoStart = autoStart
        self.announceTimeout = announceTimeout

        switch role {
        case .host:
            let session = makeHostSession()
            host = session
            client = nil
            hostID = session.selfID
            state = session.state
        case .client:
            client = makeClientSession()
            host = nil
        }

        bind()
        // A host owns the lobby from the moment it exists, and has to say so:
        // a mesh has no marked referee (plan §7.2).
        host?.announceHost()
        model.onBattleAttack = { [weak self] count in
            self?.sendAttack(count)
        }
        model.onOccupyPlace = { [weak self] serial, placement in
            self?.sendPlacement(serial: serial, placement: placement)
        }
    }

    var isOccupy: Bool { mode == .occupy }

    private var minPlayers: Int {
        mode == .occupy ? OCCUPY_MIN_PLAYERS : BATTLE_MIN_PLAYERS
    }

    var selfID: PlayerID { transport.localPlayerID }
    var isHost: Bool { role == .host }
    /// Whether this match deals itself rather than waiting on a START.
    var dealsItself: Bool { autoStart != nil }
    /// Seconds until a self-starting lobby deals, while it's counting down.
    var countdown: Int? { state?.countdown }

    /// This player's seat in the roster, if the host has told us about it.
    var selfSeat: BattlePlayer? {
        state?.players.first { $0.id == selfID }
    }

    /// Watching rather than playing — buried, or joined mid-game (App.tsx:1605).
    var isSpectating: Bool {
        guard state?.phase == .playing else { return false }
        if selfSeat?.waiting == true { return true }
        return model?.isComplete == true && model?.endReason == .buried
    }

    var canStart: Bool {
        guard isHost, !dealsItself, let state, state.phase == .lobby else { return false }
        return state.players.filter { !$0.left }.count >= minPlayers
    }

    // MARK: Standings

    /// Everyone dealt into this game, standing or fallen.
    var contestants: [BattlePlayer] {
        (state?.players ?? []).filter { !$0.waiting }
    }

    var isFinished: Bool { state?.phase == .finished }

    var selfWon: Bool {
        guard let winner = state?.winnerId else { return false }
        return winner == selfID
    }

    /// The field ranked: the last one standing first, then everyone else in
    /// reverse order of falling — the results table.
    var standings: [RankedPlayer<BattlePlayer>] {
        rankByElimination(contestants)
    }

    /// Where this player stands right now, 1-based. While the battle runs it
    /// is the live order of everyone still standing, by score; once this
    /// player has fallen — or the battle is decided — it is their final
    /// placing, which the fall order fixes the moment they go out.
    var position: Int? {
        if isOccupy {
            guard let occupy = state?.occupy, let seat = occupy.seat(of: selfID) else { return nil }
            return occupyRanking(occupy, left: seatsLeft).first { $0.seat == seat }?.rank
        }
        let field = contestants
        guard let me = field.first(where: { $0.id == selfID }) else { return nil }
        if isFinished || me.outOrder != nil {
            return standings.first { $0.player.id == selfID }?.rank
        }
        let ahead = field.filter { $0.outOrder == nil && $0.score > me.score }.count
        return ahead + 1
    }

    /// One row of Occupy's standings: the seat, its rank and its value.
    struct OccupyStandingRow: Identifiable, Equatable {
        var id: String { player.id }
        var player: BattlePlayer
        var seat: Int
        var rank: Int
        var value: Int
    }

    /// Occupy's field ranked by value — the results table, and the live
    /// order while it plays.
    var occupyStandings: [OccupyStandingRow] {
        guard let occupy = state?.occupy else { return [] }
        return occupyRanking(occupy, left: seatsLeft).compactMap { standing in
            let id = occupy.seats[standing.seat]
            guard let player = state?.players.first(where: { $0.id == id }) else { return nil }
            return OccupyStandingRow(
                player: player, seat: standing.seat, rank: standing.rank,
                value: occupy.scores[standing.seat])
        }
    }

    /// The seats whose players have walked out, ranked last whatever they own.
    private var seatsLeft: Set<Int> {
        guard let occupy = state?.occupy else { return [] }
        return Set(contestants.filter(\.left).compactMap { occupy.seat(of: $0.id) })
    }

    /// A battle can only go again with enough seats still filled.
    var canRestart: Bool {
        guard isHost, isFinished, let state else { return false }
        return state.players.filter { $0.connected && !$0.left }.count >= minPlayers
    }

    // MARK: Driving it

    /// Start the heartbeat.
    ///
    /// Cancelled by `leave()` rather than a `deinit` — a nonisolated `deinit`
    /// can't touch main-actor state under strict concurrency, and the router
    /// owns the session's lifetime anyway. Both sessions need a regular
    /// `tick` — the host to expire seat graces and ping, the client to notice
    /// a stale link and to fall back on host election when no announcement
    /// arrives.
    func run() {
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                guard let self else { return }
                self.tick(at: .now)
            }
        }
    }

    func tick(at now: Date) {
        // Taken before ticking: a tick can swap the role underneath itself
        // (a client told to host, a host told to yield), and the session
        // that was just replaced must not be driven again this pass.
        let host = host
        let client = client
        host?.tick(at: now)
        client?.tick(at: now)
        if let client = self.client { isReconnecting = client.isReconnecting }
        reportProgress()
        watchForAbandonment(at: now)
    }

    func start() {
        guard canStart else { return }
        host?.start()
    }

    /// The host deals everyone into another game straight from the results.
    func restart() {
        guard canRestart else { return }
        host?.start()
    }

    /// The host gathers everyone back in the lobby.
    func toLobby() {
        guard isHost else { return }
        host?.stop()
    }

    func leave() {
        ticker?.cancel()
        ticker = nil
        client?.leave()
        // Say so to the match as well as to the host: everyone else sees the
        // seat empty now rather than when the transport notices on its own.
        transport.disconnect()
        model?.onBattleAttack = nil
        model?.onOccupyPlace = nil
    }

    // MARK: Wiring

    private func makeHostSession() -> HostSession {
        // Occupy's referee judges words against the host's dictionary. If
        // it hasn't loaded yet, the client's own check is trusted rather
        // than every word being called fake.
        let rules: BattleRules =
            mode == .occupy
            ? .occupy(isWord: { [weak model] word in model?.dictionary?.contains(word) ?? true })
            : .battle
        return HostSession(
            transport: transport, displayName: displayName, makeSeed: makeSeed,
            clock: clock, autoStart: autoStart,
            graceSeconds: dealsItself ? Self.strangerGraceSeconds : RECONNECT_GRACE_SECONDS,
            // A stranger who lands after the deal has nothing to watch for.
            admitsMidGame: !dealsItself,
            rules: rules)
    }

    private func makeClientSession() -> ClientSession {
        ClientSession(transport: transport, clock: clock, announceTimeout: announceTimeout)
    }

    private func bind() {
        host?.events = HostEvents(
            onState: { [weak self] state in self?.adopt(state) },
            onStart: { [weak self] seed in self?.beginGame(seed: seed) },
            onStop: { [weak self] in self?.endGame() },
            onAttack: { [weak self] count in self?.model?.receiveAttack(count) },
            onYield: { [weak self] lower in self?.yield(to: lower) },
            onPlaced: { [weak self] serial in self?.model?.confirmPlacement(serial: serial) },
            onRefused: { [weak self] serial, reason in
                self?.model?.refusePlacement(serial: serial, reason: reason)
            })

        client?.events = ClientEvents(
            onState: { [weak self] state in self?.adopt(state) },
            onStart: { [weak self] seed in self?.beginGame(seed: seed) },
            onStop: { [weak self] in self?.endGame() },
            onAttack: { [weak self] count in self?.model?.receiveAttack(count) },
            onRejected: { [weak self] reason in self?.rejection = reason },
            onHostElected: { [weak self] id in self?.hostID = id },
            onPlaced: { [weak self] serial in self?.model?.confirmPlacement(serial: serial) },
            onRefused: { [weak self] serial, reason in
                self?.model?.refusePlacement(serial: serial, reason: reason)
            },
            onShouldHost: { [weak self] in self?.becomeHost() })
    }

    /// Nobody announced and we have the lowest id: take the chair. The
    /// client session is dropped and a host session stood up on the same
    /// transport, which re-takes the transport's handlers as it's built.
    private func becomeHost() {
        guard role == .client else { return }
        client?.events = ClientEvents()
        client = nil
        let session = makeHostSession()
        host = session
        role = .host
        hostID = session.selfID
        rejection = nil
        isReconnecting = false
        lastPhase = nil
        lastCountdown = nil
        state = session.state
        bind()
        session.announceHost()
        onBecameHost?()
    }

    /// Another referee with a lower id is out there: stand down and follow
    /// them. Lowest id wins, on every device, so the two lobbies fold into
    /// one without anyone talking about it.
    private func yield(to lower: PlayerID) {
        guard role == .host else { return }
        host?.events = HostEvents()
        host = nil
        let session = makeClientSession()
        client = session
        role = .client
        hostID = nil
        lastPhase = nil
        lastCountdown = nil
        state = nil
        aloneSince = nil
        bind()
        session.follow(host: lower)
    }

    /// The host's latest snapshot. In Occupy every one carries the board,
    /// and the board it carries goes straight under this player's own words.
    /// Two transitions reach past the roster on any board: into `finished`
    /// (whoever is still standing is finished there too), and into a
    /// countdown (the door closes).
    private func adopt(_ state: BattleState) {
        let previousPhase = lastPhase
        let previousCountdown = lastCountdown
        self.state = state
        lastPhase = state.phase
        lastCountdown = state.countdown
        if previousCountdown == nil, state.countdown != nil {
            onCountdownBegin?()
        }
        if isOccupy, state.phase != .lobby, let occupy = state.occupy, model?.isOccupy == true,
            model?.seed == seed
        {
            model?.adoptOccupy(occupy, now: clock())
        }
        guard state.phase == .finished, previousPhase != .finished else { return }
        if isOccupy {
            model?.finishOccupy(won: state.winnerId == selfID, players: contestants.count)
        } else {
            model?.finishBattle(won: state.winnerId == selfID, players: contestants.count)
        }
    }

    private func beginGame(seed: String) {
        self.seed = seed
        // A seat that joined mid-game watches this one out (`waiting`); its
        // board stays empty rather than dealing tiles it can't play.
        if isOccupy {
            model?.newOccupy(
                seed: seed, selfID: selfID, state: state?.occupy,
                spectating: selfSeat?.waiting == true, now: clock())
        } else {
            model?.newBattle(
                seed: seed, selfID: selfID, spectating: selfSeat?.waiting == true, now: clock())
        }
        onGameStart?()
    }

    private func endGame() {
        seed = nil
        onReturnToLobby?()
    }

    /// The host splits an attack across the field; a client hands it up.
    private func sendAttack(_ count: Int) {
        guard count > 0 else { return }
        host?.sendSelfAttack(count)
        client?.sendAttack(count)
    }

    /// An Occupy word: the host judges its own; a client sends it up.
    private func sendPlacement(serial: Int, placement: OccupyPlacement) {
        host?.placeSelf(serial: serial, placement: placement)
        client?.sendPlacement(serial: serial, placement: placement)
    }

    /// Keep the roster's scores and pile gauges current. Both sessions take
    /// the same three facts; the host applies them to its own seat directly.
    /// Occupy's scores are the board's, which the host already holds.
    private func reportProgress() {
        guard let model, state?.phase == .playing, !isOccupy else { return }
        let buried = model.isComplete && model.endReason == .buried
        host?.reportSelf(score: model.score, buried: buried, tiles: model.rack.count)
        client?.reportProgress(score: model.score, buried: buried, tiles: model.rack.count)
    }

    /// A random lobby whose host has been alone too long — the opponent
    /// left, or never arrived — is reported once, so the app can search
    /// again instead of leaving them staring at an empty room.
    private func watchForAbandonment(at now: Date) {
        guard dealsItself, isHost, !abandonedReported, let state, state.phase == .lobby else {
            aloneSince = nil
            return
        }
        let seated = state.players.filter { $0.connected && !$0.left }.count
        guard seated < minPlayers else {
            aloneSince = nil
            return
        }
        guard let since = aloneSince else {
            aloneSince = now
            return
        }
        if now.timeIntervalSince(since) >= Self.aloneSeconds {
            abandonedReported = true
            onAbandoned?()
        }
    }
}
