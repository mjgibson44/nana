import Testing
@testable import WordCore

/// Ported from `src/game/__tests__/placement.test.ts`.

private func picksFrom(_ word: String) -> [Pick] {
    word.enumerated().map { rackIndex, letter in
        Pick(letter: String(letter), rackIndex: rackIndex)
    }
}

/// Picks from a pattern where '.' marks a gap tile, e.g. 'so.ar'.
private func picksWithGaps(_ pattern: String) -> [Pick] {
    pattern.enumerated().map { i, ch in
        ch == "." ? Pick(letter: nil, rackIndex: GAP) : Pick(letter: String(ch), rackIndex: i)
    }
}

@Suite("Placement: planPlacement with gap tiles") struct PlacementPlanPlacementWithGapTiles {
    @Test("lets a gap sit on a letter already on the board")
    func letsAGapSitOnALetterAlreadyOnTheBoard() {
        // SOLAR typed with a gap where the L goes, over an L already at 2,4.
        let board: TileMap = ["2,4": "l"]
        let plan = planPlacement(
            board: board, bounds: Bounds(size: 10),
            anchor: Cell(row: 2, col: 2), dir: .across, picks: picksWithGaps("so.ar")
        )
        #expect(plan.complete == true)
        #expect(plan.unfilledGaps == [])
        // The gap places nothing — the L was already there.
        #expect(plan.steps.map { "\($0.letter)@\($0.key)" } == [
            "s@2,2",
            "o@2,3",
            "a@2,5",
            "r@2,6",
        ])
    }

    @Test("still lays out the whole word when a gap has nothing under it")
    func stillLaysOutTheWholeWordWhenAGapHasNothingUnderIt() {
        // Nothing at 2,4 for the gap to stand on, but the word must stay visible so
        // it can be lined up — it just can't be played yet.
        let plan = planPlacement(
            board: [:], bounds: Bounds(size: 10),
            anchor: Cell(row: 2, col: 2), dir: .across, picks: picksWithGaps("so.ar")
        )
        #expect(plan.complete == false)
        #expect(plan.unfilledGaps == ["2,4"])
        // Every letter is placed, and the gap holds its own square in the middle.
        #expect(plan.steps.map { "\($0.letter)@\($0.key)" } == [
            "s@2,2",
            "o@2,3",
            "a@2,5",
            "r@2,6",
        ])
    }

    @Test("reports every gap left uncovered")
    func reportsEveryGapLeftUncovered() {
        let plan = planPlacement(
            board: [:], bounds: Bounds(size: 10),
            anchor: Cell(row: 2, col: 2), dir: .across, picks: picksWithGaps("s.a.r")
        )
        #expect(plan.unfilledGaps == ["2,3", "2,5"])
        #expect(plan.complete == false)
        #expect(plan.steps.map(\.key) == ["2,2", "2,4", "2,6"])
    }

    @Test("refuses a gap that misses the letter it was aimed at")
    func refusesAGapThatMissesTheLetterItWasAimedAt() {
        // The L is one cell further along than the gap reaches, so the gap comes
        // down on an empty square and the L gets flowed over instead.
        let plan = planPlacement(
            board: ["2,5": "l"], bounds: Bounds(size: 10),
            anchor: Cell(row: 2, col: 2), dir: .across, picks: picksWithGaps("so.ar")
        )
        #expect(plan.complete == false)
        #expect(plan.unfilledGaps == ["2,4"])
    }

    @Test("still flows letters over existing tiles without a gap")
    func stillFlowsLettersOverExistingTilesWithoutAGap() {
        // Typing the word minus its crossing letter works as it always has.
        let plan = planPlacement(
            board: ["2,4": "l"], bounds: Bounds(size: 10),
            anchor: Cell(row: 2, col: 2), dir: .across, picks: picksFrom("soar")
        )
        #expect(plan.complete == true)
        #expect(plan.steps.map(\.key) == ["2,2", "2,3", "2,5", "2,6"])
    }
}

@Suite("Placement: anchorForGapTarget") struct PlacementAnchorForGapTarget {
    @Test("starts the word so the gap lands on the clicked letter")
    func startsTheWordSoTheGapLandsOnTheClickedLetter() throws {
        // SOLAR with a hole for the L, aimed at an L already at 2,4: the word has
        // to start two squares back so S and O land in front of it.
        let board: TileMap = ["2,4": "l"]
        let anchor = anchorForGapTarget(
            board: board, bounds: Bounds(size: 10),
            target: Cell(row: 2, col: 4), dir: .across, picks: picksWithGaps("so.ar")
        )
        #expect(anchor == Cell(row: 2, col: 2))
        // And planning from there really does put the gap on the L.
        let plan = planPlacement(
            board: board, bounds: Bounds(size: 10),
            anchor: try #require(anchor), dir: .across, picks: picksWithGaps("so.ar")
        )
        #expect(plan.complete == true)
        #expect(plan.steps.map(\.key) == ["2,2", "2,3", "2,5", "2,6"])
    }

    @Test("is the clicked cell itself when the gap comes first")
    func isTheClickedCellItselfWhenTheGapComesFirst() {
        #expect(anchorForGapTarget(
            board: [:], bounds: Bounds(size: 10),
            target: Cell(row: 3, col: 3), dir: .down, picks: picksWithGaps(".at")
        ) == Cell(row: 3, col: 3))
    }

    @Test("aims only the first of several gaps at the click")
    func aimsOnlyTheFirstOfSeveralGapsAtTheClick() {
        let anchor = anchorForGapTarget(
            board: [:], bounds: Bounds(size: 10),
            target: Cell(row: 2, col: 4), dir: .across, picks: picksWithGaps("s.a.r")
        )
        #expect(anchor == Cell(row: 2, col: 3))
    }

    @Test("flows the leading letters back over words already on the board")
    func flowsTheLeadingLettersBackOverWordsAlreadyOnTheBoard() throws {
        // CAT sits at 2,2-2,4. The two letters before the gap flow back over it,
        // so the first lands at 2,1 and the second right before the target.
        let board: TileMap = ["2,2": "c", "2,3": "a", "2,4": "t", "2,6": "x"]
        let anchor = anchorForGapTarget(
            board: board, bounds: Bounds(size: 10),
            target: Cell(row: 2, col: 6), dir: .across, picks: picksWithGaps("ab.d")
        )
        #expect(anchor == Cell(row: 2, col: 1))
        let plan = planPlacement(
            board: board, bounds: Bounds(size: 10),
            anchor: try #require(anchor), dir: .across, picks: picksWithGaps("ab.d")
        )
        #expect(plan.complete == true)
        #expect(plan.steps.map(\.key) == ["2,1", "2,5", "2,7"])
    }

    @Test("refuses when the square right before the gap is taken")
    func refusesWhenTheSquareRightBeforeTheGapIsTaken() {
        // A gap claims the very next square after the letter before it, so that
        // letter has nowhere to go when 2,5 (right before the target) is occupied.
        let board: TileMap = ["2,5": "x", "2,6": "l"]
        #expect(anchorForGapTarget(
            board: board, bounds: Bounds(size: 10),
            target: Cell(row: 2, col: 6), dir: .across, picks: picksWithGaps("so.ar")
        ) == nil)
    }

    @Test("refuses when the leading letters run off the grid")
    func refusesWhenTheLeadingLettersRunOffTheGrid() {
        #expect(anchorForGapTarget(
            board: [:], bounds: Bounds(size: 10),
            target: Cell(row: 0, col: 1), dir: .across, picks: picksWithGaps("so.ar")
        ) == nil)
    }

    @Test("returns null when the picks have no gap")
    func returnsNullWhenThePicksHaveNoGap() {
        #expect(anchorForGapTarget(
            board: [:], bounds: Bounds(size: 10),
            target: Cell(row: 2, col: 2), dir: .across, picks: picksFrom("cat")
        ) == nil)
    }
}

@Suite("Placement: impliedDirections") struct PlacementImpliedDirections {
    @Test("reads a letter to the left as typing across")
    func readsALetterToTheLeftAsTypingAcross() {
        #expect(impliedDirections(board: ["4,3": "a"], cell: Cell(row: 4, col: 4)) == [.across])
    }

    @Test("reads a letter above as typing down")
    func readsALetterAboveAsTypingDown() {
        #expect(impliedDirections(board: ["3,4": "a"], cell: Cell(row: 4, col: 4)) == [.down])
    }

    @Test("has no opinion with nothing behind the cell")
    func hasNoOpinionWithNothingBehindTheCell() {
        // Letters to the right and below say nothing about where typing starts.
        #expect(impliedDirections(board: ["4,5": "a", "5,4": "b"], cell: Cell(row: 4, col: 4)) == [])
    }

    @Test("offers both when hemmed in on both sides")
    func offersBothWhenHemmedInOnBothSides() {
        #expect(impliedDirections(board: ["4,3": "a", "3,4": "b"], cell: Cell(row: 4, col: 4)) == [
            .across,
            .down,
        ])
    }
}

@Suite("Placement: cursorCell") struct PlacementCursorCell {
    @Test("starts on the chosen cell when nothing is staged")
    func startsOnTheChosenCellWhenNothingIsStaged() {
        #expect(cursorCell(
            board: [:], bounds: Bounds(size: 10),
            anchor: Cell(row: 2, col: 2), dir: .across, picks: []
        ) == Cell(row: 2, col: 2))
    }

    @Test("walks ahead of the letters already staged")
    func walksAheadOfTheLettersAlreadyStaged() {
        #expect(cursorCell(
            board: [:], bounds: Bounds(size: 10),
            anchor: Cell(row: 2, col: 2), dir: .across, picks: picksFrom("ca")
        ) == Cell(row: 2, col: 4))
    }

    @Test("steps over a word already on the board")
    func stepsOverAWordAlreadyOnTheBoard() {
        // DOG sits at 2,3-2,5; one letter staged at 2,2 puts the focus past it.
        let board: TileMap = ["2,3": "d", "2,4": "o", "2,5": "g"]
        #expect(cursorCell(
            board: board, bounds: Bounds(size: 10),
            anchor: Cell(row: 2, col: 2), dir: .across, picks: picksFrom("a")
        ) == Cell(row: 2, col: 6))
    }

    @Test("starts past a letter when building on from it")
    func startsPastALetterWhenBuildingOnFromIt() {
        #expect(cursorCell(
            board: ["2,2": "a"], bounds: Bounds(size: 10),
            anchor: Cell(row: 2, col: 2), dir: .across, picks: []
        ) == Cell(row: 2, col: 3))
    }

    @Test("comes back null once the word runs off the grid")
    func comesBackNullOnceTheWordRunsOffTheGrid() {
        #expect(cursorCell(
            board: [:], bounds: Bounds(size: 4),
            anchor: Cell(row: 0, col: 0), dir: .across, picks: picksFrom("abcd")
        ) == nil)
    }

    @Test("counts a gap as taking a square, covered or not")
    func countsAGapAsTakingASquareCoveredOrNot() {
        // S, gap, R from 2,2 reaches 2,5 next whether or not 2,3 holds a letter.
        #expect(cursorCell(
            board: [:], bounds: Bounds(size: 10),
            anchor: Cell(row: 2, col: 2), dir: .across, picks: picksWithGaps("s.r")
        ) == Cell(row: 2, col: 5))
        #expect(cursorCell(
            board: ["2,3": "o"], bounds: Bounds(size: 10),
            anchor: Cell(row: 2, col: 2), dir: .across, picks: picksWithGaps("s.r")
        ) == Cell(row: 2, col: 5))
    }
}

@Suite("Placement: startableDirections") struct PlacementStartableDirections {
    @Test("offers both ways from an empty cell")
    func offersBothWaysFromAnEmptyCell() {
        #expect(startableDirections(
            board: [:], bounds: Bounds(size: 10), cell: Cell(row: 4, col: 4)
        ) == [.across, .down])
    }

    @Test("still offers both in the far corner, where only one letter fits")
    func stillOffersBothInTheFarCornerWhereOnlyOneLetterFits() {
        // Overflow is reported when the word is actually planned, not here.
        #expect(startableDirections(
            board: [:], bounds: Bounds(size: 10), cell: Cell(row: 9, col: 9)
        ) == [.across, .down])
    }

    @Test("offers only the ways a placed letter has room to grow")
    func offersOnlyTheWaysAPlacedLetterHasRoomToGrow() {
        // A letter with its right-hand neighbour taken can only carry on downwards.
        #expect(startableDirections(
            board: ["4,4": "a", "4,5": "b"], bounds: Bounds(size: 10), cell: Cell(row: 4, col: 4)
        ) == [.down])
        #expect(startableDirections(
            board: ["4,4": "a", "5,4": "b"], bounds: Bounds(size: 10), cell: Cell(row: 4, col: 4)
        ) == [.across])
    }

    @Test("offers nothing from a letter walled in both ways")
    func offersNothingFromALetterWalledInBothWays() {
        let board: TileMap = ["4,4": "a", "4,5": "b", "5,4": "c"]
        #expect(startableDirections(
            board: board, bounds: Bounds(size: 10), cell: Cell(row: 4, col: 4)
        ) == [])
    }

    @Test("treats the edge of the grid as blocking for a placed letter")
    func treatsTheEdgeOfTheGridAsBlockingForAPlacedLetter() {
        let board: TileMap = ["9,9": "a"]
        #expect(startableDirections(
            board: board, bounds: Bounds(size: 10), cell: Cell(row: 9, col: 9)
        ) == [])
    }
}

@Suite("Placement: planPlacement") struct PlacementPlanPlacement {
    @Test("lays letters out across from the anchor")
    func laysLettersOutAcrossFromTheAnchor() {
        let plan = planPlacement(
            board: [:], bounds: Bounds(size: 10),
            anchor: Cell(row: 2, col: 3), dir: .across, picks: picksFrom("cat")
        )
        #expect(plan.complete == true)
        #expect(plan.steps == [
            PlacementStep(key: "2,3", letter: "c", rackIndex: 0),
            PlacementStep(key: "2,4", letter: "a", rackIndex: 1),
            PlacementStep(key: "2,5", letter: "t", rackIndex: 2),
        ])
    }

    @Test("lays letters out down from the anchor")
    func laysLettersOutDownFromTheAnchor() {
        let plan = planPlacement(
            board: [:], bounds: Bounds(size: 10),
            anchor: Cell(row: 2, col: 3), dir: .down, picks: picksFrom("cat")
        )
        #expect(plan.steps.map(\.key) == ["2,3", "3,3", "4,3"])
    }

    @Test("flows over tiles already on the board without spending a pick")
    func flowsOverTilesAlreadyOnTheBoardWithoutSpendingAPick() {
        let board: TileMap = ["0,1": "a"]
        let plan = planPlacement(
            board: board, bounds: Bounds(size: 10),
            anchor: Cell(row: 0, col: 0), dir: .across, picks: picksFrom("ct")
        )
        #expect(plan.complete == true)
        #expect(plan.steps == [
            PlacementStep(key: "0,0", letter: "c", rackIndex: 0),
            PlacementStep(key: "0,2", letter: "t", rackIndex: 1),
        ])
    }

    @Test("reports incomplete when the word runs off the grid")
    func reportsIncompleteWhenTheWordRunsOffTheGrid() {
        let plan = planPlacement(
            board: [:], bounds: Bounds(size: 5),
            anchor: Cell(row: 0, col: 3), dir: .across, picks: picksFrom("cat")
        )
        #expect(plan.complete == false)
        #expect(plan.steps.map(\.key) == ["0,3", "0,4"])
    }

    @Test("returns an empty plan for no picks")
    func returnsAnEmptyPlanForNoPicks() {
        let plan = planPlacement(
            board: [:], bounds: Bounds(size: 10),
            anchor: Cell(row: 0, col: 0), dir: .across, picks: []
        )
        #expect(plan.steps == [])
        #expect(plan.complete == true)
    }
}

@Suite("Placement: planWordCells") struct PlacementPlanWordCells {
    // CAT sitting across at row 0, cols 0-2.
    let cat: TileMap = ["0,0": "c", "0,1": "a", "0,2": "t"]
    let own: [CellKey] = ["0,0", "0,1", "0,2"]

    @Test("moves a word to a clear stretch of board")
    func movesAWordToAClearStretchOfBoard() {
        #expect(planWordCells(
            board: cat, bounds: Bounds(size: 10), length: 3, own: own,
            dir: .across, start: Cell(row: 4, col: 5)
        ) == ["4,5", "4,6", "4,7"])
    }

    @Test("rotates a word about its first letter")
    func rotatesAWordAboutItsFirstLetter() {
        #expect(planWordCells(
            board: cat, bounds: Bounds(size: 10), length: 3, own: own,
            dir: .down, start: Cell(row: 0, col: 0)
        ) == ["0,0", "1,0", "2,0"])
    }

    @Test("treats the cells the word is vacating as free")
    func treatsTheCellsTheWordIsVacatingAsFree() {
        // Shifting CAT one to the right overlaps its own A and T.
        #expect(planWordCells(
            board: cat, bounds: Bounds(size: 10), length: 3, own: own,
            dir: .across, start: Cell(row: 0, col: 1)
        ) == ["0,1", "0,2", "0,3"])
    }

    @Test("refuses to land on another word")
    func refusesToLandOnAnotherWord() {
        var board = cat
        board["2,0"] = "x"
        #expect(planWordCells(
            board: board, bounds: Bounds(size: 10), length: 3, own: own,
            dir: .down, start: Cell(row: 0, col: 0)
        ) == nil)
    }

    @Test("refuses to run off the grid")
    func refusesToRunOffTheGrid() {
        #expect(planWordCells(
            board: cat, bounds: Bounds(size: 10), length: 3, own: own,
            dir: .across, start: Cell(row: 0, col: 8)
        ) == nil)
        #expect(planWordCells(
            board: cat, bounds: Bounds(size: 10), length: 3, own: own,
            dir: .down, start: Cell(row: -1, col: 0)
        ) == nil)
    }
}

@Suite("Placement: findAvailable") struct PlacementFindAvailable {
    @Test("finds a matching pile tile")
    func findsAMatchingPileTile() {
        #expect(findAvailable(rack: ["a", "b", "c"], letter: "b", taken: []) == 1)
    }

    @Test("skips tiles already claimed by the current word")
    func skipsTilesAlreadyClaimedByTheCurrentWord() {
        #expect(findAvailable(rack: ["a", "b", "a"], letter: "a", taken: [0]) == 2)
    }

    @Test("is case-insensitive about the typed letter")
    func isCaseInsensitiveAboutTheTypedLetter() {
        #expect(findAvailable(rack: ["a", "b"], letter: "B", taken: []) == 1)
    }

    @Test("returns -1 when the letter is not available")
    func returnsMinusOneWhenTheLetterIsNotAvailable() {
        #expect(findAvailable(rack: ["a", "b"], letter: "z", taken: []) == -1)
        #expect(findAvailable(rack: ["a"], letter: "a", taken: [0]) == -1)
    }
}
