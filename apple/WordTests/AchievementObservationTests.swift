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
        // The longest-word rule only counts real words, so the dictionary has
        // to be in before anything is placed.
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

    func testPlacingAWordNotesItsLength() async {
        let model = await game()
        XCTAssertNotNil(model.dictionary, "the dictionary must load in the test host")

        // Find a real word this rack can spell, and play it.
        guard let (word, indices) = spellableWord(in: model) else {
            return XCTFail("no playable word in the opening rack")
        }
        for index in indices { model.togglePick(index) }
        XCTAssertTrue(model.handle(.confirm))

        XCTAssertEqual(model.longestWordPlaced, word.count)
        XCTAssertEqual(model.outcome.report.longestWord, word.count)
    }

    func testAGapTileIsNoticed() throws {
        // The tutorial's last step is a scripted gap play, which makes it the
        // one deterministic way to land one.
        let gapIndex = try XCTUnwrap(
            tutorialScript.firstIndex(where: \.needsGap), "the script should have a gap step")
        let model = GameModel()
        model.newTutorial()
        for _ in 0..<gapIndex { model.skipTutorialStep() }
        XCTAssertFalse(model.usedGapTile, "nothing has borrowed a letter yet")

        let step = tutorialScript[gapIndex]
        let played = try XCTUnwrap(
            scriptedPlacement(
                board: model.board, bounds: model.bounds, step: step, rack: model.rack))
        XCTAssertTrue(played.picks.contains { $0.letter == nil })
        model.commit(
            keyOf(played.anchor.row, played.anchor.col), played.dir, picksToPlace: played.picks)

        XCTAssertTrue(model.usedGapTile, "the gap play has to be noticed to ever be a badge")
        XCTAssertTrue(model.outcome.report.usedGapTile)
    }

    func testFinishingTheTutorialReportsItsBadgeThroughTheFunnel() throws {
        let gapIndex = try XCTUnwrap(tutorialScript.firstIndex(where: \.needsGap))
        let model = GameModel()
        var outcomes: [GameOutcome] = []
        model.newTutorial()
        model.onFinish = { outcomes.append($0) }
        for _ in 0..<gapIndex { model.skipTutorialStep() }

        let step = tutorialScript[gapIndex]
        let played = try XCTUnwrap(
            scriptedPlacement(
                board: model.board, bounds: model.bounds, step: step, rack: model.rack))
        model.commit(
            keyOf(played.anchor.row, played.anchor.col), played.dir, picksToPlace: played.picks)

        XCTAssertTrue(model.tutorialFinished)
        XCTAssertEqual(outcomes.count, 1, "a finished lesson reports exactly once")
        XCTAssertTrue(outcomes.first?.report.tutorialFinished ?? false)
        XCTAssertEqual(outcomes.first?.mode, .tutorial)
    }

    func testTheReportCarriesEverythingTheEvaluatorNeeds() async {
        let model = await game()
        let report = model.outcome.report
        XCTAssertEqual(report.mode, .endless)
        XCTAssertEqual(report.pace, .regular)
        // Battle fields stay dark until phase 4 fills them.
        XCTAssertFalse(report.battleWon)
        XCTAssertEqual(report.attackTilesSent, 0)
    }

    func testFinishingReportsThroughTheOneFunnel() async {
        let model = await game()
        var outcomes: [GameOutcome] = []
        model.onFinish = { outcomes.append($0) }

        guard let (word, indices) = spellableWord(in: model) else {
            return XCTFail("no playable word in the opening rack")
        }
        for index in indices { model.togglePick(index) }
        XCTAssertTrue(model.handle(.confirm))
        model.finishGame(reason: .buried)

        XCTAssertEqual(outcomes.count, 1)
        XCTAssertEqual(outcomes.first?.report.longestWord, word.count)
        XCTAssertEqual(outcomes.first?.mode, .endless)
    }

    func testANewGameForgetsTheLastOnesObservations() async {
        let model = await game()
        guard let (_, indices) = spellableWord(in: model) else {
            return XCTFail("no playable word in the opening rack")
        }
        for index in indices { model.togglePick(index) }
        XCTAssertTrue(model.handle(.confirm))
        XCTAssertGreaterThan(model.longestWordPlaced, 0)

        model.newGame(seed: "a-different-game")
        XCTAssertEqual(model.longestWordPlaced, 0)
        XCTAssertFalse(model.usedGapTile)
    }

    // MARK: Helpers

    /// The longest real word the opening rack can spell, with the rack
    /// indices that spell it. Brute force over short combinations — the rack
    /// is 20 tiles and this only runs a handful of times.
    private func spellableWord(in model: GameModel) -> (String, [Int])? {
        guard let dictionary = model.dictionary else { return nil }
        let rack = model.rack
        var best: (String, [Int])?
        // Words of 3–5 letters from ordered index triples upward.
        for length in stride(from: 5, through: 3, by: -1) {
            for combo in combinations(of: Array(rack.indices), choose: length) {
                let word = combo.map { rack[$0] }.joined()
                if dictionary.contains(word) {
                    best = (word, combo)
                    break
                }
            }
            if best != nil { break }
        }
        return best
    }

    private func combinations(of items: [Int], choose k: Int) -> [[Int]] {
        guard k > 0 else { return [[]] }
        guard items.count >= k else { return [] }
        var result: [[Int]] = []
        for (offset, item) in items.enumerated() {
            let rest = Array(items[(offset + 1)...])
            for tail in permutations(of: rest, choose: k - 1) {
                result.append([item] + tail)
                if result.count > 4_000 { return result }
            }
        }
        return result
    }

    /// Order matters for spelling, so the tail is permuted rather than combined.
    private func permutations(of items: [Int], choose k: Int) -> [[Int]] {
        guard k > 0 else { return [[]] }
        var result: [[Int]] = []
        for (offset, item) in items.enumerated() {
            var rest = items
            rest.remove(at: offset)
            for tail in permutations(of: rest, choose: k - 1) {
                result.append([item] + tail)
                if result.count > 4_000 { return result }
            }
        }
        return result
    }
}
