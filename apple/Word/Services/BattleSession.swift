import Foundation
import Observation
import WordCore
import WordNet

/// The app's side of a battle: owns whichever `WordNet` session this player
/// is (host or client), drives its clock, and wires it to the board.
///
/// `WordNet` deliberately knows nothing about transports beyond
/// `BattleTransport`, and nothing about the game beyond scores and counts.
/// This is where those two halves meet — which is also why it takes a
/// transport rather than making one: a `MemoryMesh` here makes a whole battle
/// playable in tests, and the GameKit adapter becomes a drop-in that changes
/// nothing below this line (plan §7.5 — only the adapter needs devices).
@Observable @MainActor
final class BattleSession {
    /// Who this player is in the match.
    enum Role: Equatable {
        case host
        case client
    }

    let role: Role
    private(set) var state: BattleState?
    private(set) var hostID: PlayerID?
    /// Set when the host refuses us — a version mismatch or a full lobby.
    private(set) var rejection: String?
    private(set) var isReconnecting = false
    /// The seed of the game in progress, if any.
    private(set) var seed: String?

    private let clock: () -> Date
    private let transport: BattleTransport
    private let host: HostSession?
    private let client: ClientSession?
    private weak var model: GameModel?
    private var ticker: Task<Void, Never>?
    /// The phase the last snapshot was in, so the finish is handled once, on
    /// the way in, rather than on every broadcast after it.
    private var lastPhase: BattlePhase?

    /// Told when a game starts, so the router can show the board.
    var onGameStart: (() -> Void)?
    /// Told when the host gathers everyone back to the lobby.
    var onReturnToLobby: (() -> Void)?

    init(
        role: Role,
        transport: BattleTransport,
        model: GameModel,
        displayName: @escaping (PlayerID) -> String = { _ in "Player" },
        makeSeed: @escaping () -> String = { randomSeed() },
        /// One clock for the whole battle — the sessions' graces and pings,
        /// and the board's drip. Injectable so a test can play a three-minute
        /// battle without waiting three minutes.
        clock: @escaping () -> Date = { .now }
    ) {
        self.role = role
        self.transport = transport
        self.model = model
        self.clock = clock

        switch role {
        case .host:
            let session = HostSession(
                transport: transport, displayName: displayName, makeSeed: makeSeed,
                clock: clock)
            host = session
            client = nil
            hostID = session.selfID
            state = session.state
        case .client:
            let session = ClientSession(transport: transport, clock: clock)
            client = session
            host = nil
        }

        bind()
        // A host owns the lobby from the moment it exists, and has to say so:
        // a mesh has no marked referee (plan §7.2).
        host?.announceHost()
        model.onBattleAttack = { [weak self] count in
            self?.sendAttack(count)
        }
    }

    var selfID: PlayerID { transport.localPlayerID }
    var isHost: Bool { role == .host }

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
        guard isHost, let state, state.phase == .lobby else { return false }
        return state.players.filter { !$0.left }.count >= BATTLE_MIN_PLAYERS
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
        let field = contestants
        guard let me = field.first(where: { $0.id == selfID }) else { return nil }
        if isFinished || me.outOrder != nil {
            return standings.first { $0.player.id == selfID }?.rank
        }
        let ahead = field.filter { $0.outOrder == nil && $0.score > me.score }.count
        return ahead + 1
    }

    /// A battle can only go again with enough seats still filled.
    var canRestart: Bool {
        guard isHost, isFinished, let state else { return false }
        return state.players.filter { $0.connected && !$0.left }.count >= BATTLE_MIN_PLAYERS
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
        host?.tick(at: now)
        client?.tick(at: now)
        if let client { isReconnecting = client.isReconnecting }
        reportProgress()
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
        model?.onBattleAttack = nil
    }

    // MARK: Wiring

    private func bind() {
        host?.events = HostEvents(
            onState: { [weak self] state in self?.adopt(state) },
            onStart: { [weak self] seed in self?.beginGame(seed: seed) },
            onStop: { [weak self] in self?.endGame() },
            onAttack: { [weak self] count in self?.model?.receiveAttack(count) })

        client?.events = ClientEvents(
            onState: { [weak self] state in self?.adopt(state) },
            onStart: { [weak self] seed in self?.beginGame(seed: seed) },
            onStop: { [weak self] in self?.endGame() },
            onAttack: { [weak self] count in self?.model?.receiveAttack(count) },
            onRejected: { [weak self] reason in self?.rejection = reason },
            onHostElected: { [weak self] id in self?.hostID = id })
    }

    /// The host's latest snapshot. The one transition that reaches the board
    /// is into `finished`: whoever is still standing is finished there too.
    private func adopt(_ state: BattleState) {
        let previous = lastPhase
        self.state = state
        lastPhase = state.phase
        guard state.phase == .finished, previous != .finished else { return }
        model?.finishBattle(won: state.winnerId == selfID, players: contestants.count)
    }

    private func beginGame(seed: String) {
        self.seed = seed
        // A seat that joined mid-game watches this one out (`waiting`); its
        // board stays empty rather than dealing tiles it can't play.
        model?.newBattle(
            seed: seed, selfID: selfID, spectating: selfSeat?.waiting == true, now: clock())
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

    /// Keep the roster's scores and pile gauges current. Both sessions take
    /// the same three facts; the host applies them to its own seat directly.
    private func reportProgress() {
        guard let model, state?.phase == .playing else { return }
        let buried = model.isComplete && model.endReason == .buried
        host?.reportSelf(score: model.score, buried: buried, tiles: model.rack.count)
        client?.reportProgress(score: model.score, buried: buried, tiles: model.rack.count)
    }
}
