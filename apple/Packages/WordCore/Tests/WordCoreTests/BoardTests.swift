import Testing
@testable import WordCore

/// Ported from `src/game/__tests__/board.test.ts`.

/// Build a board from ascii rows; '.' means empty.
private func boardFrom(_ rows: [String]) -> TileMap {
    var tiles = TileMap()
    for (r, row) in rows.enumerated() {
        for (c, ch) in row.enumerated() where ch != "." {
            tiles[keyOf(r, c)] = String(ch)
        }
    }
    return tiles
}

@Suite("Board: runsTouching") struct BoardRunsTouching {
    /// The whole contract: it is `extractRuns` filtered to the cells asked
    /// about, only without reading the rest of the board. Checked over a
    /// pile of seeded random boards, because the interesting cases (a cell
    /// mid-run, three cells of one word, a lone letter, an empty cell) all
    /// turn up in a few hundred of them.
    @Test("matches extractRuns filtered to the cells asked about")
    func runsTouchingMatchExtractRuns() {
        let rng = seededRng("runs-touching")
        for _ in 0..<200 {
            var tiles = TileMap()
            for row in 0..<6 {
                for col in 0..<6 where rng() < 0.5 {
                    tiles[keyOf(row, col)] = String("abcdefgh"[
                        String.Index(utf16Offset: Int(rng() * 8), in: "abcdefgh")])
                }
            }
            // Ask about a handful of cells, occupied and empty alike.
            let asked = (0..<4).map { _ in keyOf(Int(rng() * 6), Int(rng() * 6)) }
            let want = extractRuns(tiles)
                .filter { run in run.cells.contains { asked.contains($0) } }
            let got = runsTouching(asked, in: tiles)
            #expect(
                Set(want.map { "\($0.word)/\($0.direction)/\($0.cells)" })
                    == Set(got.map { "\($0.word)/\($0.direction)/\($0.cells)" }))
        }
    }

    @Test("a word touched at three of its letters comes back once")
    func emitsEachRunOnce() {
        let tiles = boardFrom(["cat"])
        let runs = runsTouching([keyOf(0, 0), keyOf(0, 1), keyOf(0, 2)], in: tiles)
        #expect(runs.map(\.word) == ["cat"])
    }

    @Test("an empty cell touches nothing")
    func emptyCellsTouchNothing() {
        #expect(runsTouching([keyOf(9, 9)], in: boardFrom(["cat"])).isEmpty)
    }
}

@Suite("Board: extractRuns") struct BoardExtractRuns {
    @Test("finds across and down words")
    func findsAcrossAndDownWords() {
        // c a t
        // . t .
        // . e .
        let tiles = boardFrom(["cat", ".t.", ".e."])
        let runs = extractRuns(tiles)
        let words = runs.map(\.word).sorted()
        #expect(words == ["ate", "cat"])
        #expect(runs.first { $0.word == "cat" }?.direction == .across)
        #expect(runs.first { $0.word == "ate" }?.direction == .down)
    }

    @Test("ignores single letters")
    func ignoresSingleLetters() {
        let tiles = boardFrom(["c.t"])
        #expect(extractRuns(tiles) == [])
    }

    @Test("splits runs across gaps")
    func splitsRunsAcrossGaps() {
        let tiles = boardFrom(["at.at"])
        let runs = extractRuns(tiles)
        #expect(runs.map(\.word) == ["at", "at"])
    }
}

@Suite("Board: isConnected") struct BoardIsConnected {
    @Test("accepts one connected group")
    func acceptsOneConnectedGroup() {
        #expect(isConnected(boardFrom(["cat", ".t.", ".e."])) == true)
    }

    @Test("rejects two separate groups")
    func rejectsTwoSeparateGroups() {
        #expect(isConnected(boardFrom(["cat", "...", "dog"])) == false)
    }

    @Test("is vacuously true for empty and single-tile boards")
    func isVacuouslyTrueForEmptyAndSingleTileBoards() {
        #expect(isConnected([:]) == true)
        #expect(isConnected(boardFrom(["a"])) == true)
    }
}

@Suite("Board: validateBoard") struct BoardValidateBoard {
    let dict: Set<String> = ["cat", "ate", "dog", "at"]

    @Test("accepts a fully valid crossword")
    func acceptsAFullyValidCrossword() {
        let v = validateBoard(boardFrom(["cat", ".t.", ".e."]), dictionary: dict)
        #expect(v.ok == true)
        #expect(v.invalidRuns == [])
        #expect(v.isolatedTiles == [])
        #expect(v.connected == true)
    }

    @Test("flags words missing from the dictionary")
    func flagsWordsMissingFromTheDictionary() {
        // "ax" (down) is not in the test dictionary.
        let v = validateBoard(boardFrom(["cat", ".x."]), dictionary: dict)
        #expect(v.ok == false)
        #expect(v.invalidRuns.map(\.word) == ["ax"])
    }

    @Test("flags isolated tiles")
    func flagsIsolatedTiles() {
        let v = validateBoard(boardFrom(["cat", "...", "x.."]), dictionary: dict)
        #expect(v.isolatedTiles == [keyOf(2, 0)])
        #expect(v.connected == false)
        #expect(v.ok == false)
    }

    @Test("flags disconnected groups even when all words are valid")
    func flagsDisconnectedGroupsEvenWhenAllWordsAreValid() {
        let v = validateBoard(boardFrom(["cat", "...", "dog"]), dictionary: dict)
        #expect(v.invalidRuns == [])
        #expect(v.connected == false)
        #expect(v.ok == false)
    }

    @Test("is not ok for an empty board")
    func isNotOkForAnEmptyBoard() {
        let v = validateBoard([:], dictionary: dict)
        #expect(v.ok == false)
        #expect(v.tileCount == 0)
    }

    @Test("rejects two-letter runs even when the dictionary has them")
    func rejectsTwoLetterRunsEvenWhenTheDictionaryHasThem() {
        // AT is in the test dictionary, but two-letter words are banned outright.
        let v = validateBoard(boardFrom(["at"]), dictionary: dict)
        #expect(dict.contains("at") == true)
        #expect(v.invalidRuns.map(\.word) == ["at"])
        #expect(v.ok == false)
    }

    @Test("names the tiles adrift from the main body of the board")
    func namesTheTilesAdriftFromTheMainBodyOfTheBoard() {
        // CAT is the bigger group, so the far-off DOG is what's adrift.
        let v = validateBoard(boardFrom(["cat", "...", "dog"]), dictionary: dict)
        #expect(v.disconnectedTiles.sorted() == [keyOf(2, 0), keyOf(2, 1), keyOf(2, 2)])
    }

    @Test("leaves nothing adrift when the board is one group")
    func leavesNothingAdriftWhenTheBoardIsOneGroup() {
        let v = validateBoard(boardFrom(["cat", ".t.", ".e."]), dictionary: dict)
        #expect(v.disconnectedTiles == [])
    }
}

@Suite("Board: components") struct BoardComponents {
    @Test("returns one group for a joined-up board")
    func returnsOneGroupForAJoinedUpBoard() {
        #expect(components(boardFrom(["cat", ".t.", ".e."])).count == 1)
    }

    @Test("orders groups largest first, so the main board comes out on top")
    func ordersGroupsLargestFirstSoTheMainBoardComesOutOnTop() {
        // A four-tile word and a lone tile, far apart.
        let groups = components(boardFrom(["cats", "....", "x..."]))
        #expect(groups.map(\.count) == [4, 1])
        #expect(groups[1] == [keyOf(2, 0)])
    }

    @Test("has no groups at all on an empty board")
    func hasNoGroupsAtAllOnAnEmptyBoard() {
        #expect(components([:]) == [])
    }
}
