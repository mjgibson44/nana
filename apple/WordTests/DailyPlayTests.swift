import WordCore
import XCTest

@testable import Word

/// The Daily, played through the real model: that everyone opens the same
/// position, that a word costs a stroke and can be taken back, that reaching
/// every ring is a tier rather than the end, that the day finishes on an
/// empty pile or on the player's say-so, and that a day put down is picked
/// back up rather than dealt again.
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

    func testATakenBackWordCostsNothing() async throws {
        let model = try await dailyModel()
        let board = model.board
        let rack = model.rack
        try TestPlays.attachWord(on: model)
        XCTAssertEqual(model.strokes, 1)
        XCTAssertTrue(model.canUndo)

        XCTAssertTrue(model.undoLastWord())

        // The whole point of the eraser: the position is exactly the one the
        // player was looking at before, and the stroke is not spent. The
        // score is a property of the board you finish with, not of the route.
        XCTAssertEqual(model.strokes, 0)
        XCTAssertEqual(model.board, board)
        XCTAssertEqual(model.rack.sorted(), rack.sorted())
        XCTAssertFalse(model.canUndo, "nothing left to take back")
        XCTAssertEqual(model.dailyResult?.strokes, 0)
    }

    func testWordsComeBackOffInReverseOrder() async throws {
        let model = try await dailyModel()
        try TestPlays.attachWord(on: model)
        let afterFirst = model.board
        guard (try? TestPlays.attachWord(on: model)) != nil else {
            throw XCTSkip("this deal can't attach a second word")
        }
        XCTAssertEqual(model.strokes, 2)

        XCTAssertTrue(model.undoLastWord())
        XCTAssertEqual(model.strokes, 1)
        XCTAssertEqual(model.board, afterFirst, "the last word, not any word")
    }

    func testOnlyTheDailyHasAnEraser() async throws {
        let solo = GameModel()
        solo.newGame(seed: "solo", pace: .regular)
        await solo.loadDictionary()
        try TestPlays.placeOpener(on: solo)
        // Permanence protects a clock, and Solo has one. This mode doesn't.
        XCTAssertFalse(solo.canUndo)
        XCTAssertFalse(solo.undoLastWord())
        XCTAssertTrue(solo.landings.isEmpty)
    }

    // MARK: Reaching the rings

    func testTheRingsAreATierRatherThanTheEnd() async throws {
        let model = try await dailyModel()
        let progress = try XCTUnwrap(model.dailyProgress)
        XCTAssertEqual(progress.reached, 0, "no ring starts covered")
        XCTAssertFalse(progress.ringsDone)
        XCTAssertFalse(model.isComplete)
    }

    func testCoveringEveryRingDoesNotEndTheDay() async throws {
        // The mode's central correction. Covering the last ring used to
        // finish the game on the spot, which meant reading the board well
        // bought you *less* of it — and made the every-tile tier reachable
        // only by the word that happened to empty the pile in the same
        // stroke. Now it is a tier that pays, and the day plays on.
        let model = try await dailyModel()
        let built = try XCTUnwrap(model.day)
        var saved = try XCTUnwrap(model.savedGame())
        saved.board = built.solution
        saved.rack = ["a", "b", "c"]

        let restored = GameModel()
        restored.restore(saved)
        await restored.loadDictionary()

        XCTAssertEqual(restored.dailyProgress?.ringsDone, true)
        XCTAssertFalse(restored.isComplete, "rings reached, tiles still in hand")
        XCTAssertEqual(restored.dailyResult?.reached, built.targets.count)
    }

    func testAnEmptyPileEndsTheDay() async throws {
        // The natural ending: nothing left in hand is nothing left to play.
        // Nothing is arriving either, so there is no reason to sit on a
        // finished board waiting to be told.
        let model = try await dailyModel()
        let cues = RecordingCues()
        model.cues = cues
        try TestPlays.emptyThePileWithOneWord(on: model)

        XCTAssertTrue(model.rack.isEmpty)
        XCTAssertTrue(model.isComplete)
        XCTAssertEqual(cues.played.last, .win)
        let result = try XCTUnwrap(model.dailyResult)
        XCTAssertEqual(result.tilesLeft, 0)
        XCTAssertTrue(result.allTilesPlaced, "the second tier, and now a reachable one")
        // The all-tiles bonus is in the points, as the day's card promises.
        XCTAssertGreaterThanOrEqual(result.points, ALL_TILES_BONUS)
    }

    func testTheDayNeverDealsItselfMoreTilesForClearingTheBoard() async throws {
        // Solo pays a board clear with 25 points and five more tiles. The
        // Daily's deal is the whole puzzle, so five more would be letters it
        // was never cut from — and the day is over by then anyway.
        let model = try await dailyModel()
        try TestPlays.emptyThePileWithOneWord(on: model)
        XCTAssertFalse(model.boardClearReady)
        XCTAssertTrue(model.rack.isEmpty)
    }

    func testFinishingIsThePlayersToCall() async throws {
        let model = try await dailyModel()
        let cues = RecordingCues()
        model.cues = cues
        try TestPlays.attachWord(on: model)
        XCTAssertFalse(model.isComplete, "tiles left, and no clock to run out")

        model.finishDay()

        XCTAssertTrue(model.isComplete)
        XCTAssertEqual(cues.played.last, .win, "a day is finished, never lost")
        // Stopping with tiles in hand is a decision with a price rather than
        // a way to game the ranking.
        let result = try XCTUnwrap(model.dailyResult)
        XCTAssertGreaterThan(result.tilesLeft, 0)
        XCTAssertFalse(model.canUndo, "a finished day is finished")
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
        XCTAssertTrue(progress.ringsDone)
        XCTAssertTrue(progress.allTilesPlaced, "and every tile is down")
    }

    func testFinishingIsAWinWhateverTheBoardCameTo() async throws {
        let model = try await dailyModel()
        let cues = RecordingCues()
        model.cues = cues
        model.finishGame(reason: .solved)

        XCTAssertTrue(model.isComplete)
        XCTAssertEqual(cues.played, [.win], "there is no losing ending here")
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
        // One number, and it is the one on screen: what goes to the board can
        // never be measuring something other than what the player was shown.
        XCTAssertEqual(dailyLeaderboardScore(result), result.score)
        XCTAssertEqual(model.score, result.score)
        // A tile left in the pile costs, which is the arithmetic that stops
        // stopping early from being the winning line. (Read off a board worth
        // enough to be above the floor: one word into a full pile, the day is
        // worth nothing at all, which is itself the point.)
        XCTAssertGreaterThan(result.tilesPlaced, 0, "a word's worth of tiles is off the pile")
        let tidier = DailyResult(
            strokes: result.strokes, par: result.par, points: result.points,
            reached: result.reached, tilesPlaced: result.tilesPlaced + 1,
            tilesLeft: result.tilesLeft - 1, allTilesPlaced: false)
        XCTAssertEqual(tidier.score - result.score, DAILY_TILE_POINTS)
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
        XCTAssertEqual(saved.landings.count, 1)

        let store = MemoryStore()
        saved.save(to: store)
        let back = try XCTUnwrap(SavedSoloGame.load(from: store))

        let restored = GameModel()
        restored.restore(back)
        XCTAssertEqual(restored.mode, .daily)
        XCTAssertEqual(restored.board, board)
        XCTAssertEqual(restored.rack, rack)
        XCTAssertEqual(restored.strokes, 1)
        // The eraser comes back with the board: a day picked up after lunch
        // can still take back the word it went to lunch regretting.
        XCTAssertTrue(restored.canUndo)
        XCTAssertTrue(restored.undoLastWord())
        XCTAssertEqual(restored.strokes, 0)
        XCTAssertEqual(restored.board, model.day?.board)
        restored.restore(back)
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
