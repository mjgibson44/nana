import GameKit
import SwiftUI
import WordCore
import WordNet

/// The app's one router state, plus the overlays each screen raises.
enum Route: Equatable {
    case home
    /// Picking a Solo game's speed, on the way in.
    case soloSetup
    /// Getting into a battle (or an Occupy game): opening a room or joining one.
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
    /// Which game the room being opened or joined plays.
    @State private var battleMode: GameMode = .battle
    @State private var battleBusy = false
    @State private var battleError: String?
    @State private var partyCode: String?
    @State private var battleDoorNotice = false
    @State private var savedGame: SavedSoloGame?
    /// The stand-in rival of a `WORD_AUTOSTART=occupy` game.
    @State private var localRival: BattleSession?

    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            switch route {
            case .home:
                HomeScreen(
                    hasSavedGame: savedGame != nil,
                    onResume: resumeSavedGame,
                    onSolo: { route = .soloSetup },
                    onBattle: { chooseBattle(mode: .battle) },
                    onOccupy: { chooseBattle(mode: .occupy) })

            case .soloSetup:
                SoloSetupScreen(
                    pace: settings.pace,
                    onPlay: startSolo(pace:),
                    onClose: { route = .home })

            case .battleEntry:
                BattleEntryScreen(
                    mode: battleMode,
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
                    mode: battleMode,
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
            // (§7.1), and any score made meanwhile is held by Progression and
            // flushed if this succeeds.
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
            switch ProcessInfo.processInfo.environment["WORD_AUTOSTART"] {
            case "solo": startSolo(pace: settings.pace)
            case "occupy": startLocalOccupy()
            default: break
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
        // Cross-device progress and the leaderboard queue — both of which
        // work signed out and flush when auth arrives (§7.1).
        progression.record(outcome)
        settings.record(score: outcome.score, words: outcome.words)
        // A finished game is not a game to come back to.
        settings.save(nil)
    }

    // MARK: Battle and Occupy (plan §7.3)

    private func chooseBattle(mode: GameMode) {
        if gameCenter.battleBlockedReason != nil {
            battleDoorNotice = true
        } else {
            battleMode = mode
            battleError = nil
            partyCode = nil
            route = .battleEntry
            // Occupy's host judges everyone's words, so its dictionary has to
            // be in before the first one arrives — not when the board appears.
            if mode == .occupy {
                Task { await model.loadDictionary() }
            }
        }
    }

    /// A development hook: `WORD_AUTOSTART=occupy` opens straight onto an
    /// Occupy board against a rival who never plays — two sessions on an
    /// in-memory mesh — so a simulator can be screenshotted.
    private func startLocalOccupy() {
        let mesh = MemoryMesh()
        let hostTransport = mesh.add("me")
        let rivalTransport = mesh.add("rival")
        let rivalModel = GameModel()
        let host = BattleSession(
            role: .host, mode: .occupy, transport: hostTransport, model: model,
            displayName: { $0 == "me" ? "You" : "Rival" })
        let rival = BattleSession(role: .client, mode: .occupy, transport: rivalTransport, model: rivalModel)
        mesh.connect("me")
        mesh.connect("rival")
        host.onGameStart = { route = .game }
        host.onReturnToLobby = { route = .battleLobby }
        host.run()
        battle = host
        battleMode = .occupy
        // Held for the app's lifetime: a dropped session takes its seat with it.
        localRival = rival
        Task {
            await model.loadDictionary()
            host.start()
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
        let mode = battleMode
        runBattleSetup {
            let match = try await matchmaking.findMatchByInvite(mode: mode)
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
            mode: battleMode,
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
