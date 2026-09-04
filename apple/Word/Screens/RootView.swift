import GameKit
import SwiftUI
import WordCore
import WordNet

/// The app's one router state, plus the overlays each screen raises.
enum Route: Equatable {
    case home
    /// Picking a Solo game's speed, on the way in.
    case soloSetup
    /// Getting into a battle: finding strangers, opening a room, or joining one.
    case battleEntry
    /// In a battle's lobby, waiting for the host — or the countdown — to start it.
    case battleLobby
    case game
}

/// The root: owns the route, the model, and the services the game plays
/// through.
struct RootView: View {
    @State private var route: Route = .home
    @State private var model = GameModel()
    @State private var settings = AppSettings()
    @State private var audio = AudioEngine()
    // iCloud-backed: each device writes only its own blob, so the merge
    // (§9.1) is what makes two devices add up.
    @State private var progression = Progression(sync: UbiquitousSyncStore())
    @State private var gameCenter = GameCenter()
    @State private var matchmaking = Matchmaking()
    @State private var battle: BattleSession?
    @State private var battleBusy = false
    @State private var battleError: String?
    @State private var partyCode: String?
    @State private var battleDoorNotice = false
    @State private var savedGame: SavedSoloGame?
    /// The random match being looked for, while one is.
    @State private var searching: RandomMatchKind?
    @State private var searchStatus: String?
    /// The road into a battle that's underway, so backing out can cancel it —
    /// and a match that lands for an abandoned attempt is recognised as such.
    @State private var setupTask: Task<Void, Never>?
    @State private var setupGeneration = 0

    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            switch route {
            case .home:
                HomeScreen(
                    hasSavedGame: savedGame != nil,
                    showsGameCenter: gameCenter.isSignedIn,
                    onResume: resumeSavedGame,
                    onSolo: { route = .soloSetup },
                    onBattle: chooseBattle)

            case .soloSetup:
                SoloSetupScreen(
                    pace: settings.pace,
                    onPlay: startSolo(pace:),
                    onClose: { route = .home })

            case .battleEntry:
                BattleEntryScreen(
                    supportsPartyCodes: Matchmaking.supportsPartyCodes,
                    partyCode: partyCode,
                    searching: searching,
                    searchStatus: searchStatus,
                    isBusy: battleBusy,
                    error: battleError,
                    onHost: hostBattle,
                    onJoin: joinBattle(code:),
                    onInvite: inviteToBattle,
                    onDuel: { findRandom(.duel) },
                    onParty: { findRandom(.party) },
                    onCancelSearch: cancelSearch,
                    onClose: leaveBattle)

            case .battleLobby:
                BattleLobbyScreen(
                    state: battle?.state,
                    selfID: battle?.selfID ?? "",
                    isHost: battle?.isHost ?? false,
                    canStart: battle?.canStart ?? false,
                    isReconnecting: battle?.isReconnecting ?? false,
                    rejection: battle?.rejection,
                    autoStart: battle?.autoStart,
                    countdown: battle?.countdown,
                    onStart: { battle?.start() },
                    onLeave: leaveBattle)

            case .game:
                GameScreen(
                    model: model,
                    battle: battle,
                    onLeave: leaveGame,
                    onNewGame: startSolo(pace:))
            }

            // Battle is the one mode that genuinely needs an identity, so it
            // is the only place sign-in is ever insisted on (§7.1).
            if battleDoorNotice {
                NoticeCard(text: gameCenter.battleBlockedReason ?? "") {
                    battleDoorNotice = false
                }
            }
        }
        .task {
            savedGame = settings.loadSavedGame()
            // Kicked off at launch and never blocking: Solo plays signed out
            // (§7.1), and anything earned meanwhile is held by Progression
            // and flushed if this succeeds.
            gameCenter.authenticate(feeding: progression)
            model.cues = audio
            audio.isSoundEnabled = { [settings] in settings.soundEnabled }
            audio.isHapticsEnabled = { [settings] in settings.hapticsEnabled }
            model.onFinish = { outcome in
                recordFinish(outcome)
            }
            // A development hook: `WORD_AUTOSTART=solo` in the launch
            // environment opens straight onto a game, so a simulator can be
            // screenshotted without a finger on it. Ignored otherwise.
            if ProcessInfo.processInfo.environment["WORD_AUTOSTART"] == "solo" {
                startSolo(pace: settings.pace)
            }
        }
        // The OS can kill a backgrounded app at any moment, so the in-progress
        // game is written out as it leaves the screen, not on the way down
        // (plan §6.1).
        .onChange(of: scenePhase) { _, phase in
            guard phase != .active else { return }
            persistGame()
        }
    }

    // MARK: Solo

    private func startSolo(pace: SoloPace) {
        // This is the one moment a player says what they want, so it's the
        // only one worth remembering.
        settings.pace = pace
        settings.save(nil)
        savedGame = nil
        model.newGame(pace: pace)
        route = .game
    }

    /// Every finished game lands here — the local stats, and the Game Center
    /// submission that hangs off the same funnel.
    private func recordFinish(_ outcome: GameOutcome) {
        // Cross-device progress, achievements, and the leaderboard queue —
        // all of which work signed out and flush when auth arrives (§7.1).
        let recorded = progression.record(outcome)
        if !recorded.completed.isEmpty {
            model.announceAchievements(recorded.completed)
        }
        settings.record(score: outcome.score, words: outcome.words)
        // A finished game is not a game to come back to.
        settings.save(nil)
    }

    // MARK: Battle (plan §7.3)

    private func chooseBattle() {
        if gameCenter.battleBlockedReason != nil {
            battleDoorNotice = true
        } else {
            battleError = nil
            partyCode = nil
            route = .battleEntry
        }
    }

    /// Open a room and show its code. The party exists before the match does —
    /// players join the party, and it becomes a `GKMatch` when we ask.
    private func hostBattle() {
        guard #available(iOS 26, macOS 26, *) else { return }
        runBattleSetup {
            let (activity, code) = try await matchmaking.hostParty()
            partyCode = code
            let match = try await matchmaking.match(for: activity)
            return (GameKitTransport(match: match), .host, nil)
        }
    }

    private func joinBattle(code: String) {
        guard #available(iOS 26, macOS 26, *) else { return }
        runBattleSetup {
            let activity = try await matchmaking.joinParty(code: code)
            let match = try await matchmaking.match(for: activity)
            return (GameKitTransport(match: match), .client, nil)
        }
    }

    /// Game Center's own invite sheet — the road that works on every OS the
    /// app supports. Whoever sends the invite referees.
    private func inviteToBattle() {
        runBattleSetup {
            let match = try await matchmaking.findMatchByInvite()
            return (GameKitTransport(match: match), .host, nil)
        }
    }

    /// Strangers. Nobody opened this room, so everyone enters as a client and
    /// the sessions elect a referee among themselves; the match then deals
    /// itself on the kind's rule.
    private func findRandom(_ kind: RandomMatchKind) {
        searching = kind
        searchStatus = "Finding players…"
        runBattleSetup {
            let transport = try await matchmaking.findRandomMatch(kind) { status in
                searchStatus = status
            }
            return (transport, .client, kind)
        }
    }

    /// Back out of a search, staying on the entry screen.
    private func cancelSearch() {
        abandonSetup()
        matchmaking.cancelSearch()
        searching = nil
        searchStatus = nil
        battleBusy = false
    }

    /// The room emptied out around us and its door is shut: look again for
    /// the same kind of match rather than leave the player in an empty lobby.
    private func searchAgain(_ kind: RandomMatchKind) {
        battle?.leave()
        battle = nil
        route = .battleEntry
        battleError = "Nobody else is here any more."
        findRandom(kind)
    }

    /// The shared shape of every road in: show it's working, form a match,
    /// build the session, land in the lobby. Only the newest attempt gets to
    /// touch the screen — an older one that finishes late is let go.
    private func runBattleSetup(
        _ form: @escaping () async throws -> (GameKitTransport, BattleSession.Role, RandomMatchKind?)
    ) {
        abandonSetup()
        let generation = setupGeneration
        battleBusy = true
        setupTask = Task {
            do {
                let (transport, role, kind) = try await form()
                guard generation == setupGeneration else {
                    transport.disconnect()
                    return
                }
                startBattle(transport: transport, role: role, kind: kind)
            } catch let failure as Matchmaking.Failure {
                guard generation == setupGeneration else { return }
                partyCode = nil
                switch failure {
                case .cancelled:
                    // Backing out of matchmaking isn't an error worth saying.
                    break
                case let .unavailable(message), let .failed(message):
                    battleError = message
                }
            } catch is CancellationError {
                // Backed out; the state was reset by whoever cancelled.
                return
            } catch {
                guard generation == setupGeneration else { return }
                partyCode = nil
                battleError = error.localizedDescription
            }
            guard generation == setupGeneration else { return }
            battleBusy = false
            searching = nil
            searchStatus = nil
        }
    }

    /// Cancel whatever road in is underway, and make sure it can't land later.
    private func abandonSetup() {
        setupTask?.cancel()
        setupTask = nil
        setupGeneration += 1
        battleError = nil
    }

    private func startBattle(
        transport: GameKitTransport, role: BattleSession.Role, kind: RandomMatchKind?
    ) {
        let session = BattleSession(
            role: role,
            transport: transport,
            model: model,
            displayName: { transport.displayName(for: $0) },
            autoStart: kind?.rule,
            announceTimeout: kind == nil
                ? HOST_ANNOUNCE_TIMEOUT_SECONDS : HOST_CLAIM_TIMEOUT_SECONDS)
        session.onGameStart = { route = .game }
        session.onReturnToLobby = { route = .battleLobby }
        if let kind {
            // The door closes on every device as the countdown begins; a
            // party's host holds it open until then.
            session.onCountdownBegin = { matchmaking.stopFilling(transport) }
            session.onBecameHost = {
                if kind == .party { matchmaking.keepFilling(transport, kind: kind) }
            }
            session.onAbandoned = { searchAgain(kind) }
        }
        session.run()
        battle = session
        route = .battleLobby
    }

    /// Out of a battle by any road — backing out of the entry screen, leaving
    /// the lobby, or quitting a game.
    private func leaveBattle() {
        abandonSetup()
        matchmaking.cancelSearch()
        battle?.leave()
        battle = nil
        partyCode = nil
        battleError = nil
        battleBusy = false
        searching = nil
        searchStatus = nil
        route = .home
    }

    // MARK: Leaving, resuming, persisting

    /// Done with a game by any road.
    private func leaveGame() {
        // A battle's board belongs to its battle: leaving the game leaves
        // the battle.
        if battle != nil {
            leaveBattle()
            return
        }
        persistGame()
        route = .home
    }

    private func resumeSavedGame() {
        guard let savedGame else { return }
        model.restore(savedGame)
        self.savedGame = nil
        route = .game
    }

    private func persistGame() {
        guard route == .game, battle == nil else { return }
        let snapshot = model.savedGame()
        settings.save(snapshot)
        savedGame = snapshot
    }
}
