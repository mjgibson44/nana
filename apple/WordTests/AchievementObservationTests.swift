import WordCore
import XCTest

@testable import Word

/// The wiring between the game and the achievement evaluator (plan §8.3).
///
/// The evaluator itself is pinned in `WordCore`; what's tested here is that
/// the game actually *notices* — a badge that can never fire is worse than no
/// badge, and nothing else would catch it.
@MainActor
final class AchievementObservationTests: XCTestCase {

    private func game(seed: String = "achievements") async -> GameModel {
        let model = GameModel()
        model.newGame(seed: seed)
        // Nothing lands without the dictionary, so it has to be in first.
        await model.loadDictionary()
        return model
    }

    func testAFreshGameHasNothingToReport() async {
        let model = await game()
        XCTAssertFalse(model.usedGapTile)
        XCTAssertEqual(model.longestWordPlaced, 0)
        XCTAssertEqual(model.boardClears, 0)
        XCTAssertFalse(model.recoveredFromOverLimit)
    }

    func testPlacingAWordNotesItsLength() async throws {
        let model = await game()
        XCTAssertNotNil(model.dictionary, "the dictionary must load in the test host")

        let word = try TestPlays.placeOpener(on: model)

        XCTAssertEqual(model.longestWordPlaced, word.count)
        XCTAssertEqual(model.outcome.report.longestWord, word.count)
    }

    func testAGapTileIsNoticed() async throws {
        let model = await game()
        try TestPlays.placeOpener(on: model)
        XCTAssertFalse(model.usedGapTile, "nothing has borrowed a letter yet")

        try TestPlays.attachWord(on: model)

        XCTAssertTrue(model.usedGapTile, "the gap play has to be noticed to ever be a badge")
        XCTAssertTrue(model.outcome.report.usedGapTile)
    }

    func testTheReportCarriesEverythingTheEvaluatorNeeds() async {
        let model = await game()
        let report = model.outcome.report
        XCTAssertEqual(report.mode, .endless)
        XCTAssertEqual(report.pace, .regular)
        // Battle fields stay dark outside a battle.
        XCTAssertFalse(report.battleWon)
        XCTAssertEqual(report.attackTilesSent, 0)
    }

    func testFinishingReportsThroughTheOneFunnel() async throws {
        let model = await game()
        var outcomes: [GameOutcome] = []
        model.onFinish = { outcomes.append($0) }

        let word = try TestPlays.placeOpener(on: model)
        model.finishGame(reason: .buried)

        XCTAssertEqual(outcomes.count, 1)
        XCTAssertEqual(outcomes.first?.report.longestWord, word.count)
        XCTAssertEqual(outcomes.first?.mode, .endless)
    }

    func testANewGameForgetsTheLastOnesObservations() async throws {
        let model = await game()
        try TestPlays.placeOpener(on: model)
        XCTAssertGreaterThan(model.longestWordPlaced, 0)

        model.newGame(seed: "a-different-game")
        XCTAssertEqual(model.longestWordPlaced, 0)
        XCTAssertFalse(model.usedGapTile)
    }
}
