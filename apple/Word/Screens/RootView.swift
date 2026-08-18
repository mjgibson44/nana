import SwiftUI
import WordCore

/// The app's one router state (App.tsx:293), plus the overlays each screen
/// raises. Battle joins in phase 4; its door already explains itself and then
/// says so.
enum Route: Equatable {
    case home
    case game
}

/// What's standing between a chosen door and its game — each shown once ever
/// (App.tsx:364–374): the tutorial before a player's very first game, then the
/// mode's own explainer.
private enum PendingDoor: Equatable {
    case tutorialOffer(GameDoor)
    case explainer(GameDoor)
}

/// The root: owns the route, the model, and the services the game plays
/// through, and applies the theme preference to the whole app.
struct RootView: View {
    @State private var route: Route = .home
    @State private var model = GameModel()
    @State private var settings = AppSettings()
    @State private var audio = AudioEngine()

    @State private var pending: PendingDoor?
    @State private var showSetup = false
    @State private var showStats = false
    @State private var showSettings = false
    @State private var battleDoorNotice = false
    @State private var savedGame: SavedSoloGame?
    /// Set while the tutorial is on its way to a door a first-timer picked, so
    /// finishing the lesson hands them on rather than dropping them home.
    @State private var doorAfterTutorial: GameDoor?

    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            switch route {
            case .home:
                HomeScreen(
                    hasSavedGame: savedGame != nil,
                    onResume: resumeSavedGame,
                    onChoose: choose(door:),
                    onTutorial: startTutorialDirectly,
                    onStats: { showStats = true },
                    onSettings: { showSettings = true })

            case .game:
                GameScreen(
                    model: model,
                    onLeave: leaveGame,
                    onShowSettings: { showSettings = true })
            }

            if let pending {
                switch pending {
                case .tutorialOffer:
                    ModeInfoCard(
                        info: TUTORIAL_INFO,
                        confirmLabel: "Start the tutorial",
                        skipLabel: "Skip",
                        onConfirm: startOfferedTutorial,
                        onSkip: skipTutorialOffer)
                case let .explainer(door):
                    ModeInfoCard(
                        info: DOOR_INFO[door] ?? SOLO_INFO,
                        confirmLabel: "Play",
                        onConfirm: { enter(door: door) },
                        onSkip: { self.pending = nil })
                }
            }

            if showSetup {
                SoloSetupCard(
                    pace: settings.pace,
                    onPlay: startSolo(pace:),
                    onDismiss: { showSetup = false })
            }

            if showStats {
                StatsScreen(stats: settings.stats(), onClose: { showStats = false })
                    .transition(.opacity)
            }

            if showSettings {
                SettingsScreen(settings: settings, onClose: { showSettings = false })
                    .transition(.opacity)
            }

            // Battle's door is real, and honest about where it is: the lobby
            // arrives with GameKit in phase 4.
            if battleDoorNotice {
                DialogCard(dismiss: { battleDoorNotice = false }) {
                    VStack(spacing: 12) {
                        Text(BATTLE_ROYALE_INFO.name)
                            .font(.system(size: 25, weight: .heavy, design: .rounded))
                        Text("Battles are coming to this app with Game Center. "
                            + "For now, Solo and the tutorial are ready to play.")
                            .font(.callout)
                            .foregroundStyle(Ink.ink.opacity(0.8))
                            .multilineTextAlignment(.center)
                        Button("Back") { battleDoorNotice = false }
                            .buttonStyle(InkActionButtonStyle(primary: true))
                    }
                }
            }
        }
        .preferredColorScheme(settings.theme.colorScheme)
        .task {
            savedGame = settings.loadSavedGame()
            model.cues = audio
            audio.isSoundEnabled = { [settings] in settings.soundEnabled }
            audio.isHapticsEnabled = { [settings] in settings.hapticsEnabled }
            model.onFinish = { [settings] score, words in
                settings.record(score: score, words: words)
                // A finished game is not a game to come back to.
                settings.save(nil)
            }
            model.onTutorialWalkedOut = leaveGame
        }
        // The OS can kill a backgrounded app at any moment, so the in-progress
        // game is written out as it leaves the screen, not on the way down
        // (plan §6.1).
        .onChange(of: scenePhase) { _, phase in
            guard phase != .active else { return }
            persistGame()
        }
    }

    // MARK: Doors (App.tsx:623–730)

    private func choose(door: GameDoor) {
        // Two things can stand in front of a door, each shown once ever.
        if !settings.hasSeenTutorialOffer() {
            settings.markTutorialOfferSeen()
            doorAfterTutorial = door
            pending = .tutorialOffer(door)
            return
        }
        if !settings.hasSeen(door: door) {
            pending = .explainer(door)
            return
        }
        enter(door: door)
    }

    /// The explainer has been read (or wasn't needed): in we go.
    private func enter(door: GameDoor) {
        settings.markSeen(door: door)
        pending = nil
        switch door {
        case .solo:
            showSetup = true
        case .battle:
            battleDoorNotice = true
        }
    }

    private func startSolo(pace: SoloPace) {
        showSetup = false
        // This is the one moment a player says what they want out of a door,
        // so it's the only one worth remembering.
        settings.pace = pace
        settings.save(nil)
        savedGame = nil
        model.newGame(pace: pace)
        route = .game
    }

    // MARK: The tutorial

    /// The home screen's Tutorial button: nothing stands in the way — a card
    /// asking whether they'd like the tutorial they just pressed Tutorial for
    /// would only describe the button they'd already read. It still counts as
    /// having seen the offer.
    private func startTutorialDirectly() {
        settings.markTutorialOfferSeen()
        doorAfterTutorial = nil
        pending = nil
        model.newTutorial()
        route = .game
    }

    private func startOfferedTutorial() {
        pending = nil
        model.newTutorial()
        route = .game
    }

    /// Passing on the offer counts as having seen it, so the door behind it
    /// opens straight away.
    private func skipTutorialOffer() {
        guard case let .tutorialOffer(door) = pending else { return }
        pending = nil
        doorAfterTutorial = nil
        if settings.hasSeen(door: door) {
            enter(door: door)
        } else {
            pending = .explainer(door)
        }
    }

    // MARK: Leaving, resuming, persisting

    /// Done with a game by any road. A first-timer who came through the
    /// tutorial on their way to a door is handed on to it (App.tsx:722–730).
    private func leaveGame() {
        persistGame()
        route = .home
        if let door = doorAfterTutorial {
            doorAfterTutorial = nil
            if settings.hasSeen(door: door) {
                enter(door: door)
            } else {
                pending = .explainer(door)
            }
        }
    }

    private func resumeSavedGame() {
        guard let savedGame else { return }
        model.restore(savedGame)
        self.savedGame = nil
        route = .game
    }

    private func persistGame() {
        guard route == .game else { return }
        let snapshot = model.savedGame()
        settings.save(snapshot)
        savedGame = snapshot
    }
}
