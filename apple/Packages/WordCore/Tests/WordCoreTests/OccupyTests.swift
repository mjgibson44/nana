import Foundation
import Testing
@testable import WordCore

/// The Occupy rules: a fixed shared board, corner starts, capture by
/// crossing, tiles worth their longest word, and an end on the clock or a
/// stall. Pure, so the whole rule set is pinned here without a network.

/// A tiny dictionary: only what these boards spell.
private let words: Set<String> = [
    "cat", "cats", "scat", "tea", "eat", "ate", "car", "arc", "art", "tar", "rat",
    "act", "star", "stare", "rest", "test", "set", "net", "ten", "tan", "ant",
]
private func isWord(_ w: String) -> Bool { words.contains(w) }

private func fresh(players: Int = 2, size: Int? = nil) -> OccupyState {
    let seats = (0..<players).map { "p\($0)" }
    return OccupyState(size: size ?? occupyBoardSize(players: players), seats: seats)
}

/// A word laid across from `at`, as a placement.
private func across(_ word: String, from cell: Cell, borrowing: [CellKey] = []) -> OccupyPlacement {
    var tiles: [CellKey: String] = [:]
    for (offset, letter) in word.enumerated() {
        let key = keyOf(cell.row, cell.col + offset)
        if !borrowing.contains(key) { tiles[key] = String(letter) }
    }
    return OccupyPlacement(tiles: tiles, borrowed: borrowing)
}

private func down(_ word: String, from cell: Cell, borrowing: [CellKey] = []) -> OccupyPlacement {
    var tiles: [CellKey: String] = [:]
    for (offset, letter) in word.enumerated() {
        let key = keyOf(cell.row + offset, cell.col)
        if !borrowing.contains(key) { tiles[key] = String(letter) }
    }
    return OccupyPlacement(tiles: tiles, borrowed: borrowing)
}

@Suite("Occupy: the board and the seats") struct OccupyGeometry {
    @Test("two players get Scrabble's board, more get Go's")
    func boardSizes() {
        #expect(occupyBoardSize(players: 2) == 15)
        #expect(occupyBoardSize(players: 3) == 19)
        #expect(occupyBoardSize(players: 4) == 19)
        #expect(occupySeconds(players: 2) == 180)
        #expect(occupySeconds(players: 4) == 240)
    }

    @Test("two players start diagonal, in the centres of their quadrants")
    func diagonalStarts() {
        let a = occupyStartCell(seat: 0, size: 15)
        let b = occupyStartCell(seat: 1, size: 15)
        #expect(a == Cell(row: 3, col: 3))
        #expect(b == Cell(row: 11, col: 11))
        #expect(occupyQuadrant(of: a, size: 15) == 0)
        #expect(occupyQuadrant(of: b, size: 15) == 1)
    }

    @Test("four players take every quadrant")
    func fourCorners() {
        let quadrants = (0..<4).map { occupyQuadrant(of: occupyStartCell(seat: $0, size: 19), size: 19) }
        #expect(quadrants == [0, 1, 2, 3])
    }

    @Test("the centre lines of an odd board belong to nobody")
    func centreLines() {
        #expect(occupyQuadrant(of: Cell(row: 7, col: 2), size: 15) == nil)
        #expect(occupyQuadrant(of: Cell(row: 2, col: 7), size: 15) == nil)
        #expect(occupyQuadrant(of: Cell(row: 8, col: 8), size: 15) == 1)
    }

    @Test("gap cells are where the gaps land, laid out like the placement")
    func gapCellsFollowThePlan() {
        var board = TileMap()
        board[keyOf(3, 4)] = "a"
        let picks = [
            Pick(letter: "c", rackIndex: 0), Pick(letter: nil, rackIndex: GAP),
            Pick(letter: "t", rackIndex: 1),
        ]
        let gaps = gapCells(
            board: board, bounds: Bounds(size: 15), anchor: Cell(row: 3, col: 3), dir: .across,
            picks: picks)
        #expect(gaps == [keyOf(3, 4)])
    }
}

@Suite("Occupy: every seat's own view") struct OccupyRotations {
    @Test("a quarter turn clockwise, and the turns that follow it")
    func rotationFormulas() {
        let cell = Cell(row: 3, col: 3)
        #expect(rotateCell(cell, size: 15, by: .upright) == cell)
        #expect(rotateCell(cell, size: 15, by: .quarter) == Cell(row: 3, col: 11))
        #expect(rotateCell(cell, size: 15, by: .half) == Cell(row: 11, col: 11))
        #expect(rotateCell(cell, size: 15, by: .threeQuarters) == Cell(row: 11, col: 3))
        for rotation in OccupyRotation.allCases {
            let there = rotateCell(cell, size: 15, by: rotation)
            #expect(rotateCell(there, size: 15, by: rotation.inverse) == cell, "\(rotation) undoes")
        }
        var turned = Cell(row: 2, col: 9)
        for _ in 0..<4 { turned = rotateCell(turned, size: 19, by: .quarter) }
        #expect(turned == Cell(row: 2, col: 9), "four quarters is a full turn")
    }

    @Test("every seat's start square lands top-left in its own frame")
    func everySeatStartsTopLeftInItsOwnFrame() {
        for size in [15, 19] {
            let home = occupyStartCell(seat: 0, size: size)
            for seat in 0..<4 {
                let start = occupyStartCell(seat: seat, size: size)
                #expect(
                    rotateCell(start, size: size, by: occupyRotation(seat: seat)) == home,
                    "seat \(seat) on \(size)")
            }
        }
    }

    @Test("an opener typed rightward at home heads toward the middle on the host's board")
    func openersHeadTowardTheMiddle() {
        // CAT from the top-left start of a 15-board, as each seat types it.
        let home = [Cell(row: 3, col: 3), Cell(row: 3, col: 4), Cell(row: 3, col: 5)]
        func hosted(_ seat: Int) -> [Cell] {
            home.map { rotateCell($0, size: 15, by: occupyRotation(seat: seat).inverse) }
        }
        #expect(hosted(0) == [Cell(row: 3, col: 3), Cell(row: 3, col: 4), Cell(row: 3, col: 5)])
        #expect(hosted(1) == [Cell(row: 11, col: 11), Cell(row: 11, col: 10), Cell(row: 11, col: 9)])
        #expect(hosted(2) == [Cell(row: 3, col: 11), Cell(row: 4, col: 11), Cell(row: 5, col: 11)])
        #expect(hosted(3) == [Cell(row: 11, col: 3), Cell(row: 10, col: 3), Cell(row: 9, col: 3)])
    }

    @Test("boards, owners and placements turn together, in order")
    func boardsRotateWithTheirOrderAndOwners() {
        var board = TileMap()
        board[keyOf(3, 3)] = "c"
        board[keyOf(3, 4)] = "a"
        board[keyOf(3, 5)] = "t"
        let turned = board.rotated(size: 15, by: .half)
        #expect(turned.keys == [keyOf(11, 11), keyOf(11, 10), keyOf(11, 9)], "insertion order kept")
        #expect(turned[keyOf(11, 9)] == "t")
        #expect(turned.rotated(size: 15, by: .half) == board)
        #expect(board.rotated(size: 15, by: .upright) == board)

        let owners = rotateOwners([keyOf(3, 3): 0, keyOf(11, 11): 1], size: 15, by: .half)
        #expect(owners == [keyOf(11, 11): 0, keyOf(3, 3): 1])

        let placement = across("tea", from: Cell(row: 3, col: 5), borrowing: [keyOf(3, 5)])
            .rotated(size: 15, by: .quarter)
        #expect(placement.borrowed == [keyOf(5, 11)])
        #expect(placement.tiles == [keyOf(6, 11): "e", keyOf(7, 11): "a"])
    }
}

@Suite("Occupy: landing words") struct OccupyPlacements {
    @Test("the opener lands from the start square and is owned by its seat")
    func openerLands() throws {
        let state = fresh()
        let start = state.startCell(seat: 0)
        let next = try occupyApply(across("cat", from: start), seat: 0, at: 1, to: state, isWord: isWord)
        #expect(next.board.count == 3)
        #expect(next.owners[keyOf(start.row, start.col)] == 0)
        #expect(next.opened == [true, false])
        #expect(next.scores == [9, 0], "three tiles in a three-letter word")
        #expect(next.settledAt == [1, 0])
    }

    @Test("an opener that misses the start square is refused")
    func openerOffStart() {
        let state = fresh()
        #expect(throws: OccupyRefusal.openerOffStart) {
            try occupyApply(across("cat", from: Cell(row: 5, col: 5)), seat: 0, at: 1, to: state, isWord: isWord)
        }
    }

    @Test("after the opener every word has to borrow")
    func mustBorrow() throws {
        var state = fresh()
        state = try occupyApply(across("cat", from: state.startCell(seat: 0)), seat: 0, at: 1, to: state, isWord: isWord)
        #expect(throws: OccupyRefusal.mustBorrow) {
            try occupyApply(across("tea", from: Cell(row: 8, col: 3)), seat: 0, at: 2, to: state, isWord: isWord)
        }
    }

    @Test("borrowing a rival's letter captures it, value and all")
    func captureByCrossing() throws {
        var state = fresh()
        let start = state.startCell(seat: 0)  // (3,3): c a t across
        state = try occupyApply(across("cat", from: start), seat: 0, at: 1, to: state, isWord: isWord)
        // Seat 1 plays T-E-A down through the T at (3,5).
        let t = keyOf(3, 5)
        state = try occupyApply(
            down("tea", from: Cell(row: 3, col: 5), borrowing: [t]), seat: 1, at: 2, to: state, isWord: isWord)
        #expect(state.owners[t] == 1, "the borrowed letter flipped")
        #expect(state.opened == [true, true], "borrowing counts as opening")
        // Seat 0 keeps C and A (worth 3 each); seat 1 holds T, E, A (3 each).
        #expect(state.scores == [6, 9])
        #expect(state.settledAt == [2, 2], "both scores moved on the capture")
    }

    @Test("a tile is worth the longest word it sits in")
    func longestWordValue() throws {
        var state = fresh()
        let start = state.startCell(seat: 0)
        state = try occupyApply(across("cat", from: start), seat: 0, at: 1, to: state, isWord: isWord)
        // STARE down through the A at (3,4): s above, r e below → the A is now in a 5-letter word.
        let a = keyOf(3, 4)
        state = try occupyApply(
            down("stare", from: Cell(row: 1, col: 4), borrowing: [a]), seat: 1, at: 2, to: state, isWord: isWord)
        let values = occupyTileValues(state.board)
        #expect(values[a] == 5)
        #expect(values[keyOf(3, 3)] == 3)
        #expect(state.scores == [6, 25])
    }

    @Test("a square someone got to first is refused, not overwritten")
    func takenSquare() throws {
        var state = fresh()
        state = try occupyApply(across("cat", from: state.startCell(seat: 0)), seat: 0, at: 1, to: state, isWord: isWord)
        var clash = across("tea", from: Cell(row: 3, col: 5), borrowing: [keyOf(3, 5)])
        // Pretend the client's board didn't know (3,6) was taken.
        clash.tiles[keyOf(3, 4)] = "x"
        #expect(throws: OccupyRefusal.taken(keyOf(3, 4))) {
            try occupyApply(clash, seat: 1, at: 2, to: state, isWord: isWord)
        }
    }

    @Test("a word that doesn't read is refused with its name")
    func notAWord() throws {
        var state = fresh()
        state = try occupyApply(across("cat", from: state.startCell(seat: 0)), seat: 0, at: 1, to: state, isWord: isWord)
        let bad = down("tzz", from: Cell(row: 3, col: 5), borrowing: [keyOf(3, 5)])
        #expect(throws: OccupyRefusal.notAWord(["tzz"])) {
            try occupyApply(bad, seat: 1, at: 2, to: state, isWord: isWord)
        }
    }

    @Test("a word reads either way along its line, since every seat writes toward the middle")
    func aWordReadsEitherWay() throws {
        #expect(occupyIsWord("tac", isWord: isWord))
        #expect(occupyIsWord("cat", isWord: isWord))
        #expect(!occupyIsWord("tzz", isWord: isWord))

        // Seat 1's CAT, typed rightward from its own top-left, arrives as
        // T-A-C ending on its start square in the host's frame.
        let next = try occupyApply(
            across("tac", from: Cell(row: 11, col: 9)), seat: 1, at: 1, to: fresh(), isWord: isWord)
        #expect(next.scores == [0, 9])
        #expect(next.owners[keyOf(11, 11)] == 1)
        #expect(next.opened == [false, true])

        // Seat 3 on the big board writes downward, reversed, toward the middle.
        let four = try occupyApply(
            down("tac", from: Cell(row: 12, col: 4)), seat: 3, at: 1, to: fresh(players: 4), isWord: isWord)
        #expect(four.owners[keyOf(14, 4)] == 3)
        #expect(four.scores == [0, 0, 0, 9])
    }

    @Test("a word can't leave the board, and a placement can't scatter")
    func boundsAndLines() throws {
        let state = fresh()
        #expect(throws: OccupyRefusal.offTheBoard(keyOf(3, 15))) {
            try occupyApply(across("catscatscatsx", from: Cell(row: 3, col: 3)), seat: 0, at: 1, to: state, isWord: isWord)
        }
        var scattered = across("cat", from: state.startCell(seat: 0))
        scattered.tiles[keyOf(9, 9)] = "s"
        #expect(throws: OccupyRefusal.notInALine) {
            try occupyApply(scattered, seat: 0, at: 1, to: state, isWord: isWord)
        }
    }

    @Test("borrowing needs a letter to borrow, and a seat to borrow with")
    func borrowingChecks() {
        let state = fresh()
        #expect(throws: OccupyRefusal.nothingToBorrow(keyOf(5, 5))) {
            try occupyApply(
                across("cat", from: Cell(row: 5, col: 4), borrowing: [keyOf(5, 5)]), seat: 0, at: 1,
                to: state, isWord: isWord)
        }
        #expect(throws: OccupyRefusal.notSeated) {
            try occupyApply(across("cat", from: state.startCell(seat: 0)), seat: 7, at: 1, to: state, isWord: isWord)
        }
    }

    @Test("the state round-trips through JSON, owners and all")
    func codable() throws {
        var state = fresh(players: 4)
        state = try occupyApply(across("cat", from: state.startCell(seat: 0)), seat: 0, at: 1, to: state, isWord: isWord)
        let data = try JSONEncoder().encode(state)
        let back = try JSONDecoder().decode(OccupyState.self, from: data)
        #expect(back == state)
    }
}

@Suite("Occupy: standings and the end") struct OccupyStandings {
    @Test("most value wins, and a leaver can't")
    func valueWins() {
        var state = fresh(players: 3)
        state.scores = [10, 30, 20]
        #expect(occupyRanking(state).map(\.seat) == [1, 2, 0])
        #expect(occupyWinner(state) == 1)
        #expect(occupyRanking(state, left: [1]).map(\.seat) == [2, 0, 1])
        #expect(occupyWinner(state, left: [1]) == 2)
    }

    @Test("a tie goes to quadrants held, then to whoever got there first")
    func tiebreaks() throws {
        var state = fresh()
        state.scores = [12, 12]
        // Seat 0 holds its own quadrant; seat 1 holds nothing.
        state.owners = [keyOf(1, 1): 0, keyOf(2, 2): 0, keyOf(12, 12): 1, keyOf(1, 12): 0]
        #expect(occupyQuadrantsHeld(owners: state.owners, size: 15, seats: 2) == [2, 1])
        #expect(occupyWinner(state) == 0)

        // Level on quadrants too: the earlier score stands.
        state.owners = [:]
        state.settledAt = [40, 25]
        #expect(occupyWinner(state) == 1)

        // Level on everything: a draw, and both rank first.
        state.settledAt = [25, 25]
        #expect(occupyWinner(state) == nil)
        #expect(occupyRanking(state).map(\.rank) == [1, 1])
    }

    @Test("a quadrant goes to whoever has the most tiles in it, or nobody")
    func quadrantsHeld() {
        let owners: [CellKey: Int] = [
            keyOf(1, 1): 0, keyOf(1, 2): 0, keyOf(2, 1): 1,  // top-left: seat 0
            keyOf(12, 12): 1, keyOf(12, 13): 0,  // bottom-right: tied
        ]
        #expect(occupyQuadrantsHeld(owners: owners, size: 15, seats: 2) == [1, 0])
    }

    @Test("the clock ends it, the stall ends it early, and the grace holds the stall off")
    func endings() {
        #expect(occupyEnd(elapsed: 10, sinceLastWord: 10, players: 2) == nil)
        #expect(occupyEnd(elapsed: 180, sinceLastWord: 1, players: 2) == .clock)
        #expect(occupyEnd(elapsed: 240, sinceLastWord: 1, players: 4) == .clock)
        // A minute of silence, but the grace only just ended: the stall clock
        // starts at the end of the grace, not at the deal.
        #expect(occupyEnd(elapsed: 60, sinceLastWord: 60, players: 2) == nil)
        #expect(occupyEnd(elapsed: 89, sinceLastWord: 89, players: 2) == nil)
        #expect(occupyEnd(elapsed: 90, sinceLastWord: 90, players: 2) == .stall)
        // A word at 40s resets the stall clock.
        #expect(occupyEnd(elapsed: 99, sinceLastWord: 59, players: 2) == nil)
        #expect(occupyEnd(elapsed: 100, sinceLastWord: 60, players: 2) == .stall)
    }

    @Test("the stall countdown shows only for its last stretch")
    func stallCountdown() {
        #expect(occupyStallSecondsLeft(elapsed: 5, sinceLastWord: 5) == nil, "grace")
        #expect(occupyStallSecondsLeft(elapsed: 35, sinceLastWord: 5) == nil, "just started")
        #expect(occupyStallSecondsLeft(elapsed: 60, sinceLastWord: 30) == nil, "not in the window yet")
        #expect(occupyStallSecondsLeft(elapsed: 70, sinceLastWord: 40) == 20)
        #expect(occupyStallSecondsLeft(elapsed: 75, sinceLastWord: 45) == 15)
        #expect(occupyStallSecondsLeft(elapsed: 80, sinceLastWord: 80) == 10, "measured from the grace")
        #expect(occupyStallSecondsLeft(elapsed: 200, sinceLastWord: 100) == 0)
    }
}
