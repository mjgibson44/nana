import WordCore
import XCTest

@testable import Word

@MainActor
final class GameEditingTests: XCTestCase {
    private func makeGame() -> GameModel {
        let model = GameModel()
        model.newGame(seed: "phase-2b-editing")
        return model
    }

    @discardableResult
    private func placeWord(_ count: Int, in model: GameModel) -> [String] {
        let letters = Array(model.rack.prefix(count))
        XCTAssertEqual(letters.count, count)
        for index in 0..<count { model.togglePick(index) }
        XCTAssertTrue(model.handle(.confirm))
        XCTAssertEqual(model.board.count, count)
        return letters
    }

    func testKeyboardClaimsOnlyAvailableRackLetters() {
        let model = makeGame()
        let letter = try! XCTUnwrap(model.rack.first)

        XCTAssertTrue(model.handle(.letter(letter.uppercased())))
        XCTAssertEqual(model.picks, [0])

        let impossible = "abcdefghijklmnopqrstuvwxyz".map(String.init).first { wanted in
            !model.rack.contains { $0.caseInsensitiveCompare(wanted) == .orderedSame }
        }
        if let impossible {
            XCTAssertTrue(model.handle(.letter(impossible)))
            XCTAssertEqual(model.picks, [0])
        }
    }

    func testKeyboardGapBackspaceDirectionEscapeAndConfirm() {
        let model = makeGame()
        XCTAssertTrue(model.handle(.direction(.down)))
        XCTAssertEqual(model.interactionDir, .down)

        XCTAssertTrue(model.handle(.gap))
        XCTAssertEqual(model.pickList.map(\.letter), [nil])
        XCTAssertTrue(model.handle(.backspace))
        XCTAssertTrue(model.picks.isEmpty)

        XCTAssertTrue(model.handle(.letter(model.rack[0])))
        XCTAssertTrue(model.handle(.confirm))
        XCTAssertEqual(model.board.count, 1)
        XCTAssertTrue(model.interaction == .idle)

        model.cellClick(keyOf(10, 10))
        XCTAssertTrue(model.handle(.escape))
        XCTAssertTrue(model.interaction == .idle)
    }

    func testUndoRestoresStagedWordAndRedoRestoresLanding() {
        let model = makeGame()
        let originalRack = model.rack
        _ = placeWord(3, in: model)
        let playedBoard = model.board
        let playedRack = model.rack

        XCTAssertTrue(model.canUndo)
        model.undo()
        XCTAssertTrue(model.board.isEmpty)
        XCTAssertEqual(model.rack, originalRack)
        XCTAssertEqual(model.picks, [0, 1, 2])
        XCTAssertTrue(model.canRedo)

        model.redo()
        XCTAssertEqual(model.board, playedBoard)
        XCTAssertEqual(model.rack, playedRack)
        XCTAssertTrue(model.picks.isEmpty)
    }

    func testBackspaceAndDeleteWalkAlongASelectedWord() {
        let model = makeGame()
        let originalCount = model.rack.count
        _ = placeWord(3, in: model)
        let middle = keyOf(BOARD_SIZE / 2, BOARD_SIZE / 2 + 1)
        model.selectTile(middle)

        XCTAssertTrue(model.handle(.backspace))
        XCTAssertNil(model.board[middle])
        XCTAssertEqual(model.selectedKey, keyOf(BOARD_SIZE / 2, BOARD_SIZE / 2))
        XCTAssertEqual(model.rack.count, originalCount - 2)

        XCTAssertTrue(model.handle(.deleteForward))
        XCTAssertNil(model.selectedKey)
        XCTAssertEqual(model.rack.count, originalCount - 1)
    }

    func testSelectedWordCanMoveRotateRemoveAndUndo() throws {
        let model = makeGame()
        let originalRack = model.rack
        let letters = placeWord(3, in: model)
        let pivot = keyOf(BOARD_SIZE / 2, BOARD_SIZE / 2)
        model.selectTile(pivot)
        let word = try XCTUnwrap(model.selectedWords.first)

        XCTAssertTrue(model.canRotate(word))
        model.rotateWord(word)
        XCTAssertEqual(model.board[pivot], letters[0])
        XCTAssertEqual(model.board[keyOf(BOARD_SIZE / 2 + 1, BOARD_SIZE / 2)], letters[1])

        model.undo()
        XCTAssertEqual(model.board[word.cells[1]], letters[1])

        model.selectTile(pivot)
        let restored = try XCTUnwrap(model.selectedWords.first)
        XCTAssertTrue(model.moveWord(restored, to: keyOf(10, 10), dir: .across))
        XCTAssertEqual(model.board[keyOf(10, 10)], letters[0])

        model.selectTile(keyOf(10, 10))
        let moved = try XCTUnwrap(model.selectedWords.first)
        model.removeWord(moved)
        XCTAssertTrue(model.board.isEmpty)
        XCTAssertEqual(model.rack.count, originalRack.count)

        model.undo()
        XCTAssertEqual(model.board.count, 3)
    }

    func testLockedBoardCannotEditOrRecordHistory() {
        let model = makeGame()
        _ = placeWord(3, in: model)
        model.boardLocked = true
        let board = model.board
        let rack = model.rack

        model.undo()
        XCTAssertEqual(model.board, board)
        XCTAssertEqual(model.rack, rack)
        XCTAssertFalse(model.canUndo)

        model.selectTile(board.keys[0])
        XCTAssertNil(model.selectedKey)
        model.returnToRack(board.keys[0])
        XCTAssertEqual(model.board, board)
    }
}
