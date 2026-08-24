import SwiftUI
import WordBoard
import WordCore
import WordNet
import XCTest

@testable import Word

/// Renders the phase-2b screens offscreen for eyeballing during development,
/// and asserts they compose at all — a SwiftUI view that traps on layout fails
/// here rather than on a device.
@MainActor
final class ScreenSnapshotTests: XCTestCase {
    private func write(_ image: CGImage, to name: String) {
        let url = URL(fileURLWithPath: "/tmp/word-\(name).png")
        guard
            let dest = CGImageDestinationCreateWithURL(
                url as CFURL, "public.png" as CFString, 1, nil)
        else { return }
        CGImageDestinationAddImage(dest, image, nil)
        CGImageDestinationFinalize(dest)
    }

    private func render<V: View>(_ view: V, name: String, size: CGSize) throws {
        let renderer = ImageRenderer(
            content: view.frame(width: size.width, height: size.height).environment(\.colorScheme, .light))
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.cgImage, "\(name) failed to render")
        write(image, to: name)
    }

    func testHomeScreenRenders() throws {
        try render(
            HomeScreen(
                hasSavedGame: true,
                daily: DailyStatus(
                    deal: dailyDeal(at: .now), result: nil, streak: 12),
                onResume: {}, onDaily: {}, onChoose: { _ in }, onTutorial: {},
                onStats: {}, onSettings: {}, scrollable: false),
            name: "home", size: CGSize(width: 420, height: 640))
    }

    func testHomeScreenWithAPlayedDailyRenders() throws {
        let deal = dailyDeal(at: .now)
        let played = DailyResult(
            day: deal.day, date: deal.date, score: 214, words: 9, tilesLeft: 0,
            bonusEarned: true, withinDay: true, at: Date.now.timeIntervalSince1970)
        try render(
            HomeScreen(
                hasSavedGame: false,
                daily: DailyStatus(deal: deal, result: played, streak: 6),
                onResume: {}, onDaily: {}, onChoose: { _ in }, onTutorial: {},
                onStats: {}, onSettings: {}, scrollable: false),
            name: "home-daily-played", size: CGSize(width: 420, height: 640))
    }

    func testDailySummaryRenders() throws {
        try render(
            SoloSummaryView(
                words: [
                    ScoredWord(word: "orbit", points: 10),
                    ScoredWord(word: "tin", points: 3),
                ],
                score: 214,
                onPlayAgain: {}, onSeeBoard: {}, scrollable: false,
                daily: SoloSummaryView.DailySummary(
                    date: "Aug 24", tilesLeft: 0, bonusEarned: true, streak: 6)),
            name: "summary-daily", size: CGSize(width: 420, height: 720))
    }

    func testBattleLobbyRenders() throws {
        let state = BattleState(
            phase: .lobby,
            players: [
                BattlePlayer(id: "a", name: "Ada", host: true),
                BattlePlayer(id: "b", name: "Grace"),
                BattlePlayer(id: "c", name: "Katherine", connected: false),
                BattlePlayer(id: "d", name: "Dorothy", waiting: true),
            ],
            game: 1,
            winnerId: nil)
        try render(
            BattleLobbyScreen(
                state: state, selfID: "b", hostID: "a", isHost: false, canStart: false,
                isReconnecting: false, rejection: nil,
                onStart: {}, onLeave: {}, scrollable: false),
            name: "battle-lobby", size: CGSize(width: 420, height: 760))
    }

    func testBattleLobbyRendersForTheHost() throws {
        let state = BattleState(
            phase: .lobby,
            players: [BattlePlayer(id: "a", name: "Ada", host: true)],
            game: 0,
            winnerId: nil)
        try render(
            BattleLobbyScreen(
                state: state, selfID: "a", hostID: "a", isHost: true, canStart: false,
                isReconnecting: true, rejection: nil,
                onStart: {}, onLeave: {}, scrollable: false),
            name: "battle-lobby-host", size: CGSize(width: 420, height: 700))
    }

    func testTutorialChromeRenders() throws {
        try render(
            VStack(spacing: 0) {
                TutorialHeaderView(
                    step: 3, of: TUTORIAL_STEPS, showsSkip: true, onSkip: {}, onLeave: {})
                TutorialBanner(step: 3)
                Spacer()
                TutorialFinishBand(onFinish: {})
            },
            name: "tutorial", size: CGSize(width: 420, height: 420))
    }

    func testSettingsAndStatsRender() throws {
        let settings = AppSettings(store: MemoryStore())
        try render(
            SettingsScreen(settings: settings, onClose: {}, scrollable: false),
            name: "settings", size: CGSize(width: 420, height: 700))

        let store = MemoryStore()
        let withStats = AppSettings(store: store)
        withStats.record(score: 128, words: 11, at: Date(timeIntervalSince1970: 1_760_000_000))
        withStats.record(score: 64, words: 6, at: Date(timeIntervalSince1970: 1_760_100_000))
        try render(
            StatsScreen(
                stats: withStats.stats(),
                progress: MergedProgress(
                    gamesPlayed: 24, bestScore: 512, dailyDays: [
                        dailyDayNumber(at: .now), dailyDayNumber(at: .now) - 1,
                        dailyDayNumber(at: .now) - 2,
                    ], bestDailyScore: 268),
                earned: [.firstSoloGame, .gapTile, .tutorialDone, .eightLetterWord],
                dailyStreak: 3,
                onClose: {}, scrollable: false),
            name: "stats", size: CGSize(width: 420, height: 1500))
    }

    func testCardsRender() throws {
        try render(
            ModeInfoCard(
                info: SOLO_INFO, confirmLabel: "Play", skipLabel: nil,
                onConfirm: {}, onSkip: nil),
            name: "mode-card", size: CGSize(width: 420, height: 460))
        try render(
            SoloSetupCard(pace: .regular, onPlay: { _ in }, onDismiss: {}),
            name: "setup-card", size: CGSize(width: 420, height: 400))
    }

    /// The tutorial, played end to end through the real model, rendered as the
    /// player would meet it on step two.
    func testTutorialBoardRenders() throws {
        let model = GameModel()
        model.newTutorial()
        // Play step one exactly as a player types it.
        for letter in tutorialScript[0].word.map(String.init) { model.typeLetter(letter) }
        if let target = model.target { model.commit(target.key, target.dir) }
        XCTAssertEqual(model.tutorialProgress?.step, 2)

        var metrics = BoardMetrics(bounds: model.bounds, cellBase: 44, zoom: 1)
        if let box = model.tileBounds {
            metrics.bounds = Bounds(
                minRow: box.minRow - 2, minCol: box.minCol - 3,
                maxRow: box.maxRow + 4, maxCol: box.maxCol + 3)
        }
        let scene = BoardScene(
            metrics: metrics,
            tiles: model.board.entries.map { (key: $0.key, letter: $0.value) },
            feedback: model.cellFeedback,
            wordsAt: model.wordsByCell.mapValues { $0.map(\.word) })
        try render(
            VStack(spacing: 0) {
                TutorialHeaderView(
                    step: 2, of: TUTORIAL_STEPS, showsSkip: true, onSkip: {}, onLeave: {})
                TutorialBanner(step: 2)
                BoardContentView(scene: scene)
            },
            name: "tutorial-board", size: CGSize(width: 460, height: 520))
    }
}
