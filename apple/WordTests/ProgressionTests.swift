import Foundation
import WordCore
import XCTest

@testable import Word

/// The progression service: what a finished game accumulates, and what
/// happens to a score with nobody to submit it to (plan §7.1, §8.3, §9.1).
@MainActor
final class ProgressionTests: XCTestCase {

    /// A shared iCloud stand-in: two `Progression`s pointed at one of these
    /// are two devices on one account.
    private final class FakeSyncStore: SyncStore {
        var values: [String: String] = [:]
        func data(forKey key: String) -> String? { values[key] }
        func set(_ value: String, forKey key: String) { values[key] = value }
        func keys(withPrefix prefix: String) -> [String] {
            values.keys.filter { $0.hasPrefix(prefix) }.sorted()
        }
        @discardableResult func synchronize() -> Bool { true }
    }

    /// Records every call, and can be told to fail — the network does.
    private final class FakeSubmitter: ProgressionSubmitter, @unchecked Sendable {
        var accepts = true
        private(set) var submitted: [PendingScore] = []
        private(set) var reported: [AchievementProgress] = []

        func submit(_ score: PendingScore) async -> Bool {
            submitted.append(score)
            return accepts
        }
        func report(_ achievement: AchievementProgress) async -> Bool {
            reported.append(achievement)
            return accepts
        }
    }

    private func outcome(
        mode: GameMode = .endless,
        pace: SoloPace = .regular,
        score: Int = 100,
        longestWord: Int = 4,
        usedGapTile: Bool = false,
        boardClears: Int = 0,
        recovered: Bool = false,
        tutorialFinished: Bool = false,
        daily: DailyDeal? = nil
    ) -> GameOutcome {
        GameOutcome(
            report: GameReport(
                mode: mode, pace: pace, score: score, longestWord: longestWord,
                usedGapTile: usedGapTile, boardClears: boardClears,
                recoveredFromOverLimit: recovered, tutorialFinished: tutorialFinished),
            words: 3, tilesLeft: 0, bonusEarned: false, daily: daily)
    }

    // MARK: Accumulating

    func testAFinishedGameCountsAndKeepsTheBest() {
        let progression = Progression(store: MemoryStore())
        progression.record(outcome(score: 100))
        progression.record(outcome(score: 320))
        progression.record(outcome(score: 90))

        XCTAssertEqual(progression.merged.gamesPlayed, 3)
        XCTAssertEqual(progression.merged.bestScore, 320)
        XCTAssertEqual(progression.merged.recent.count, 3)
    }

    func testTheTutorialEarnsABadgeButIsNotAGame() {
        let progression = Progression(store: MemoryStore())
        let recorded = progression.record(outcome(mode: .tutorial, tutorialFinished: true))

        XCTAssertEqual(progression.merged.gamesPlayed, 0, "a lesson isn't a game")
        XCTAssertEqual(recorded.completed, [.tutorialDone])
    }

    func testADailyRecordsItsDayForTheStreak() {
        let store = MemoryStore()
        let progression = Progression(store: store)
        let today = dailyDayNumber(at: .now)
        progression.record(outcome(mode: .daily, score: 210, daily: dailyDeal(day: today)))
        progression.record(outcome(mode: .daily, score: 180, daily: dailyDeal(day: today - 1)))

        XCTAssertEqual(progression.merged.dailyDays, [today, today - 1])
        XCTAssertEqual(progression.merged.bestDailyScore, 210)
        XCTAssertEqual(progression.dailyStreak, 2)
    }

    func testProgressSurvivesARelaunch() {
        let store = MemoryStore()
        Progression(store: store).record(outcome(score: 250))
        let relaunched = Progression(store: store)
        XCTAssertEqual(relaunched.merged.gamesPlayed, 1)
        XCTAssertEqual(relaunched.merged.bestScore, 250)
    }

    func testTheDeviceIDIsStableAcrossRelaunches() {
        let store = MemoryStore()
        let first = Progression(store: store).deviceID
        XCTAssertFalse(first.isEmpty)
        XCTAssertEqual(Progression(store: store).deviceID, first)
    }

    func testTwoDevicesAddUpRatherThanClobbering() {
        // The §9.1 property: a shared sync store, two device blobs, no loss.
        let shared = FakeSyncStore()
        let phone = Progression(store: MemoryStore(), sync: shared)
        let pad = Progression(store: MemoryStore(), sync: shared)
        XCTAssertNotEqual(phone.deviceID, pad.deviceID)

        phone.record(outcome(score: 100))
        phone.record(outcome(score: 100))
        pad.record(outcome(score: 400))

        XCTAssertEqual(pad.merged.gamesPlayed, 3, "the pad sees the phone's games too")
        XCTAssertEqual(pad.merged.bestScore, 400)
        // And the phone catches up when it next writes.
        phone.record(outcome(score: 50))
        XCTAssertEqual(phone.merged.gamesPlayed, 4)
        XCTAssertEqual(phone.merged.bestScore, 400)
    }

    // MARK: Achievements

    func testAchievementsAreEarnedFromOrdinaryPlay() {
        let progression = Progression(store: MemoryStore())
        let recorded = progression.record(
            outcome(score: 100, longestWord: 8, usedGapTile: true, recovered: true))
        XCTAssertTrue(recorded.completed.contains(.eightLetterWord))
        XCTAssertTrue(recorded.completed.contains(.gapTile))
        XCTAssertTrue(recorded.completed.contains(.comeback))
        XCTAssertTrue(recorded.completed.contains(.firstSoloGame))
        XCTAssertTrue(progression.earned.contains(.gapTile))
    }

    func testEarnedAchievementsSurviveARelaunch() {
        let store = MemoryStore()
        Progression(store: store).record(outcome(usedGapTile: true))
        XCTAssertTrue(Progression(store: store).earned.contains(.gapTile))
    }

    func testABattleBadgeIsNeverEarnedBySolo() {
        let progression = Progression(store: MemoryStore())
        let recorded = progression.record(outcome(score: 9_999, longestWord: 8))
        XCTAssertTrue(recorded.completed.allSatisfy { !$0.needsBattle })
    }

    // MARK: Signed out — the designed state (§7.1)

    func testScoresAreHeldWhileSignedOut() {
        let progression = Progression(store: MemoryStore())
        XCTAssertNil(progression.submitter)

        progression.record(outcome(pace: .fast, score: 300))

        XCTAssertFalse(progression.pendingScores.isEmpty, "held, not lost")
        XCTAssertEqual(progression.pendingScores.scores.first?.board, .soloFast)
        XCTAssertFalse(progression.pendingAchievements.isEmpty)
    }

    func testHeldScoresSurviveARelaunchStillSignedOut() {
        let store = MemoryStore()
        Progression(store: store).record(outcome(pace: .fast, score: 300))
        XCTAssertFalse(Progression(store: store).pendingScores.isEmpty)
    }

    func testOnlyTheBestHeldScorePerBoardIsKept() {
        let progression = Progression(store: MemoryStore())
        progression.record(outcome(pace: .fast, score: 100))
        progression.record(outcome(pace: .fast, score: 500))
        progression.record(outcome(pace: .fast, score: 250))
        XCTAssertEqual(progression.pendingScores.scores.count, 1)
        XCTAssertEqual(progression.pendingScores.scores.first?.score, 500)
    }

    func testSigningInFlushesEverythingHeld() async {
        let progression = Progression(store: MemoryStore())
        progression.record(outcome(pace: .fast, score: 300))
        progression.record(outcome(mode: .endless, pace: .regular, score: 120))
        XCTAssertEqual(progression.pendingScores.scores.count, 2)

        let submitter = FakeSubmitter()
        await progression.signedIn(as: submitter)

        XCTAssertTrue(progression.pendingScores.isEmpty)
        XCTAssertTrue(progression.pendingAchievements.isEmpty)
        XCTAssertEqual(Set(submitter.submitted.map(\.board)), [.soloFast, .soloRegular])
        XCTAssertFalse(submitter.reported.isEmpty)
    }

    func testARefusedSubmissionStaysQueued() async {
        let progression = Progression(store: MemoryStore())
        progression.record(outcome(pace: .fast, score: 300))

        let submitter = FakeSubmitter()
        submitter.accepts = false
        await progression.signedIn(as: submitter)

        XCTAssertFalse(submitter.submitted.isEmpty, "it tried")
        XCTAssertFalse(progression.pendingScores.isEmpty, "and kept it for next time")

        submitter.accepts = true
        await progression.flush()
        XCTAssertTrue(progression.pendingScores.isEmpty)
    }

    func testFlushingWithNothingHeldDoesNothing() async {
        let progression = Progression(store: MemoryStore())
        let submitter = FakeSubmitter()
        await progression.signedIn(as: submitter)
        XCTAssertTrue(submitter.submitted.isEmpty)
    }

    func testSigningOutGoesBackToHolding() async {
        let progression = Progression(store: MemoryStore())
        let submitter = FakeSubmitter()
        await progression.signedIn(as: submitter)
        progression.signedOut()

        progression.record(outcome(pace: .fast, score: 300))
        XCTAssertFalse(progression.pendingScores.isEmpty)
    }

    func testALateDailyIsRecordedButNeverSubmitted() {
        // §8.2: a recurring leaderboard would file it against the wrong day.
        let progression = Progression(store: MemoryStore())
        let yesterday = dailyDeal(day: dailyDayNumber(at: .now) - 1)
        progression.record(outcome(mode: .daily, score: 200, daily: yesterday))

        XCTAssertTrue(progression.merged.dailyDays.contains(yesterday.day), "still counted")
        XCTAssertFalse(
            progression.pendingScores.scores.contains { $0.board == .daily },
            "but never queued for the board")
    }

    func testTheTutorialQueuesNoScore() {
        let progression = Progression(store: MemoryStore())
        progression.record(outcome(mode: .tutorial, tutorialFinished: true))
        XCTAssertTrue(progression.pendingScores.isEmpty)
        XCTAssertFalse(progression.pendingAchievements.isEmpty, "but it does earn a badge")
    }
}
