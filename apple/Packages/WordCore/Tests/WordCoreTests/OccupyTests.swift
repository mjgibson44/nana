import Foundation
import Testing
@testable import WordCore

/// The Occupy rules: an unbounded shared board laid out in a frame, corner
/// starts off its middle, words that are each player's own, tiles worth their
/// owner's longest word, zones fought over for a minute apiece, and an end on
/// the clock or a stall. Pure, so the whole rule set is pinned here without a
/// network.

/// A tiny dictionary: only what these boards spell.
private let words: Set<String> = [
    "cat", "cats", "scat", "tea", "eat", "ate", "car", "arc", "art", "tar", "rat",
    "act", "star", "stare", "rest", "test", "set", "net", "ten", "tan", "ant",
]
private func isWord(_ w: String) -> Bool { words.contains(w) }

private func fresh(players: Int = 2) -> OccupyState {
    OccupyState(seats: (0..<players).map { "p\($0)" })
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

/// Within a zone's spawn reach of a candidate centre.
private func near(_ cell: Cell, _ centre: Cell) -> Bool {
    abs(cell.row - centre.row) <= OCCUPY_ZONE_REACH
        && abs(cell.col - centre.col) <= OCCUPY_ZONE_REACH
}

/// Seat 0's opener: CAT across from its start square.
private func opened() throws -> OccupyState {
    let state = fresh()
    return try occupyApply(
        across("cat", from: state.startCell(seat: 0)), seat: 0, at: 1, to: state, isWord: isWord)
}

@Suite("Occupy: the frame and the seats") struct OccupyGeometry {
    @Test("the board is laid out in the solo board's frame, and the clock is ten minutes")
    func frameAndClock() {
        #expect(OCCUPY_FRAME == BOARD_SIZE)
        #expect(OCCUPY_SECONDS == 600)
        #expect(occupyCentre() == Cell(row: 16, col: 16))
        #expect(fresh().frame == OCCUPY_FRAME)
    }

    @Test("two players start diagonal, eight cells apart, either side of the middle")
    func diagonalStarts() {
        let a = occupyStartCell(seat: 0, players: 2)
        let b = occupyStartCell(seat: 1, players: 2)
        #expect(a == Cell(row: 12, col: 12))
        #expect(b == Cell(row: 20, col: 20))
        #expect(occupyQuadrant(of: a, size: OCCUPY_FRAME) == 0)
        #expect(occupyQuadrant(of: b, size: OCCUPY_FRAME) == 1)
        #expect(fresh().startCell(seat: 1) == b)
    }

    @Test("four players take every quadrant, ten cells apart")
    func fourCorners() {
        let starts = (0..<4).map { occupyStartCell(seat: $0, players: 4) }
        #expect(starts == [
            Cell(row: 11, col: 11), Cell(row: 21, col: 21),
            Cell(row: 11, col: 21), Cell(row: 21, col: 11),
        ])
        let quadrants = starts.map { occupyQuadrant(of: $0, size: OCCUPY_FRAME) }
        #expect(quadrants == [0, 1, 2, 3])
    }

    @Test("the centre lines of an odd frame belong to nobody, and its edge isn't one")
    func centreLines() {
        #expect(occupyQuadrant(of: Cell(row: 7, col: 2), size: 15) == nil)
        #expect(occupyQuadrant(of: Cell(row: 2, col: 7), size: 15) == nil)
        #expect(occupyQuadrant(of: Cell(row: 8, col: 8), size: 15) == 1)
        // Past the frame is still a quadrant: the board grows there.
        #expect(occupyQuadrant(of: Cell(row: -3, col: 40), size: 15) == 2)
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

    @Test("a cell past the frame turns as well as one inside it")
    func rotationsReachPastTheFrame() {
        let outside = Cell(row: -4, col: 40)
        for rotation in OccupyRotation.allCases {
            let there = rotateCell(outside, size: OCCUPY_FRAME, by: rotation)
            #expect(rotateCell(there, size: OCCUPY_FRAME, by: rotation.inverse) == outside)
        }
        #expect(rotateCell(outside, size: OCCUPY_FRAME, by: .half) == Cell(row: 36, col: -8))
        #expect(rotateCell(occupyCentre(), size: OCCUPY_FRAME, by: .quarter) == occupyCentre())
    }

    @Test("every seat's start square lands top-left in its own frame")
    func everySeatStartsTopLeftInItsOwnFrame() {
        for players in [2, 3, 4] {
            let home = occupyStartCell(seat: 0, players: players)
            for seat in 0..<players {
                let start = occupyStartCell(seat: seat, players: players)
                #expect(
                    rotateCell(start, size: OCCUPY_FRAME, by: occupyRotation(seat: seat)) == home,
                    "seat \(seat) of \(players)")
            }
        }
    }

    @Test("an opener typed rightward at home heads toward the middle on the host's board")
    func openersHeadTowardTheMiddle() {
        // CAT from the top-left start of a 15-frame, as each seat types it.
        let home = [Cell(row: 3, col: 3), Cell(row: 3, col: 4), Cell(row: 3, col: 5)]
        func hosted(_ seat: Int) -> [Cell] {
            home.map { rotateCell($0, size: 15, by: occupyRotation(seat: seat).inverse) }
        }
        #expect(hosted(0) == [Cell(row: 3, col: 3), Cell(row: 3, col: 4), Cell(row: 3, col: 5)])
        #expect(hosted(1) == [Cell(row: 11, col: 11), Cell(row: 11, col: 10), Cell(row: 11, col: 9)])
        #expect(hosted(2) == [Cell(row: 3, col: 11), Cell(row: 4, col: 11), Cell(row: 5, col: 11)])
        #expect(hosted(3) == [Cell(row: 11, col: 3), Cell(row: 10, col: 3), Cell(row: 9, col: 3)])
    }

    @Test("boards, owners, zones and placements turn together, in order")
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

        let zone = OccupyZone(centre: Cell(row: 3, col: 4)).rotated(size: 15, by: .half)
        #expect(zone.centre == Cell(row: 11, col: 10))
        #expect(Set(zone.keys) == Set(OccupyZone(centre: Cell(row: 3, col: 4)).keys.map {
            rotateKey($0, size: 15, by: .half)
        }))
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
        let state = try opened()
        #expect(throws: OccupyRefusal.mustBorrow) {
            try occupyApply(across("tea", from: Cell(row: 8, col: 3)), seat: 0, at: 2, to: state, isWord: isWord)
        }
    }

    @Test("a rival's letter can't be borrowed: every word is its own player's")
    func borrowingARivalsLetterIsRefused() throws {
        let state = try opened()  // seat 0: c a t across from (12,12)
        let t = keyOf(12, 14)
        #expect(throws: OccupyRefusal.notYours(t)) {
            try occupyApply(
                down("tea", from: Cell(row: 12, col: 14), borrowing: [t]), seat: 1, at: 2,
                to: state, isWord: isWord)
        }
        #expect(state.owners[t] == 0, "and nothing changed hands")

        // The same word off the same letter is fine for the seat that owns it.
        let own = try occupyApply(
            down("tea", from: Cell(row: 12, col: 14), borrowing: [t]), seat: 0, at: 2, to: state,
            isWord: isWord)
        #expect(own.owners[keyOf(13, 14)] == 0)
        #expect(own.opened == [true, false], "seat 1 still hasn't opened")
    }

    @Test("a word can't run through a rival's letter, and a hole is still a hole")
    func cantRunThroughARival() throws {
        var state = try opened()  // seat 0: (12,12) c, (12,13) a, (12,14) t
        state.board[keyOf(12, 11)] = "a"  // seat 1's own letter, the far side of it
        state.owners[keyOf(12, 11)] = 1
        state.opened = [true, true]

        // Seat 1 reaching from (12,11) to (12,15) would cross all three of them.
        let through = OccupyPlacement(
            tiles: [keyOf(12, 15): "r", keyOf(12, 16): "t"], borrowed: [keyOf(12, 11)])
        #expect(throws: OccupyRefusal.throughRival(keyOf(12, 12))) {
            try occupyApply(through, seat: 1, at: 3, to: state, isWord: isWord)
        }

        // Empty ground in the way is what it always was.
        let holed = OccupyPlacement(tiles: [keyOf(12, 9): "t"], borrowed: [keyOf(12, 11)])
        #expect(throws: OccupyRefusal.notInALine) {
            try occupyApply(holed, seat: 1, at: 3, to: state, isWord: isWord)
        }
    }

    @Test("two players' words can sit flush, and each is read and valued on its own")
    func flushWordsAreReadApart() throws {
        var state = try opened()  // seat 0: c a t across (12,12)
        for (offset, letter) in "rat".enumerated() {  // seat 1, directly below it
            state.board[keyOf(13, 12 + offset)] = String(letter)
            state.owners[keyOf(13, 12 + offset)] = 1
        }
        // The down pairs across the seam — CR, AA, TT — belong to nobody, so
        // nothing on either side is worth more than its own three-letter word.
        #expect(
            occupyOwnedRuns(board: state.board, owners: state.owners).map(\.word).sorted()
                == ["cat", "rat"])
        let values = occupyTileValues(state.board, owners: state.owners)
        #expect(values.values.allSatisfy { $0 == 3 })
        #expect(occupyScores(board: state.board, owners: state.owners, seats: 2) == [9, 9])
    }

    @Test("a word may land flush against a rival's, borrowing only from itself")
    func flushLanding() throws {
        var state = try opened()
        state.board[keyOf(13, 12)] = "r"
        state.owners[keyOf(13, 12)] = 1
        state.opened = [true, true]
        state.scores = occupyScores(board: state.board, owners: state.owners, seats: 2)
        let next = try occupyApply(
            across("rat", from: Cell(row: 13, col: 12), borrowing: [keyOf(13, 12)]),
            seat: 1, at: 3, to: state, isWord: isWord)
        #expect(next.scores == [9, 9])
        #expect(next.owners[keyOf(12, 13)] == 0, "nothing changes hands")
        #expect(next.settledAt == [1, 3], "only the player who moved")
    }

    @Test("a tile is worth the longest word of its owner's that it sits in")
    func longestWordValue() throws {
        var state = try opened()
        // Seat 0 crosses its own A at (12,13): s t above, r e below.
        let a = keyOf(12, 13)
        state = try occupyApply(
            down("stare", from: Cell(row: 10, col: 13), borrowing: [a]), seat: 0, at: 2, to: state,
            isWord: isWord)
        let values = occupyTileValues(state.board, owners: state.owners)
        #expect(values[a] == 5)
        #expect(values[keyOf(12, 12)] == 3)
        #expect(state.scores == [31, 0])
    }

    @Test("a square someone got to first is refused, not overwritten")
    func takenSquare() throws {
        let state = try opened()
        var clash = across("tea", from: Cell(row: 12, col: 14), borrowing: [keyOf(12, 14)])
        // Pretend the client's board didn't know (12,13) was taken.
        clash.tiles[keyOf(12, 13)] = "x"
        #expect(throws: OccupyRefusal.taken(keyOf(12, 13))) {
            try occupyApply(clash, seat: 1, at: 2, to: state, isWord: isWord)
        }
    }

    @Test("a word that doesn't read is refused with its name")
    func notAWord() throws {
        let state = try opened()
        let bad = down("tzz", from: Cell(row: 12, col: 14), borrowing: [keyOf(12, 14)])
        #expect(throws: OccupyRefusal.notAWord(["tzz"])) {
            try occupyApply(bad, seat: 0, at: 2, to: state, isWord: isWord)
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
            across("tac", from: Cell(row: 20, col: 18)), seat: 1, at: 1, to: fresh(), isWord: isWord)
        #expect(next.scores == [0, 9])
        #expect(next.owners[keyOf(20, 20)] == 1)
        #expect(next.opened == [false, true])

        // Seat 3 of four writes downward, reversed, toward the middle.
        let four = try occupyApply(
            down("tac", from: Cell(row: 19, col: 11)), seat: 3, at: 1, to: fresh(players: 4), isWord: isWord)
        #expect(four.owners[keyOf(21, 11)] == 3)
        #expect(four.scores == [0, 0, 0, 9])
    }

    @Test("the board has no edge: a word can run past the frame, but not scatter")
    func noEdgeButOneLine() throws {
        var state = fresh()
        state.board[keyOf(-3, -3)] = "t"
        state.owners[keyOf(-3, -3)] = 0
        state.opened = [true, true]
        let past = try occupyApply(
            across("tea", from: Cell(row: -3, col: -3), borrowing: [keyOf(-3, -3)]),
            seat: 0, at: 1, to: state, isWord: isWord)
        #expect(past.board[keyOf(-3, -1)] == "a")
        #expect(past.owners[keyOf(-3, -1)] == 0, "owned wherever it is")

        let start = fresh().startCell(seat: 0)
        var scattered = across("cat", from: start)
        scattered.tiles[keyOf(9, 9)] = "s"
        #expect(throws: OccupyRefusal.notInALine) {
            try occupyApply(scattered, seat: 0, at: 1, to: fresh(), isWord: isWord)
        }
        var malformed = across("cat", from: start)
        malformed.tiles["nowhere"] = "s"
        #expect(throws: OccupyRefusal.badSquare("nowhere")) {
            try occupyApply(malformed, seat: 0, at: 1, to: fresh(), isWord: isWord)
        }
    }

    @Test("borrowing needs a letter to borrow, a seat to borrow with, and your own letter")
    func borrowingChecks() throws {
        let state = fresh()
        #expect(throws: OccupyRefusal.nothingToBorrow(keyOf(5, 5))) {
            try occupyApply(
                across("cat", from: Cell(row: 5, col: 4), borrowing: [keyOf(5, 5)]), seat: 0, at: 1,
                to: state, isWord: isWord)
        }
        #expect(throws: OccupyRefusal.notSeated) {
            try occupyApply(across("cat", from: state.startCell(seat: 0)), seat: 7, at: 1, to: state, isWord: isWord)
        }
        // A seat that owns nothing has nothing to borrow, so its first word
        // has to be its opener.
        let theirs = try opened()
        #expect(throws: OccupyRefusal.notYours(keyOf(12, 14))) {
            try occupyApply(
                down("tea", from: Cell(row: 12, col: 14), borrowing: [keyOf(12, 14)]), seat: 1,
                at: 2, to: theirs, isWord: isWord)
        }
    }

    @Test("the state round-trips through JSON, owners and zones and all")
    func codable() throws {
        var state = fresh(players: 4)
        state = try occupyApply(across("cat", from: state.startCell(seat: 0)), seat: 0, at: 1, to: state, isWord: isWord)
        state.zones = [
            OccupyZone(
                slot: 0, centre: Cell(row: 5, col: 5), opensAt: 60, closesAt: 120, winner: 2,
                counts: [1, 0, 4, 0], resolved: true),
            OccupyZone(slot: 1, centre: Cell(row: -2, col: 30), opensAt: 135, closesAt: 195),
        ]
        state.bonuses = [0, 0, OCCUPY_ZONE_BONUS, 0]
        let data = try JSONEncoder().encode(state)
        let back = try JSONDecoder().decode(OccupyState.self, from: data)
        #expect(back == state)

        // A snapshot with no zones in it is one with none.
        let bare = """
            {"frame":33,"seats":["a","b"],"board":[],"owners":{},"opened":[false,false],
             "scores":[0,0],"settledAt":[0,0]}
            """
        let decoded = try JSONDecoder().decode(OccupyState.self, from: Data(bare.utf8))
        #expect(decoded.zones.isEmpty)
        #expect(decoded.bonuses == [0, 0])
        #expect(decoded.end == nil)
    }
}

@Suite("Occupy: zones") struct OccupyZones {
    @Test("a zone is five by five around its centre")
    func shape() {
        let zone = OccupyZone(centre: Cell(row: 5, col: 8))
        #expect(zone.origin == Cell(row: 3, col: 6))
        #expect(zone.cells.count == 25)
        #expect(zone.contains(Cell(row: 7, col: 10)))
        #expect(!zone.contains(Cell(row: 8, col: 10)))
        #expect(zone.overlaps(OccupyZone(centre: Cell(row: 9, col: 12))))
        #expect(!zone.overlaps(OccupyZone(centre: Cell(row: 10, col: 13))))
    }

    @Test("a minute open, fifteen seconds' gap, and a minute of grace before the first")
    func schedule() {
        #expect(occupyZoneWindow(slot: 0).opensAt == 60)
        #expect(occupyZoneWindow(slot: 0).closesAt == 120)
        #expect(occupyZoneWindow(slot: 1).opensAt == 135)
        #expect(occupyZoneWindow(slot: 6).closesAt == 570)

        #expect(occupyZonesDue(elapsed: 0) == 0)
        #expect(occupyZonesDue(elapsed: OCCUPY_ZONE_FIRST_SECONDS - 1) == 0)
        #expect(occupyZonesDue(elapsed: OCCUPY_ZONE_FIRST_SECONDS) == 1)
        #expect(occupyZonesDue(elapsed: 134) == 1)
        #expect(occupyZonesDue(elapsed: 135) == 2)

        // Seven in a ten-minute game: an eighth would open at 9:45 with too
        // little of the clock left to be worth racing for.
        #expect(occupyZoneSlots() == 7)
        #expect(occupyZoneFits(slot: 6))
        #expect(!occupyZoneFits(slot: 7))
        #expect(occupyZonesDue(elapsed: Double(OCCUPY_SECONDS)) == 7)
    }

    @Test("the zone clock runs open, gap, open — and stops for the endgame")
    func clock() {
        #expect(occupyZoneClock(elapsed: 0) == .next(seconds: 60))
        #expect(occupyZoneClock(elapsed: 60) == .open(secondsLeft: 60))
        #expect(occupyZoneClock(elapsed: 90) == .open(secondsLeft: 30))
        #expect(occupyZoneClock(elapsed: 120) == .next(seconds: 15))
        #expect(occupyZoneClock(elapsed: 135) == .open(secondsLeft: 60))
        #expect(occupyZoneClock(elapsed: 570) == .done)
        #expect(occupyZoneClock(elapsed: Double(OCCUPY_SECONDS)) == .done)
    }

    /// A zone at (5,5) — rows 3…7, cols 3…7 — with three of seat 0's tiles
    /// inside it and two of seat 1's.
    private func contested() -> OccupyState {
        var state = fresh()
        state.zones = [
            OccupyZone(slot: 0, centre: Cell(row: 5, col: 5), opensAt: 60, closesAt: 120)
        ]
        for col in 3...5 {
            state.board[keyOf(4, col)] = "a"
            state.owners[keyOf(4, col)] = 0
        }
        for col in 5...6 {
            state.board[keyOf(6, col)] = "b"
            state.owners[keyOf(6, col)] = 1
        }
        state.scores = occupyScores(board: state.board, owners: state.owners, seats: 2)
        return state
    }

    @Test("at the whistle the zone goes to whoever holds the most tiles in it")
    func resolution() {
        let state = contested()
        #expect(state.scores == [9, 4], "three in a row and two in a row")
        let counts = occupyZoneCounts(state.zones[0], owners: state.owners, seats: 2)
        #expect(counts == [3, 2])
        #expect(occupyZoneWinner(counts) == 0)
        #expect(occupyZoneWinner([0, 0]) == nil, "an empty zone goes to nobody")

        #expect(occupyCloseZones(state, elapsed: 119, at: 10) == state, "the minute isn't up")

        let closed = occupyCloseZones(state, elapsed: 120, at: 10)
        #expect(closed.zones[0].resolved)
        #expect(!closed.zones[0].isOpen)
        #expect(closed.zones[0].winner == 0)
        #expect(closed.zones[0].counts == [3, 2])
        #expect(closed.bonuses == [OCCUPY_ZONE_BONUS, 0])
        #expect(closed.scores == [9 + OCCUPY_ZONE_BONUS, 4], "the board's value, plus the zone")
        #expect(closed.settledAt == [10, 0], "only the seat whose score moved")
        #expect(closed.zonesWon == [1, 0])
        #expect(closed.openZone == nil)

        #expect(occupyCloseZones(closed, elapsed: 200, at: 20) == closed, "a whistle goes once")
    }

    @Test("a zone held level goes to nobody")
    func tiedZone() {
        var state = contested()
        state.board[keyOf(6, 7)] = "b"
        state.owners[keyOf(6, 7)] = 1
        state.scores = occupyScores(board: state.board, owners: state.owners, seats: 2)
        let closed = occupyCloseZones(state, elapsed: 120, at: 10)
        #expect(closed.zones[0].counts == [3, 3])
        #expect(closed.zones[0].resolved)
        #expect(closed.zones[0].winner == nil)
        #expect(closed.bonuses == [0, 0])
        #expect(closed.scores == state.scores)
    }

    @Test("a zone still open when the game ends is closed at the whistle")
    func closedAtTheEnd() {
        let state = contested()
        #expect(state.openZone != nil)
        let closed = occupyCloseZones(state, elapsed: 61, all: true, at: 61)
        #expect(closed.zones[0].resolved)
        #expect(closed.zones[0].winner == 0)
        #expect(closed.bonuses == [OCCUPY_ZONE_BONUS, 0])
    }

    @Test("a zone goes on empty ground both players can reach, clear of starts and other zones")
    func candidates() throws {
        let state = try opened()  // seat 0's CAT is down; seat 1 hasn't opened
        let starts = state.seats.indices.map { state.startCell(seat: $0) }
        let candidates = occupyZoneCandidates(state)
        #expect(!candidates.isEmpty)
        for centre in candidates {
            let zone = OccupyZone(centre: centre)
            #expect(zone.keys.allSatisfy { state.board[$0] == nil }, "nothing under it")
            #expect(!starts.contains { zone.contains($0) }, "not over a start square")
            // Within reach of seat 0's letters *and* of seat 1's start: with
            // nothing to capture, a zone one player alone can reach is a gift
            // rather than a contest.
            #expect(state.board.keys.map(parseKey).contains { near($0, centre) })
            #expect(near(starts[1], centre))
        }

        // A zone already down keeps the next one off its ground.
        var withZone = state
        withZone.zones = [OccupyZone(centre: candidates[0])]
        for centre in occupyZoneCandidates(withZone) {
            #expect(!OccupyZone(centre: centre).overlaps(withZone.zones[0]))
        }
    }

    @Test("ground only one player can reach will do when there's no fairer patch")
    func lonelyGround() throws {
        var state = try opened()
        state.opened = [true, true]  // seat 1 has opened, and owns nothing near
        let candidates = occupyZoneCandidates(state)
        #expect(!candidates.isEmpty)
        #expect(
            candidates.allSatisfy { centre in
                state.board.keys.map(parseKey).contains { near($0, centre) }
            })
    }

    @Test("before anyone opens, zones sit near the start squares")
    func beforeTheOpeners() {
        let state = fresh()
        let starts = [state.startCell(seat: 0), state.startCell(seat: 1)]
        let candidates = occupyZoneCandidates(state)
        #expect(!candidates.isEmpty)
        for centre in candidates {
            #expect(starts.contains { near($0, centre) })
        }
    }

    @Test("the same roll puts the zone in the same place, on its slot's clock")
    func deterministicSpawn() throws {
        let state = try opened()
        let a = occupySpawnZone(state, slot: 1, rng: seededRng("seed/zones/1"))
        let b = occupySpawnZone(state, slot: 1, rng: seededRng("seed/zones/1"))
        #expect(a != nil)
        #expect(a == b)
        #expect(a?.slot == 1)
        #expect(a?.opensAt == 135)
        #expect(a?.closesAt == 195)
        #expect(a?.resolved == false)
        #expect(occupyZoneCandidates(state).contains(a!.centre))
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

    @Test("a tie goes to zones taken, then quadrants held, then to whoever got there first")
    func tiebreaks() throws {
        var state = fresh()
        state.scores = [12, 12]
        // Zones first: the seat that took one is ahead of the seat that didn't.
        state.zones = [
            OccupyZone(slot: 0, centre: Cell(row: 5, col: 5), winner: 1, resolved: true)
        ]
        #expect(state.zonesWon == [0, 1])
        #expect(occupyWinner(state) == 1)
        state.zones = []
        // Seat 0 holds its own quadrant and the top-right; seat 1 holds nothing.
        state.owners = [keyOf(1, 1): 0, keyOf(2, 2): 0, keyOf(20, 20): 1, keyOf(1, 30): 0]
        #expect(occupyQuadrantsHeld(owners: state.owners, size: state.frame, seats: 2) == [2, 1])
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
        #expect(occupyEnd(elapsed: 10, sinceLastWord: 10) == nil)
        #expect(occupyEnd(elapsed: 599, sinceLastWord: 1) == nil)
        #expect(occupyEnd(elapsed: 600, sinceLastWord: 1) == .clock)
        // A minute of silence, but the grace only just ended: the stall clock
        // starts at the end of the grace, not at the deal.
        #expect(occupyEnd(elapsed: 60, sinceLastWord: 60) == nil)
        #expect(occupyEnd(elapsed: 89, sinceLastWord: 89) == nil)
        #expect(occupyEnd(elapsed: 90, sinceLastWord: 90) == .stall)
        // A word at 40s resets the stall clock.
        #expect(occupyEnd(elapsed: 99, sinceLastWord: 59) == nil)
        #expect(occupyEnd(elapsed: 100, sinceLastWord: 60) == .stall)
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
