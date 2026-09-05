import WordBoard
import WordCore
import XCTest

@testable import Word

/// Words built on the board by dragging tiles out of the pile: a dropped tile
/// waits on its square for the ✓, comes back off on a tap, and lands through
/// the same funnel as a typed word — so the same rules refuse it.
@MainActor
final class StagingPlayTests: XCTestCase {
    private func makeGame(seed: String = "staging") async -> GameModel {
        let model = GameModel()
        model.newGame(seed: seed)
        await model.loadDictionary()
        return model
    }

    /// Drag pile tile `index` onto `cell`, the way the gesture layer would.
    private func drop(_ model: GameModel, index: Int, on cell: Cell) {
        model.beginDrag(.rack(index: index, letter: model.rack[index]), at: .zero)
        XCTAssertEqual(model.hiddenRackIndex, index, "hidden in its slot while it rides")
        model.dragMoved(to: CGPoint(x: 10, y: 10))
        XCTAssertEqual(model.drag?.location, CGPoint(x: 10, y: 10))
        model.applyDrop(.cell(cell))
        XCTAssertNil(model.drag)
    }

    /// Drag a real word out of the pile and onto the board through one of
    /// its letters, the board-built counterpart of `TestPlays.attachWord`.
    /// Returns the word and the letter it ran through.
    @discardableResult
    private func attachByDragging(on model: GameModel) throws -> (word: String, through: CellKey) {
        guard let dictionary = model.dictionary else { throw XCTSkip("load the dictionary first") }
        for key in model.board.keys {
            let borrowed = model.board[key]!
            let cell = parseKey(key)
            for length in [3, 4] {
                for gapAt in 0..<length {
                    for combo in TestPlays.permutations(of: Array(model.rack.indices), choose: length - 1) {
                        var letters = combo.map { model.rack[$0] }
                        letters.insert(borrowed, at: gapAt)
                        let word = letters.joined()
                        guard dictionary.contains(word) else { continue }
                        for direction in Direction.allCases {
                            let cells = (0..<length).map { position in
                                direction == .across
                                    ? Cell(row: cell.row, col: cell.col - gapAt + position)
                                    : Cell(row: cell.row - gapAt + position, col: cell.col)
                            }
                            let free = cells.enumerated().allSatisfy { position, target in
                                position == gapAt || model.board[keyOf(target.row, target.col)] == nil
                            }
                            guard free else { continue }
                            var picks = combo.makeIterator()
                            for (position, target) in cells.enumerated() where position != gapAt {
                                drop(model, index: picks.next()!, on: target)
                            }
                            if model.confirmStaged() { return (word, key) }
                            model.clearWord()
                        }
                    }
                }
            }
        }
        throw XCTSkip("no word in this rack attaches to the board by dragging")
    }

    func testADroppedTileWaitsOnTheBoardAndLeavesItsSlotEmpty() async {
        let model = await makeGame()
        let start = GameModel.startCell
        let letter = model.rack[0]
        drop(model, index: 0, on: start)

        XCTAssertEqual(model.stagedLetters, [keyOf(start.row, start.col): letter])
        XCTAssertEqual(model.stagedIndices, [0])
        XCTAssertTrue(model.board.isEmpty, "not landed")
        XCTAssertTrue(model.hasStaged)
        XCTAssertTrue(model.canConfirm, "the ✓ is always offered, so it can say what's wrong")
        XCTAssertTrue(model.canClearWord)
        XCTAssertEqual(model.rack.count, SOLO_START_TILES, "the pile still holds the letter")
        XCTAssertTrue(model.preview.isEmpty, "the row's opener ghost stands aside")

        // The slot can't be picked or typed while its tile is on the board.
        model.togglePick(0)
        XCTAssertTrue(model.picks.isEmpty)
        if !model.rack.dropFirst().contains(letter) {
            XCTAssertTrue(model.handle(.letter(letter)))
            XCTAssertTrue(model.picks.isEmpty, "no other \(letter) to claim")
        }
    }

    func testATapOrADropOnThePileTakesAStagedTileBack() async {
        let model = await makeGame()
        let start = GameModel.startCell
        let key = keyOf(start.row, start.col)
        drop(model, index: 0, on: start)
        model.selectTile(key)
        XCTAssertFalse(model.hasStaged, "tapped back into the pile")

        drop(model, index: 1, on: start)
        model.beginDrag(.board(cell: start, letter: model.rack[1]), at: .zero)
        XCTAssertFalse(model.hasStaged, "lifted off the board")
        XCTAssertNil(model.hiddenRackIndex, "it isn't in the pile to hide")
        model.applyDrop(.pile)
        XCTAssertFalse(model.hasStaged)
        XCTAssertNil(model.drag)

        // Let go nowhere in particular, it goes back where it was.
        drop(model, index: 1, on: start)
        model.beginDrag(.board(cell: start, letter: model.rack[1]), at: .zero)
        model.applyDrop(.none)
        XCTAssertEqual(Array(model.stagedLetters.keys), [key])

        // And it can be carried to another square — but not onto a taken one.
        let next = Cell(row: start.row, col: start.col + 1)
        model.beginDrag(.board(cell: start, letter: model.rack[1]), at: .zero)
        model.applyDrop(.cell(next))
        XCTAssertEqual(Array(model.stagedLetters.keys), [keyOf(next.row, next.col)])
        drop(model, index: 2, on: next)
        XCTAssertEqual(model.stagedIndices, [1], "the second tile went home")
        XCTAssertEqual(model.toast?.text, "There’s already a tile on that square.")

        // Clearing the word clears the board too.
        model.clearWord()
        XCTAssertFalse(model.hasStaged)
    }

    func testAnOpenerBuiltOnTheBoardLandsWithTheCheck() async throws {
        let model = await makeGame()
        guard let (word, indices) = TestPlays.spellableWord(in: model) else {
            throw XCTSkip("this rack can't spell an opener")
        }
        let start = GameModel.startCell
        for (offset, index) in indices.enumerated() {
            drop(model, index: index, on: Cell(row: start.row, col: start.col + offset))
        }
        XCTAssertEqual(model.stagedVerdict, .good, "green: it would land")
        XCTAssertTrue(model.handle(.confirm))

        XCTAssertEqual(model.board.count, word.count)
        for (offset, letter) in word.enumerated() {
            XCTAssertEqual(model.board[keyOf(start.row, start.col + offset)], String(letter))
        }
        XCTAssertFalse(model.hasStaged)
        XCTAssertEqual(model.rack.count, SOLO_START_TILES - word.count, "spent")
        XCTAssertFalse(model.isFirstWord)
        XCTAssertFalse(model.canConfirm, "nothing left for the ✓")
    }

    func testAnOpenerOffTheStartSquareIsRefusedAndStaysStaged() async throws {
        let model = await makeGame()
        guard let (_, indices) = TestPlays.spellableWord(in: model) else {
            throw XCTSkip("this rack can't spell an opener")
        }
        let start = GameModel.startCell
        for (offset, index) in indices.enumerated() {
            drop(model, index: index, on: Cell(row: start.row + 4, col: start.col + offset))
        }
        XCTAssertNotEqual(model.stagedVerdict, .bad, "it reads; it's just in the wrong place")
        XCTAssertFalse(model.confirmStaged())
        XCTAssertTrue(model.toast?.text.contains("start square") ?? false)
        XCTAssertTrue(model.board.isEmpty)
        XCTAssertEqual(model.stagedIndices, Set(indices), "still there to move")
    }

    func testTilesThatDontSpellAWordShowRedAndAreRefusedByName() async throws {
        let model = await makeGame()
        guard let dictionary = model.dictionary else { throw XCTSkip("no dictionary") }
        guard
            let combo = TestPlays.permutations(of: Array(model.rack.indices), choose: 3).first(where: {
                !dictionary.contains($0.map { model.rack[$0] }.joined())
            })
        else { throw XCTSkip("everything this rack spells is a word") }
        let start = GameModel.startCell
        for (offset, index) in combo.enumerated() {
            drop(model, index: index, on: Cell(row: start.row, col: start.col + offset))
        }
        XCTAssertEqual(model.stagedVerdict, .bad)
        XCTAssertFalse(model.confirmStaged())
        let spelled = combo.map { model.rack[$0] }.joined().uppercased()
        XCTAssertEqual(model.toast?.text, "\(spelled) isn’t a word")
        XCTAssertTrue(model.hasStaged, "left in place to fix")
    }

    func testALaterWordBuiltOnTheBoardHasToJoinAndBorrowsWhatItRunsThrough() async throws {
        let model = await makeGame()
        try TestPlays.placeOpener(on: model)
        let placed = model.board
        let tiles = model.rack.count

        // An island, however real a word, is refused.
        let start = GameModel.startCell
        drop(model, index: 0, on: Cell(row: start.row + 6, col: start.col))
        XCTAssertFalse(model.confirmStaged())
        XCTAssertTrue(model.toast?.text.contains("join") ?? false)
        model.clearWord()

        let (word, through) = try attachByDragging(on: model)
        XCTAssertGreaterThan(model.board.count, placed.count)
        XCTAssertNotNil(model.board[through])
        XCTAssertEqual(model.rack.count, tiles - (word.count - 1), "the borrowed letter cost nothing")
        XCTAssertFalse(model.hasStaged)
        XCTAssertTrue(model.usedGapTile == false, "no gap was typed")
        XCTAssertEqual(model.longestWordPlaced, max(placed.count, word.count))
    }

    func testTheRowCantLandWhileTilesAreStaged() async throws {
        let model = await makeGame()
        try TestPlays.placeOpener(on: model)
        let placed = model.board
        drop(model, index: 0, on: Cell(row: GameModel.startCell.row + 6, col: 0))

        model.togglePick(1)
        model.addGap()
        model.togglePick(2)
        model.selectTile(placed.keys[0])
        XCTAssertEqual(model.board, placed, "nothing landed")
        XCTAssertTrue(model.toast?.text.contains("Confirm or clear") ?? false)
        model.aimThroughLetter(placed.keys[0])
        XCTAssertNil(model.aim, "and nothing is aimed")

        model.clearWord()
        XCTAssertTrue(model.picks.isEmpty)
        XCTAssertFalse(model.hasStaged)
    }

    func testShufflingKeepsStagedTilesOnTheirSquares() async {
        let model = await makeGame()
        let start = GameModel.startCell
        drop(model, index: 0, on: start)
        drop(model, index: 1, on: Cell(row: start.row, col: start.col + 1))
        model.togglePick(2)
        let before = model.stagedLetters
        let typed = model.pickList.compactMap(\.letter)

        model.shufflePile()

        XCTAssertEqual(model.stagedLetters, before, "the same letters on the same squares")
        XCTAssertEqual(model.pickList.compactMap(\.letter), typed, "and the row survives too")
        XCTAssertTrue(model.stagedIndices.isDisjoint(with: Set(model.picks)), "each letter its own slot")
    }

    func testAFinishedGameDropsWhatWasStaged() async {
        let model = await makeGame()
        drop(model, index: 0, on: GameModel.startCell)
        model.finishGame(reason: .buried)
        XCTAssertFalse(model.hasStaged)
        XCTAssertNil(model.drag)
    }

    // MARK: Occupy

    /// A seat-0 model on a fresh two-player board, with nobody to answer it.
    private func seated(seed: String = "staging-occupy") async -> GameModel {
        let model = GameModel()
        model.newOccupy(seed: seed, selfID: "me", state: OccupyState(seats: ["me", "them"]))
        await model.loadDictionary()
        return model
    }

    /// The rival's STAR, backwards from their start square in the host's frame.
    private func rivalsWord() -> OccupyState {
        var theirs = OccupyState(seats: ["me", "them"])
        for (offset, letter) in "star".enumerated() {
            theirs.board[keyOf(20, 20 - offset)] = String(letter)
            theirs.owners[keyOf(20, 20 - offset)] = 1
        }
        theirs.opened = [false, true]
        theirs.scores = [0, 16]
        return theirs
    }

    func testAWordDraggedOntoAnOccupyBoardCapturesWhatItRunsThrough() async throws {
        let model = await seated()
        model.adoptOccupy(rivalsWord())
        var sent: [(Int, OccupyPlacement)] = []
        model.onOccupyPlace = { sent.append(($0, $1)) }

        let (word, through) = try attachByDragging(on: model)

        XCTAssertEqual(model.owners[through], 0, "captured")
        XCTAssertEqual(sent.count, 1)
        XCTAssertFalse(sent[0].1.borrowed.isEmpty, "the letters it ran through went up as borrowed")
        XCTAssertEqual(model.occupyWords.last?.word, word)
        XCTAssertEqual(model.rack.count, OCCUPY_HAND, "refilled")
        XCTAssertFalse(model.isFirstWord, "borrowing counts as opening")
        XCTAssertFalse(model.hasStaged)
    }

    func testARivalsWordLandingUnderAStagedTileSendsItBack() async {
        let model = await seated()
        drop(model, index: 0, on: Cell(row: 20, col: 19))
        XCTAssertTrue(model.hasStaged)

        model.adoptOccupy(rivalsWord())

        XCTAssertFalse(model.hasStaged, "the square is theirs now")
        XCTAssertEqual(model.toast?.text, "Someone got there first.")
        XCTAssertEqual(model.rack.count, OCCUPY_HAND, "the tile is back in the pile")
    }
}
