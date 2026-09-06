import WordCore
import XCTest

@testable import Word

/// The Daily, played through the real model: that everyone opens the same
/// position, that a word costs a stroke, that reaching every ring ends it,
/// that the pile can't end it, and that a day put down is picked back up
/// rather than dealt again.
///
/// The puzzle's own rules — how the board is built, what par means, how the
/// score packs — are argued out in `WordCoreTests/DailyBoardTests`. This is
/// about the wiring.
@MainActor
final class DailyPlayTests: XCTestCase {
    private let day = dailyDeal(day: 20_500)

    private func dailyModel() async throws -> GameModel {
        let model = GameModel()
        try model.newDaily(day, now: .now)
        await model.loadDictionary()
        model.dismissSplash(at: .now)
        return model
    }

    // MARK: Opening

    func testOpensOnTheWordAlreadyDown() async throws {
        let model = try await dailyModel()
        let built = try XCTUnwrap(model.day)

        XCTAssertEqual(model.mode, .daily)
        XCTAssertEqual(model.board.count, built.seedWord.count)
        XCTAssertEqual(extractRuns(model.board).first?.word, built.seedWord)
        XCTAssertEqual(model.rack.count, built.letters.count)
        XCTAssertEqual(model.strokes, 0)
        // Something is already down, so every word the player plays has to
        // borrow a letter — there is no opener to place by fiat.
        XCTAssertFalse(model.isFirstWord)
    }

    func testEveryoneGetsTheSamePositionNotJustTheSameLetters() throws {
        let mine = GameModel()
        let yours = GameModel()
        try mine.newDaily(day)
        try yours.newDaily(day)

        XCTAssertEqual(mine.board, yours.board)
        XCTAssertEqual(mine.rack, yours.rack)
        XCTAssertEqual(mine.day?.targets, yours.day?.targets)
        XCTAssertEqual(mine.day?.par, yours.day?.par)
    }

    func testADifferentDayIsADifferentPuzzle() throws {
        let today = GameModel()
        let tomorrow = GameModel()
        try today.newDaily(dailyDeal(day: 20_500))
        try tomorrow.newDaily(dailyDeal(day: 20_501))
        XCTAssertNotEqual(today.board, tomorrow.board)
    }

    func testTheDealFitsThePile() throws {
        // The whole deal arrives at once, so a day that dealt more than the
        // pile holds would arrive already buried.
        for number in 20_500..<20_530 {
            let model = GameModel()
            try model.newDaily(dailyDeal(day: number))
            XCTAssertLessThanOrEqual(model.rack.count, PILE_LIMIT)
        }
    }

    // MARK: The pile is not the pressure here

    func testAFullPileNeverBuriesADaily() async throws {
        let model = try await dailyModel()
        XCTAssertGreaterThan(model.rack.count, 0)
        // Whatever the deal came to, and however close to the limit it sits,
        // the day is not lost — nothing more is arriving.
        XCTAssertFalse(model.isComplete)
        model.advanceClock(at: .now.addingTimeInterval(10_000))
        XCTAssertFalse(model.isComplete, "there is no clock to run out either")
        XCTAssertNil(model.remainingSeconds(at: .now))
        XCTAssertFalse(model.canPause)
    }

    // MARK: Strokes

    func testAWordCostsAStroke() async throws {
        let model = try await dailyModel()
        try TestPlays.attachWord(on: model)
        XCTAssertEqual(model.strokes, 1)

        let result = try XCTUnwrap(model.dailyResult)
        XCTAssertEqual(result.strokes, 1)
        XCTAssertEqual(result.par, model.day?.par)
        XCTAssertEqual(result.underPar, (model.day?.par ?? 0) - 1)
    }

    func testAWordThatDoesNotLandCostsNothing() async throws {
        let model = try await dailyModel()
        // A word that isn't a word never lands, so it never spends a stroke.
        model.togglePick(0)
        model.togglePick(1)
        XCTAssertFalse(model.commitThroughLetter(try XCTUnwrap(model.board.keys.first)))
        XCTAssertEqual(model.strokes, 0)
    }

    // MARK: Reaching the rings

    func testTheDayIsUnfinishedUntilEveryTargetIsCovered() async throws {
        let model = try await dailyModel()
        let progress = try XCTUnwrap(model.dailyProgress)
        XCTAssertEqual(progress.reached, 0, "no target starts covered")
        XCTAssertFalse(progress.done)
        XCTAssertFalse(model.isComplete)
    }

    func testTheHiddenCrosswordCoversEveryTarget() async throws {
        // Restoring the day onto its own solution is the cheapest way to see
        // a finished board: it is the arrangement the deal was cut from, so
        // it covers every ring by construction. Restoring never *ends* a game
        // — that is a landing's job — so this is about the reading, not the
        // ending.
        let model = try await dailyModel()
        let built = try XCTUnwrap(model.day)
        var saved = try XCTUnwrap(model.savedGame())
        saved.board = built.solution
        saved.rack = []

        let restored = GameModel()
        restored.restore(saved)
        await restored.loadDictionary()

        let progress = try XCTUnwrap(restored.dailyProgress)
        XCTAssertEqual(progress.reached, built.targets.count)
        XCTAssertTrue(progress.done)
        XCTAssertTrue(progress.allTilesPlaced, "and every tile is down")
    }

    func testSolvingEndsTheDayAsAWin() async throws {
        let model = try await dailyModel()
        let cues = RecordingCues()
        model.cues = cues
        model.finishGame(reason: .solved)

        XCTAssertTrue(model.isComplete)
        XCTAssertEqual(cues.played, [.win], "the one ending here that isn't a loss")
    }

    // MARK: What a finished day reports

    func testAFinishedDayCarriesTheDayAndItsResult() async throws {
        let model = try await dailyModel()
        try TestPlays.attachWord(on: model)
        model.finishGame(reason: .solved)

        let outcome = model.outcome
        XCTAssertEqual(outcome.mode, .daily)
        XCTAssertEqual(outcome.daily, day)
        let result = try XCTUnwrap(outcome.dailyResult)
        XCTAssertEqual(result.strokes, 1)
        // The board is ranked on words, not points — so what is posted is the
        // packed pair, and fewer words beats more points.
        let quicker = DailyResult(
            strokes: result.strokes, par: result.par, points: result.points + 100,
            reached: result.reached, allTilesPlaced: result.allTilesPlaced)
        XCTAssertGreaterThan(dailyLeaderboardScore(quicker), dailyLeaderboardScore(result))
    }

    // MARK: Coming back to it

    func testADayInProgressIsWorthComingBackTo() async throws {
        let model = try await dailyModel()
        try TestPlays.attachWord(on: model)
        let board = model.board
        let rack = model.rack

        let saved = try XCTUnwrap(model.savedGame())
        XCTAssertEqual(saved.gameMode, .daily)
        XCTAssertEqual(saved.dailyDay, day.day)
        XCTAssertEqual(saved.strokes, 1)

        let store = MemoryStore()
        saved.save(to: store)
        let back = try XCTUnwrap(SavedSoloGame.load(from: store))

        let restored = GameModel()
        restored.restore(back)
        XCTAssertEqual(restored.mode, .daily)
        XCTAssertEqual(restored.board, board)
        XCTAssertEqual(restored.rack, rack)
        XCTAssertEqual(restored.strokes, 1)
        XCTAssertEqual(restored.day?.targets, model.day?.targets)
        XCTAssertEqual(restored.dailyDeal, day)
        // Straight back to the board: the opening card holds a clock, and
        // there isn't one.
        XCTAssertNil(restored.splash)
    }

    func testAnUntouchedDayIsStillWorthComingBackTo() async throws {
        // Unlike Solo, whose opening board can be had again by starting
        // another game. There is one go at this one.
        let model = try await dailyModel()
        XCTAssertNotNil(model.savedGame())
    }

    func testStartingSoloClearsTheDay() async throws {
        let model = try await dailyModel()
        model.newGame(seed: "after", pace: .regular)
        XCTAssertEqual(model.mode, .endless)
        XCTAssertNil(model.day)
        XCTAssertNil(model.dailyDeal)
        XCTAssertEqual(model.strokes, 0)
        XCTAssertNil(model.dailyResult)
    }
}
