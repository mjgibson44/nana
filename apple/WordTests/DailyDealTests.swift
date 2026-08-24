import Foundation
import WordCore
import XCTest

@testable import Word

/// The Daily Deal's app-layer rules: one attempt a day, results recorded
/// against the day they were *started* on, and a game that survives being put
/// away. The day arithmetic and seed live in `WordCore` and are tested there.
@MainActor
final class DailyDealTests: XCTestCase {

    private func settings() -> (AppSettings, MemoryStore) {
        let store = MemoryStore()
        return (AppSettings(store: store), store)
    }

    private func result(day: Int, score: Int = 100, withinDay: Bool = true) -> DailyResult {
        DailyResult(
            day: day, date: dailyDateString(day: day), score: score, words: 4,
            tilesLeft: 0, bonusEarned: true, withinDay: withinDay, at: 0)
    }

    // MARK: One attempt a day

    func testAFreshDayIsPlayable() {
        let (settings, _) = settings()
        let status = settings.dailyStatus()
        XCTAssertTrue(status.canPlay)
        XCTAssertFalse(status.isPlayed)
        XCTAssertEqual(status.streak, 0)
    }

    func testRecordingTodayClosesIt() {
        let (settings, _) = settings()
        let today = settings.dailyStatus().deal.day
        settings.recordDaily(result(day: today))

        let status = settings.dailyStatus()
        XCTAssertFalse(status.canPlay, "one attempt a day")
        XCTAssertTrue(status.isPlayed)
        XCTAssertEqual(status.result?.score, 100)
        XCTAssertEqual(status.streak, 1)
    }

    func testASecondResultForTheSameDayIsIgnored() {
        let (settings, _) = settings()
        let today = settings.dailyStatus().deal.day
        settings.recordDaily(result(day: today, score: 100))
        settings.recordDaily(result(day: today, score: 999))
        XCTAssertEqual(settings.dailyStatus().result?.score, 100, "the first go stands")
        XCTAssertEqual(settings.dailyHistory().results.count, 1)
    }

    func testTomorrowIsPlayableAgain() {
        let (settings, _) = settings()
        let today = settings.dailyStatus().deal.day
        settings.recordDaily(result(day: today - 1))
        let status = settings.dailyStatus()
        XCTAssertTrue(status.canPlay)
        XCTAssertEqual(status.streak, 1, "yesterday's run is still alive today")
    }

    // MARK: Persistence

    func testHistorySurvivesAReload() {
        let (settings, store) = settings()
        let today = settings.dailyStatus().deal.day
        settings.recordDaily(result(day: today, score: 321))

        let reloaded = AppSettings(store: store)
        XCTAssertEqual(reloaded.dailyStatus().result?.score, 321)
    }

    func testGarbageFallsBackToAnEmptyHistory() {
        let store = MemoryStore([DailyHistory.key: "{not json"])
        let settings = AppSettings(store: store)
        XCTAssertTrue(settings.dailyHistory().results.isEmpty)
        XCTAssertTrue(settings.dailyStatus().canPlay)
    }

    func testAStaleVersionIsDroppedRatherThanMigrated() {
        let store = MemoryStore([DailyHistory.key: #"{"version":99,"results":[]}"#])
        XCTAssertTrue(AppSettings(store: store).dailyHistory().results.isEmpty)
    }

    // MARK: The deal itself

    func testTodayDealsTheSameLettersTwice() {
        let model = GameModel()
        let deal = dailyDeal(at: .now)
        model.newDaily(deal: deal)
        let first = model.rack

        let other = GameModel()
        other.newDaily(deal: deal)
        XCTAssertEqual(first, other.rack, "same day, same letters, for everyone")
        XCTAssertEqual(first.count, DailyRules.tileCount)
    }

    func testADailyHasNoClockAndNoOpeningCard() {
        let model = GameModel()
        model.newDaily(deal: dailyDeal(at: .now))
        XCTAssertNil(model.countdown, "a fixed deal has nothing to run out of")
        XCTAssertNil(model.splash)
        XCTAssertFalse(model.showsClock)
        XCTAssertFalse(model.showsLooseGauge)
        XCTAssertTrue(model.showsTilesLeft)
        XCTAssertTrue(model.canFinishDaily)
    }

    func testFinishingHandsInTheBoardRatherThanLosing() {
        let model = GameModel()
        var outcome: GameOutcome?
        model.onFinish = { outcome = $0 }
        let deal = dailyDeal(at: .now)
        model.newDaily(deal: deal)

        model.finishDaily()

        XCTAssertTrue(model.isComplete)
        XCTAssertEqual(model.endReason, .dailyDone)
        XCTAssertEqual(outcome?.mode, .daily)
        XCTAssertEqual(outcome?.daily?.day, deal.day)
        XCTAssertEqual(outcome?.tilesLeft, DailyRules.tileCount, "nothing was placed")
        XCTAssertFalse(outcome?.bonusEarned ?? true)
        XCTAssertFalse(model.canFinishDaily, "and it can't be handed in twice")
    }

    func testFinishingIsIdempotent() {
        let model = GameModel()
        var finishes = 0
        model.onFinish = { _ in finishes += 1 }
        model.newDaily(deal: dailyDeal(at: .now))
        model.finishDaily()
        model.finishDaily()
        XCTAssertEqual(finishes, 1, "one funnel, one record")
    }

    // MARK: Rollover (plan §8.2)

    func testAResultKnowsWhetherItBeatTheRollover() {
        let (settings, _) = settings()
        let today = settings.dailyStatus().deal.day
        settings.recordDaily(result(day: today, withinDay: false))
        XCTAssertEqual(
            settings.dailyStatus().result?.withinDay, false,
            "a game finished after the flip is recorded but flagged ineligible")
    }

    func testTheDealIsPinnedAtTheStartOfTheGame() {
        // The model holds the day it began on, so a rollover mid-game can't
        // silently move the result onto the next day's board.
        let model = GameModel()
        let yesterday = dailyDeal(day: dailyDayNumber(at: .now) - 1)
        model.newDaily(deal: yesterday)
        model.finishDaily()
        XCTAssertEqual(model.outcome.daily?.day, yesterday.day)
        XCTAssertNotEqual(model.outcome.daily?.day, dailyDayNumber(at: .now))
    }

    // MARK: Save and restore

    func testAnUntouchedDailyIsWorthSaving() {
        let model = GameModel()
        model.newDaily(deal: dailyDeal(at: .now))
        let saved = model.savedGame()
        XCTAssertNotNil(saved, "one attempt a day — an untouched board still matters")
        XCTAssertEqual(saved?.gameMode, .daily)
        XCTAssertEqual(saved?.dailyDay, dailyDayNumber(at: .now))
    }

    func testARestoredDailyComesBackAsThatDaysPuzzle() {
        let model = GameModel()
        let deal = dailyDeal(day: dailyDayNumber(at: .now) - 3)
        model.newDaily(deal: deal)
        let dealtLetters = model.rack
        guard let saved = model.savedGame() else { return XCTFail("expected a save") }

        let restored = GameModel()
        restored.restore(saved)

        XCTAssertTrue(restored.isDaily)
        XCTAssertEqual(restored.daily?.day, deal.day)
        XCTAssertEqual(restored.rack, dealtLetters)
        XCTAssertNil(restored.splash, "no clock means no resume card holding one")
        XCTAssertTrue(restored.canFinishDaily)
    }

    func testAFinishedDailyIsNotWorthSaving() {
        let model = GameModel()
        model.newDaily(deal: dailyDeal(at: .now))
        model.finishDaily()
        XCTAssertNil(model.savedGame())
    }

    func testStartingSoloClearsTheDailyIdentity() {
        let model = GameModel()
        model.newDaily(deal: dailyDeal(at: .now))
        model.newGame(pace: .regular)
        XCTAssertNil(model.daily)
        XCTAssertFalse(model.isDaily)
        XCTAssertEqual(model.savedGame()?.gameMode, nil, "an untouched solo board isn't saved")
    }
}
