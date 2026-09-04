import GameKit
import SwiftUI
import WordCore

/// The app's one router state, plus the overlays each screen raises.
enum Route: Equatable {
    case home
    /// Getting into a battle: opening a room or joining one.
    case battleEntry
    /// In a battle's lobby, waiting for the host to start.
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

    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            switch route {
            case .home:
                HomeScreen(
                    hasSavedGame: savedGame != nil,
                    showsGameCenter: gameCenter.isSignedIn,
                    onResume: resumeSavedGame,
                    onSolo: { startSolo(pace: settings.pace) },
                    onBattle: chooseBattle)

            case .battleEntry:
                BattleEntryScreen(
                    supportsPartyCodes: Matchmaking.supportsPartyCodes,
                    partyCode: partyCode,
                    isBusy: battleBusy,
                    error: battleError,
                    onHost: hostBattle,
                    onJoin: joinBattle(code:),
                    onInvite: inviteToBattle,
                    onClose: leaveBattle)

            case .battleLobby:
                BattleLobbyScreen(
                    state: battle?.state,
                    selfID: battle?.selfID ?? "",
                    isHost: battle?.isHost ?? false,
                    canStart: battle?.canStart ?? false,
                    isReconnecting: battle?.isReconnecting ?? false,
                    rejection: battle?.rejection,
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
            return (match, .host)
        }
    }

    private func joinBattle(code: String) {
        guard #available(iOS 26, macOS 26, *) else { return }
        runBattleSetup {
            let activity = try await matchmaking.joinParty(code: code)
            let match = try await matchmaking.match(for: activity)
            return (match, .client)
        }
    }

    /// Game Center's own invite sheet — the road that works on every OS the
    /// app supports. Whoever sends the invite referees.
    private func inviteToBattle() {
        runBattleSetup {
            let match = try await matchmaking.findMatchByInvite()
            return (match, .host)
        }
    }

    /// The shared shape of every road in: show it's working, form a match,
    /// build the session, land in the lobby.
    private func runBattleSetup(
        _ form: @escaping () async throws -> (GKMatch, BattleSession.Role)
    ) {
        battleBusy = true
        battleError = nil
        Task {
            do {
                let (match, role) = try await form()
                startBattle(match: match, role: role)
            } catch let failure as Matchmaking.Failure {
                partyCode = nil
                if case .cancelled = failure {
                    // Backing out of matchmaking isn't an error worth saying.
                    battleError = nil
                } else if case let .unavailable(message) = failure {
                    battleError = message
                } else if case let .failed(message) = failure {
                    battleError = message
                }
            } catch {
                partyCode = nil
                battleError = error.localizedDescription
            }
            battleBusy = false
        }
    }

    private func startBattle(match: GKMatch, role: BattleSession.Role) {
        let transport = GameKitTransport(match: match)
        let session = BattleSession(
            role: role,
            transport: transport,
            model: model,
            displayName: { transport.displayName(for: $0) })
        session.onGameStart = { route = .game }
        session.onReturnToLobby = { route = .battleLobby }
        session.run()
        battle = session
        route = .battleLobby
    }

    /// Out of a battle by any road — backing out of the entry screen, leaving
    /// the lobby, or quitting a game.
    private func leaveBattle() {
        battle?.leave()
        battle = nil
        partyCode = nil
        battleError = nil
        battleBusy = false
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
