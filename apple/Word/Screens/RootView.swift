import GameKit
import SwiftUI
import WordCore
import WordNet

/// The app's one router state, plus the overlays each screen raises.
enum Route: Equatable {
    case home
    /// Picking a Solo game's speed, on the way in.
    case soloSetup
    /// Getting into a duel or a battle (or an Occupy game): opening a room,
    /// or joining one by its code.
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
    /// Which game the room being opened, joined or searched for plays.
    @State private var battleMode: GameMode = .battle
    /// Which door it was: a duel's room seats two, a battle's the mode's cap.
    @State private var battleRoom: RoomKind = .battle
    @State private var battleBusy = false
    @State private var battleError: String?
    @State private var partyCode: String?
    @State private var battleDoorNotice = false
    /// The stand-in rival of a `WORD_AUTOSTART=occupy` game.
    @State private var localRival: BattleSession?
    /// The road into a battle that's underway, so backing out can cancel it —
    /// and a match that lands for an abandoned attempt is recognised as such.
    @State private var setupTask: Task<Void, Never>?
    @State private var setupGeneration = 0
    /// Where a first-time player was heading when the tutorial stepped in —
    /// they carry on there once it's done. Nil for a tutorial opened from
    /// HOW TO PLAY, which comes back home.
    @State private var tutorialThen: Door?

    /// The three ways in from home.
    enum Door: Equatable {
        case solo
        case room(RoomKind)
    }

    var body: some View {
        ZStack {
            switch route {
            case .home:
                HomeScreen(
                    onSolo: { open(.solo) },
                    onDuel: { open(.room(.duel)) },
                    onBattle: { open(.room(.battle)) },
                    onHowToPlay: { startTutorial(then: nil) })

            case .soloSetup:
                SoloSetupScreen(
                    pace: settings.pace,
                    onPlay: { pace in startSolo(pace: pace, modifier: .none) },
                    onClose: { route = .home })

            case .battleEntry:
                BattleEntryScreen(
                    room: battleRoom,
                    supportsPartyCodes: Matchmaking.supportsPartyCodes,
                    partyCode: partyCode,
                    isBusy: battleBusy,
                    error: battleError,
                    onHost: hostRoom,
                    onJoin: joinBattle(code:),
                    onClose: leaveBattle)
                    // A fresh screen for each door, so a code half-typed
                    // behind DUEL isn't waiting behind BATTLE.
                    .id(battleRoom)

            case .battleLobby:
                lobbyScreen

            case .game:
                GameScreen(
                    model: model,
                    battle: battle,
                    onLeave: leaveGame,
                    onNewGame: startSolo(pace:modifier:),
                    onTutorialDone: finishTutorial,
                    tutorialPlayLabel: tutorialPlayLabel)
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
            case "solo": startSolo(pace: settings.pace, modifier: settings.modifier)
            case "tutorial": startTutorial(then: nil)
            case "occupy": startLocalOccupy()
            default: break
            }
        }
    }

    // MARK: Doors and the tutorial

    /// A door on the home screen. The first one a new player opens is
    /// fronted by the tutorial, once; after that every door opens straight.
    private func open(_ door: Door) {
        if !settings.hasSeenTutorial {
            startTutorial(then: door)
        } else {
            enter(door)
        }
    }

    private func enter(_ door: Door) {
        switch door {
        case .solo: route = .soloSetup
        case let .room(room): chooseBattle(room: room)
        }
    }

    private func startTutorial(then door: Door?) {
        tutorialThen = door
        model.newTutorial()
        route = .game
    }

    /// Finished or skipped: on to the door the player picked, or home.
    private func finishTutorial() {
        settings.markTutorialSeen()
        let door = tutorialThen
        tutorialThen = nil
        route = .home
        if let door { enter(door) }
    }

    /// The finish card's button names where it leads.
    private var tutorialPlayLabel: String {
        switch tutorialThen {
        case .solo: return "Play solo"
        case .room(.duel): return "On to duel"
        case .room(.battle): return "On to battle"
        case nil: return "Done"
        }
    }

    // MARK: Solo

    /// The room: who's in it, and the START that only its host has.
    private var lobbyScreen: some View {
        BattleLobbyScreen(
            mode: battleMode,
            room: battleRoom,
            state: battle?.state,
            selfID: battle?.selfID ?? "",
            isHost: battle?.isHost == true,
            canStart: battle?.canStart ?? false,
            isReconnecting: battle?.isReconnecting ?? false,
            rejection: battle?.rejection,
            autoStart: battle?.autoStart,
            countdown: battle?.countdown,
            onStart: { battle?.start() },
            onLeave: leaveBattle)
    }

    private func startSolo(pace: SoloPace, modifier: SoloModifier) {
        // This is the one moment a player says what they want, so it's the
        // only one worth remembering. The board is always a clear one: the
        // modifier is accepted for the game screen's NEW GAME and set aside.
        settings.pace = pace
        settings.modifier = .none
        settings.save(nil)
        model.newGame(pace: pace, modifier: .none)
        route = .game
    }

    /// Every finished game lands here — the local stats, and the Game Center
    /// submission that hangs off the same funnel.
    private func recordFinish(_ outcome: GameOutcome) {
        // Cross-device progress and the leaderboard queue — both of which
        // work signed out and flush when auth arrives (§7.1).
        progression.record(outcome)
        settings.record(score: outcome.score, words: outcome.words)
    }

    // MARK: Battle and Occupy (plan §7.3)

    private func chooseBattle(room: RoomKind, mode: GameMode = .battle) {
        if gameCenter.battleBlockedReason != nil {
            battleDoorNotice = true
        } else {
            battleRoom = room
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

    /// HOST: a party code where the OS has them, Game Center's invite sheet
    /// where it doesn't.
    private func hostRoom() {
        if Matchmaking.supportsPartyCodes {
            hostBattle()
        } else {
            inviteToBattle()
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
            return (GameKitTransport(match: match), .host)
        }
    }

    private func joinBattle(code: String) {
        guard #available(iOS 26, macOS 26, *) else { return }
        runBattleSetup {
            let activity = try await matchmaking.joinParty(code: code)
            let match = try await matchmaking.match(for: activity)
            return (GameKitTransport(match: match), .client)
        }
    }

    /// Game Center's own invite sheet — the road that works on every OS the
    /// app supports. Whoever sends the invite referees.
    private func inviteToBattle() {
        let mode = battleMode
        let seats = battleRoom.seatLimit
        runBattleSetup {
            let match = try await matchmaking.findMatchByInvite(mode: mode, seatLimit: seats)
            return (GameKitTransport(match: match), .host)
        }
    }

    /// The shared shape of every road in: show it's working, form a match,
    /// build the session, land in the lobby. Only the newest attempt gets to
    /// touch the screen — an older one that finishes late is let go.
    private func runBattleSetup(
        _ form: @escaping () async throws -> (GameKitTransport, BattleSession.Role)
    ) {
        abandonSetup()
        let generation = setupGeneration
        battleBusy = true
        setupTask = Task {
            do {
                let (transport, role) = try await form()
                guard generation == setupGeneration else {
                    transport.disconnect()
                    return
                }
                startBattle(transport: transport, role: role)
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
        }
    }

    /// Cancel whatever road in is underway, and make sure it can't land later.
    private func abandonSetup() {
        setupTask?.cancel()
        setupTask = nil
        setupGeneration += 1
        battleError = nil
    }

    private func startBattle(transport: GameKitTransport, role: BattleSession.Role) {
        let session = BattleSession(
            role: role,
            mode: battleMode,
            transport: transport,
            model: model,
            displayName: { transport.displayName(for: $0) },
            // Always the plain board: one layout, no squares.
            setup: BattleSetup(),
            seatLimit: battleRoom.seatLimit)
        session.onGameStart = { route = .game }
        session.onReturnToLobby = { route = .battleLobby }
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
        route = .home
    }

    // MARK: Leaving

    /// Done with a game by any road.
    private func leaveGame() {
        // A battle's board belongs to its battle: leaving the game leaves
        // the battle.
        if battle != nil {
            leaveBattle()
            return
        }
        // Leaving the tutorial early still counts as having seen it: it
        // won't step in front of a door again.
        if model.isTutorial {
            settings.markTutorialSeen()
            tutorialThen = nil
        }
        route = .home
    }
}
