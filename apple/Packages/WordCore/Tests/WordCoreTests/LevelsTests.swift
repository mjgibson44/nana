import Testing
@testable import WordCore

/// Ported from `src/game/__tests__/levels.test.ts`.

@Suite("Levels: boardBounds") struct LevelsBoardBounds {
    let START = Bounds(
        minRow: 0,
        minCol: 0,
        maxRow: BOARD_SIZE - 1,
        maxCol: BOARD_SIZE - 1
    )

    @Test("is the starting board while it is empty")
    func isTheStartingBoardWhileItIsEmpty() {
        #expect(boardBounds([:]) == START)
    }

    @Test("stays put while tiles keep their distance from every edge")
    func staysPutWhileTilesKeepTheirDistanceFromEveryEdge() {
        #expect(boardBounds(["16,16": "a"]) == START)
    }

    @Test("grows past an edge a tile has come close to")
    func growsPastAnEdgeATileHasComeCloseTo() {
        // A tile on the top edge pushes the board GROW_MARGIN rows above it.
        var expected = START
        expected.minRow = -GROW_MARGIN
        #expect(boardBounds(["0,16": "a"]) == expected)
    }

    @Test("keeps growing as tiles follow the edge outward")
    func keepsGrowingAsTilesFollowTheEdgeOutward() {
        // Play onto the new rows and the board recedes again.
        var expected = START
        expected.minRow = -5 - GROW_MARGIN
        #expect(boardBounds(["-5,16": "a"]) == expected)
    }

    @Test("grows in every direction at once")
    func growsInEveryDirectionAtOnce() {
        let board: TileMap = ["0,0": "a", keyOf(BOARD_SIZE - 1, BOARD_SIZE - 1): "b"]
        #expect(boardBounds(board) == Bounds(
            minRow: -GROW_MARGIN,
            minCol: -GROW_MARGIN,
            maxRow: BOARD_SIZE - 1 + GROW_MARGIN,
            maxCol: BOARD_SIZE - 1 + GROW_MARGIN
        ))
    }

    @Test("always leaves at least the margin of open board beyond every tile")
    func alwaysLeavesAtLeastTheMarginOfOpenBoardBeyondEveryTile() {
        let board: TileMap = ["2,30": "a", "31,4": "b"]
        let bounds = boardBounds(board)
        #expect(bounds.minRow <= 2 - GROW_MARGIN)
        #expect(bounds.maxCol >= 30 + GROW_MARGIN)
        #expect(bounds.maxRow >= 31 + GROW_MARGIN)
        #expect(bounds.minCol <= 4 - GROW_MARGIN)
    }
}

@Suite("Levels: wordScore") struct LevelsWordScore {
    @Test("pays nothing for a lone tile")
    func paysNothingForALoneTile() {
        #expect(wordScore("a") == 0)
    }

    @Test("rewards length faster than linearly")
    func rewardsLengthFasterThanLinearly() {
        #expect(wordScore("cat") == 3)
        #expect(wordScore("cats") == 6)
        #expect(wordScore("elephant") == 28)
    }

    @Test("makes one long word beat the same letters split in two")
    func makesOneLongWordBeatTheSameLettersSplitInTwo() {
        #expect(wordScore("planets") > wordScore("plan") + wordScore("ets"))
    }
}

@Suite("Levels: scoreBoard") struct LevelsScoreBoard {
    let DICT: Set<String> = ["cat", "car", "arc", "at", "as", "ta"]

    /// Lay a word across (row, col) onwards.
    func across(_ tiles: TileMap, _ row: Int, _ col: Int, _ word: String) -> TileMap {
        var tiles = tiles
        for (i, letter) in word.enumerated() {
            tiles[keyOf(row, col + i)] = String(letter)
        }
        return tiles
    }

    func score(_ tiles: TileMap, _ tilesLeft: Int) -> BoardScore {
        scoreBoard(validateBoard(tiles, dictionary: DICT), tilesLeft: tilesLeft)
    }

    @Test("scores nothing for an empty board")
    func scoresNothingForAnEmptyBoard() {
        let result = score([:], 20)
        #expect(result.words == 0)
        #expect(result.bonus == 0)
        #expect(result.total == 0)
        #expect(result.bonusEarned == false)
    }

    @Test("pays out only for real words")
    func paysOutOnlyForRealWords() {
        let tiles = across([:], 0, 0, "cat")
        #expect(score(tiles, 5).words == 3)
        // XYZ is not in the dictionary, so it adds nothing.
        #expect(score(across(tiles, 5, 0, "xyz"), 5).words == 3)
    }

    @Test("counts a crossing tile towards both of its words")
    func countsACrossingTileTowardsBothOfItsWords() {
        // CAT across, CAR down, sharing the C.
        var tiles = across([:], 0, 0, "cat")
        tiles[keyOf(1, 0)] = "a"
        tiles[keyOf(2, 0)] = "r"
        #expect(score(tiles, 5).words == wordScore("cat") + wordScore("car"))
    }

    @Test("adds the bonus once the pile is empty and the board is valid")
    func addsTheBonusOnceThePileIsEmptyAndTheBoardIsValid() {
        let tiles = across([:], 0, 0, "cat")
        let result = score(tiles, 0)
        #expect(result.bonusEarned == true)
        #expect(result.bonus == ALL_TILES_BONUS)
        #expect(result.total == 3 + ALL_TILES_BONUS)
    }

    @Test("withholds the bonus while tiles remain in the pile")
    func withholdsTheBonusWhileTilesRemainInThePile() {
        #expect(score(across([:], 0, 0, "cat"), 1).bonusEarned == false)
    }

    @Test("withholds the bonus when the emptied pile left an invalid board")
    func withholdsTheBonusWhenTheEmptiedPileLeftAnInvalidBoard() {
        // Pile empty, but ZZZ isn't a word.
        let tiles = across(across([:], 0, 0, "cat"), 5, 0, "zzz")
        let result = score(tiles, 0)
        #expect(result.bonusEarned == false)
        #expect(result.bonus == 0)
        #expect(result.words == 3)
    }

    @Test("withholds the bonus when the words are valid but not all connected")
    func withholdsTheBonusWhenTheWordsAreValidButNotAllConnected() {
        // Two legal words, far apart — the board isn't one group.
        let tiles = across(across([:], 0, 0, "cat"), 8, 8, "car")
        #expect(score(tiles, 0).bonusEarned == false)
    }
}
