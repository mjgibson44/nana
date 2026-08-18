import Testing
@testable import WordCore

/// Ported from `src/game/__tests__/tutorial.test.ts`.

/// Play a step's scripted placement, the way commit does, and hand back the
/// board it leaves — the whole point being that the word lands.
private func playStep(_ board: TileMap, _ stepIndex: Int, _ rack: [String]) throws -> TileMap {
    let step = tutorialScript[stepIndex]
    let bounds = boardBounds(board)
    let played = try #require(scriptedPlacement(board: board, bounds: bounds, step: step, rack: rack))
    let plan = planPlacement(
        board: board, bounds: bounds, anchor: played.anchor, dir: played.dir, picks: played.picks
    )
    #expect(plan.complete == true)
    #expect(plan.steps.count > 0)
    var next = board
    for placed in plan.steps { next[placed.key] = placed.letter }
    return next
}

@Suite("Tutorial: TUTORIAL_SCRIPT") struct TutorialScriptTests {
    @Test("deals each word one letter short of the last, so every word crosses")
    func dealsEachWordOneLetterShortOfTheLastSoEveryWordCrosses() {
        #expect(tutorialScript.map(\.word) == ["solar", "orbit", "pole"])
        #expect(tutorialScript[0].tiles.joined() == "solar")
        #expect(tutorialScript[1].tiles.joined() == "obit")
        #expect(tutorialScript[2].tiles.joined() == "ple")
    }

    @Test("opens with the word spelled out in reading order")
    func opensWithTheWordSpelledOutInReadingOrder() {
        #expect(tutorialScript[0].tiles.joined() == tutorialScript[0].word)
    }

    @Test("asks for a gap tile only on the last step")
    func asksForAGapTileOnlyOnTheLastStep() {
        #expect(tutorialScript.map(\.needsGap) == [false, false, true])
    }

    @Test("has something to say the moment each word lands")
    func hasSomethingToSayTheMomentEachWordLands() {
        for step in tutorialScript {
            #expect(step.done.contains(step.word.uppercased()))
        }
    }

    @Test("counts its own steps")
    func countsItsOwnSteps() {
        #expect(TUTORIAL_STEPS == 3)
    }
}

@Suite("Tutorial: scriptedPlacement") struct TutorialScriptedPlacementTests {
    @Test("lays the opening word out across the middle of an empty board")
    func laysTheOpeningWordOutAcrossTheMiddleOfAnEmptyBoard() throws {
        let board = try playStep([:], 0, tutorialScript[0].tiles)
        let runs = extractRuns(board)
        #expect(runs.map(\.word) == ["solar"])
        let first = try #require(runs.first)
        #expect(first.direction == .across)
        // Comfortably inside the starting board, not against its corner.
        let cells = first.cells.map { parseKey($0) }
        for cell in cells {
            #expect(cell.row > 4)
            #expect(cell.col > 4)
        }
    }

    @Test("walks the whole script through, each word crossing the one before")
    func walksTheWholeScriptThroughEachWordCrossingTheOneBefore() throws {
        var board = try playStep([:], 0, tutorialScript[0].tiles)
        board = try playStep(board, 1, tutorialScript[1].tiles)
        board = try playStep(board, 2, tutorialScript[2].tiles)

        let words = extractRuns(board).map(\.word).sorted()
        #expect(words == ["orbit", "pole", "solar"])
        // Twelve tiles for three words totalling fourteen letters: the two
        // crossings are real, not three words laid out side by side.
        #expect(board.keys.count == 12)
    }

    @Test("claims the letter it borrows with a gap when the step wants one")
    func claimsTheLetterItBorrowsWithAGapWhenTheStepWantsOne() throws {
        var board = try playStep([:], 0, tutorialScript[0].tiles)
        board = try playStep(board, 1, tutorialScript[1].tiles)
        let played = try #require(scriptedPlacement(
            board: board, bounds: boardBounds(board), step: tutorialScript[2], rack: ["p", "l", "e"]
        ))
        #expect(played.picks.map(\.rackIndex).contains(GAP))
        #expect(played.picks.filter { $0.letter == nil }.count == 1)
    }

    @Test("finishes a word the player started rather than starting a second one")
    func finishesAWordThePlayerStartedRatherThanStartingASecondOne() throws {
        // Three of SOLAR's tiles already down, two left in the pile.
        let board: TileMap = ["10,10": "s", "10,11": "o", "10,12": "l"]
        let played = try #require(scriptedPlacement(
            board: board, bounds: boardBounds(board), step: tutorialScript[0], rack: ["a", "r"]
        ))
        #expect(played.anchor == Cell(row: 10, col: 10))
        #expect(played.dir == .across)
        #expect(played.picks.map(\.letter) == ["a", "r"])
    }

    @Test("gives up rather than guess when the word has nowhere left to go")
    func givesUpRatherThanGuessWhenTheWordHasNowhereLeftToGo() {
        // ORBIT's R is walled in on all four sides, so nothing can cross it.
        let board: TileMap = [
            "10,10": "r",
            "9,10": "x",
            "11,10": "x",
            "10,9": "x",
            "10,11": "x",
        ]
        let played = scriptedPlacement(
            board: board, bounds: boardBounds(board), step: tutorialScript[1],
            rack: tutorialScript[1].tiles
        )
        #expect(played == nil)
    }

    @Test("will not bury the word inside a longer run")
    func willNotBuryTheWordInsideALongerRun() throws {
        // SOLAR would read as SOLARS, so this R is no use for ORBIT.
        let board: TileMap = ["10,10": "r", "10,11": "s"]
        let bounds = boardBounds(board)
        let played = try #require(scriptedPlacement(
            board: board, bounds: bounds, step: tutorialScript[1], rack: tutorialScript[1].tiles
        ))
        // Down through the R is still fine — it's the across reading that's spoiled.
        #expect(played.dir == .down)
        #expect(played.anchor == Cell(row: 9, col: 10))
        #expect(keyOf(played.anchor.row, played.anchor.col) == "9,10")
    }
}
