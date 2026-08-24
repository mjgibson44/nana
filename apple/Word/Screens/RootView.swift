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
    // iCloud-backed now that the entitlement exists: each device writes only
    // its own blob, so the merge (§9.1) is what makes two devices add up.
    @State private var progression = Progression(sync: UbiquitousSyncStore())
    @State private var gameCenter = GameCenter()

    @State private var pending: PendingDoor?
    @State private var showSetup = false
    @State private var showStats = false
    @State private var showSettings = false
    @State private var battleDoorNotice = false
    @State private var savedGame: SavedSoloGame?
    /// Today's puzzle and what's been done about it, refreshed whenever the
    /// home screen comes back into view.
    @State private var daily: DailyStatus?
    @State private var dailyExplainer = false
    @State private var dailyStreak = 0
    /// Shown when the row is tapped on a day already played.
    @State private var dailyResult: DailyResult?
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
                    showsGameCenter: gameCenter.isSignedIn,
                    daily: daily,
                    onResume: resumeSavedGame,
                    onDaily: chooseDaily,
                    onChoose: choose(door:),
                    onTutorial: startTutorialDirectly,
                    onStats: { showStats = true },
                    onSettings: { showSettings = true })

            case .game:
                GameScreen(
                    model: model,
                    onLeave: leaveGame,
                    onShowSettings: { showSettings = true },
                    dailyStreak: dailyStreak)
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

            if let result = dailyResult {
                DialogCard(dismiss: { dailyResult = nil }) {
                    VStack(spacing: 12) {
                        Text(DAILY_DEAL_INFO.name)
                            .font(.system(size: 25, weight: .heavy, design: .rounded))
                        Text(dailyDeal(day: result.day).shortLabel)
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(Ink.ink.opacity(0.7))
                        HStack(spacing: 22) {
                            dailyResultStat("\(result.score)", "Score")
                            dailyResultStat("\(result.words)", result.words == 1 ? "Word" : "Words")
                            dailyResultStat(
                                "\(result.tilesLeft)",
                                result.tilesLeft == 1 ? "Tile left" : "Tiles left")
                        }
                        Text(nextDealNote)
                            .font(.caption)
                            .foregroundStyle(Ink.ink.opacity(0.7))
                            .multilineTextAlignment(.center)
                        Button("Back") { dailyResult = nil }
                            .buttonStyle(InkActionButtonStyle(primary: true))
                    }
                }
            }

            if dailyExplainer {
                ModeInfoCard(
                    info: DAILY_DEAL_INFO,
                    confirmLabel: "Play today’s deal",
                    skipLabel: "Not now",
                    onConfirm: startDaily,
                    onSkip: { dailyExplainer = false })
            }

            if showSetup {
                SoloSetupCard(
                    pace: settings.pace,
                    onPlay: startSolo(pace:),
                    onDismiss: { showSetup = false })
            }

            if showStats {
                StatsScreen(
                    stats: settings.stats(),
                    progress: progression.merged,
                    earned: progression.earned,
                    dailyStreak: progression.dailyStreak,
                    onClose: { showStats = false })
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
                        Text(
                            gameCenter.battleBlockedReason
                                ?? "Matchmaking arrives with the next slice — the battle "
                                    + "itself is built and tested."
                        )
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
            daily = settings.dailyStatus()
            // Kicked off at launch and never blocking: everything except
            // Battle plays signed out (§7.1), and anything earned meanwhile is
            // held by Progression and flushed if this succeeds.
            gameCenter.authenticate(feeding: progression)
            model.cues = audio
            audio.isSoundEnabled = { [settings] in settings.soundEnabled }
            audio.isHapticsEnabled = { [settings] in settings.hapticsEnabled }
            model.onFinish = { outcome in
                recordFinish(outcome)
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

    /// The Daily Deal row. Its explainer is shown once, like a door's; after
    /// that the row leads straight to today's puzzle — or, once it's been
    /// played, to what the player scored.
    private func chooseDaily() {
        let status = settings.dailyStatus()
        daily = status
        guard status.canPlay else {
            // One attempt a day: the row becomes a way back to the result.
            // Deliberately *not* by re-dealing and finishing the game — that
            // would run the finish funnel again and file a phantom Solo score.
            dailyResult = status.result
            return
        }
        if !settings.hasSeenDailyExplainer() {
            dailyExplainer = true
            return
        }
        startDaily()
    }

    private func dailyResultStat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 24, weight: .heavy, design: .rounded))
                .foregroundStyle(Ink.ink)
            Text(label)
                .font(.caption2.bold())
                .foregroundStyle(Ink.ink.opacity(0.65))
        }
    }

    /// How long until the next puzzle, in whole hours — the honest unit, since
    /// the reset is a fixed instant and nobody needs it to the second.
    private var nextDealNote: String {
        guard let daily else { return "" }
        let hours = Int(
            (daily.deal.closesAt.timeIntervalSinceNow / 3_600).rounded(.up))
        guard hours > 0 else { return "A new deal is ready." }
        return hours == 1
            ? "A new deal in about an hour."
            : "A new deal in about \(hours) hours."
    }

    private func startDaily() {
        settings.markDailyExplainerSeen()
        dailyExplainer = false
        let status = settings.dailyStatus()
        daily = status
        guard status.canPlay else { return }
        dailyStreak = status.streak
        settings.save(nil)
        savedGame = nil
        model.newDaily(deal: status.deal)
        route = .game
    }

    /// Every finished game lands here — Solo's stats, the Daily Deal's result
    /// and streak, and (phase 3) the Game Center submission that hangs off the
    /// same funnel.
    private func recordFinish(_ outcome: GameOutcome) {
        // Cross-device progress, achievements, and the leaderboard queue —
        // all of which work signed out and flush when auth arrives (§7.1).
        let recorded = progression.record(outcome)
        if !recorded.completed.isEmpty {
            model.announceAchievements(recorded.completed)
        }
        // The tutorial earns a badge but isn't a game, so it stops here.
        guard outcome.mode != .tutorial else { return }
        settings.record(score: outcome.score, words: outcome.words)
        if let deal = outcome.daily {
            // Recorded against the day the game *started* on, and marked
            // ineligible if the puzzle rolled over while it was being played
            // (plan §8.2).
            let history = settings.recordDaily(
                DailyResult(
                    day: deal.day,
                    date: deal.date,
                    score: outcome.score,
                    words: outcome.words,
                    tilesLeft: outcome.tilesLeft,
                    bonusEarned: outcome.bonusEarned,
                    withinDay: dailyDayNumber(at: .now) == deal.day,
                    at: Date.now.timeIntervalSince1970))
            dailyStreak = history.streak(today: deal.day)
            daily = settings.dailyStatus()
        }
        // A finished game is not a game to come back to.
        settings.save(nil)
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
        // The day can have rolled over while a game was open.
        daily = settings.dailyStatus()
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
