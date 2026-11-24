import WordBoard
import WordCore
import XCTest

@testable import Word

/// The tutorial, played through the real model the way a player would:
/// SOLAR spelled and ✓'d, then ORBIT and POLE each built with a gap and
/// landed by tapping the letter they borrow.
@MainActor
final class TutorialPlayTests: XCTestCase {
    /// Pick the step's word into the row in its pattern's order — a letter
    /// off the pile, or a gap.
    static func build(_ pattern: [String?], on model: GameModel) {
        for entry in pattern {
            if let letter = entry {
                let index = model.rack.indices.first {
                    model.rack[$0] == letter && !model.picks.contains($0)
                }
                model.togglePick(index!)
            } else {
                model.addGap()
            }
        }
    }

    /// Tap each board letter the step borrows until the word lands.
    static func landThroughBoard(_ step: TutorialStep, on model: GameModel) {
        let before = model.tutorialStep
        for key in model.board.keys.sorted() where model.board[key] == step.borrowed.first {
            model.selectTile(key)
            if model.tutorialStep != before { return }
        }
    }

    static func playedOpener() async -> GameModel {
        let model = GameModel()
        model.newTutorial()
        await model.loadDictionary()
        build(tutorialScript[0].pattern, on: model)
        model.confirm()
        return model
    }

    func testItOpensOnTheFirstStepsTilesWithNoClock() {
        let model = GameModel()
        model.newTutorial()
        XCTAssertTrue(model.isTutorial)
        XCTAssertEqual(model.rack, ["s", "o", "l", "a", "r"])
        XCTAssertNil(model.secondsToNextTiles(at: .now))
        XCTAssertFalse(model.canPause)
        XCTAssertEqual(model.pileTone, .ok)
        // No "GAME ON" card promising a clock the tutorial doesn't have.
        XCTAssertNil(model.splash)
        XCTAssertTrue(model.canAcceptInput)
    }

    func testTheWholeScriptPlaysThroughWithTwoGapWords() async {
        let model = await Self.playedOpener()
        XCTAssertEqual(model.tutorialStep, 1)
        XCTAssertEqual(model.rack, ["o", "b", "i", "t"])

        // ORBIT: the row is ready only once the gap is in the R's place.
        Self.build([tutorialScript[1].pattern[0]], on: model)
        XCTAssertTrue(model.tutorialWantsGap)
        Self.build(Array(tutorialScript[1].pattern.dropFirst()), on: model)
        XCTAssertTrue(model.tutorialRowReady)
        Self.landThroughBoard(tutorialScript[1], on: model)
        XCTAssertEqual(model.tutorialStep, 2)
        XCTAssertTrue(model.usedGapTile)

        Self.build(tutorialScript[2].pattern, on: model)
        Self.landThroughBoard(tutorialScript[2], on: model)
        XCTAssertTrue(model.tutorialFinished)
        XCTAssertTrue(model.rack.isEmpty)
        XCTAssertEqual(Set(extractRuns(model.board).map(\.word)), ["solar", "orbit", "pole"])
        // An empty pile in the tutorial is the end of it, not a board clear.
        XCTAssertFalse(model.boardClearReady)
        XCTAssertFalse(model.canAcceptInput)
    }

    func testTheOpenerHasToBeTheStepsWord() async {
        let model = GameModel()
        model.newTutorial()
        await model.loadDictionary()
        // OARS is a word, just not this step's.
        Self.build(["o", "a", "r", "s"], on: model)
        model.confirm()
        XCTAssertTrue(model.board.isEmpty)
        XCTAssertEqual(model.tutorialStep, 0)
        XCTAssertEqual(model.toast?.text, "Spell SOLAR for this step.")
    }

    func testAGapStepRefusesTheWordBuiltOnTheBoardWithoutOne() async throws {
        let model = await Self.playedOpener()
        // Drop O, B, I, T on the squares around SOLAR's R, as if dragged
        // from the pile: ORBIT, but with no gap.
        let r = try XCTUnwrap(model.board.first { $0.value == "r" }?.key)
        let cell = parseKey(r)
        let squares = [(-1, "o"), (1, "b"), (2, "i"), (3, "t")]
        for (offset, letter) in squares {
            let index = try XCTUnwrap(model.rack.firstIndex(of: letter))
            model.beginDrag(.rack(index: index, letter: letter), at: .zero)
            model.applyDrop(.cell(Cell(row: cell.row + offset, col: cell.col)))
        }
        XCTAssertFalse(model.confirmStaged())
        XCTAssertEqual(model.tutorialStep, 1)
        XCTAssertEqual(model.toast?.text, "Use a gap for the R — then tap the R on the board.")
    }
}
