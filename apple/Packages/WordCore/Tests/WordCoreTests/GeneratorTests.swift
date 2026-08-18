import Testing
@testable import WordCore

/// Ported from `src/game/__tests__/generator.test.ts`.
///
/// These are statistical/structural tests over a non-seeded rng — the TS
/// suite runs on `Math.random`; here a `SystemRandomNumberGenerator` stands
/// in. Determinism is pinned separately by the fixture parity tests.

private let generationDict = Set(commonWords)

/// The Swift stand-in for `Math.random`: a fresh system generator captured
/// in a `() -> Double` closure, as the generator API expects.
private func makeRng() -> () -> Double {
    var g = SystemRandomNumberGenerator()
    return { Double.random(in: 0..<1, using: &g) }
}

private func sortedLetters(_ letters: [String]) -> String {
    letters.sorted().joined()
}

/// Mirrors the TS `^[a-z]{count}$` regex checks.
private func isLowercase(_ s: String, count: Int) -> Bool {
    s.count == count && s.allSatisfy { $0 >= "a" && $0 <= "z" }
}

@Suite("Generator: generatePuzzle") struct GeneratorGeneratePuzzle {
    @Test("deals exactly 20 letters backed by a known-valid connected solution")
    func dealsExactly20LettersBackedByAKnownValidConnectedSolution() throws {
        let rng = makeRng()
        for _ in 0..<50 {
            let puzzle = try generatePuzzle(wordPool: commonWords, tileCount: 20, rng: rng)

            #expect(puzzle.letters.count == 20)
            #expect(isLowercase(puzzle.letters.joined(), count: 20))

            // The crossword builder should essentially always succeed with a
            // 5,000-word pool — the fallback is a safety net, not the normal path.
            let solution = try #require(puzzle.solution)

            let validation = validateBoard(solution, dictionary: generationDict)
            #expect(validation.ok == true)
            #expect(validation.tileCount == 20)

            // The dealt letters are exactly the letters of the hidden solution.
            #expect(sortedLetters(puzzle.letters) == sortedLetters(solution.values))
        }
    }

    @Test("supports other tile counts")
    func supportsOtherTileCounts() throws {
        let rng = makeRng()
        for count in [12, 15, 21, 30] {
            let puzzle = try generatePuzzle(wordPool: commonWords, tileCount: count, rng: rng)
            #expect(puzzle.letters.count == count)
            if let solution = puzzle.solution {
                let validation = validateBoard(solution, dictionary: generationDict)
                #expect(validation.ok == true)
                #expect(validation.tileCount == count)
            }
        }
    }

    @Test("draws from multiple source words for variety")
    func drawsFromMultipleSourceWordsForVariety() throws {
        let rng = makeRng()
        let puzzle = try generatePuzzle(wordPool: commonWords, tileCount: 20, rng: rng)
        #expect(puzzle.sourceWords.count >= 3)
        for word in puzzle.sourceWords {
            #expect(generationDict.contains(word) == true)
        }
    }

    @Test("holds the solution inside maxSpan, for Puzzle mode boards")
    func holdsTheSolutionInsideMaxSpanForPuzzleModeBoards() throws {
        // 8 is Puzzle's tightest board; 20 tiles must still deal reliably.
        let rng = makeRng()
        for _ in 0..<50 {
            let puzzle = try generatePuzzle(
                wordPool: commonWords, tileCount: 20, rng: rng, maxSpan: 8
            )
            #expect(puzzle.letters.count == 20)
            let solution = try #require(puzzle.solution)

            let validation = validateBoard(solution, dictionary: generationDict)
            #expect(validation.ok == true)

            var minRow = Int.max
            var maxRow = Int.min
            var minCol = Int.max
            var maxCol = Int.min
            for key in solution.keys {
                let cell = parseKey(key)
                minRow = min(minRow, cell.row)
                maxRow = max(maxRow, cell.row)
                minCol = min(minCol, cell.col)
                maxCol = max(maxCol, cell.col)
            }
            #expect(maxRow - minRow + 1 <= 8)
            #expect(maxCol - minCol + 1 <= 8)
        }
    }
}

@Suite("Generator: extendPuzzle") struct GeneratorExtendPuzzle {
    /// Centre a puzzle's solution on the real board, the way level one does.
    func openingBoard(_ rng: () -> Double) throws -> TileMap {
        let puzzle = try generatePuzzle(wordPool: commonWords, tileCount: 20, rng: rng)
        var board = TileMap()
        let offset = 6
        for (key, letter) in try #require(puzzle.solution) {
            let cell = parseKey(key)
            board[keyOf(cell.row + offset, cell.col + offset)] = letter
        }
        return board
    }

    @Test("adds exactly the letters asked for, leaving the board alone")
    func addsExactlyTheLettersAskedForLeavingTheBoardAlone() throws {
        let rng = makeRng()
        for _ in 0..<25 {
            let board = try openingBoard(rng)
            let before = board
            let dealt = try extendPuzzle(
                board: board, bounds: Bounds(size: BOARD_SIZE),
                wordPool: commonWords, tileCount: 10, rng: rng
            )

            #expect(dealt.letters.count == 10)
            #expect(isLowercase(dealt.letters.joined(), count: 10))
            // The generator must not mutate the board it was handed. (TileMap
            // is a value type, so the copy taken before the call must match.)
            #expect(board == before)
        }
    }

    /// The guarantee the levels rest on: the new letters can all be played onto
    /// the board *as it already stands*, keeping every existing tile in place.
    @Test("grows an arrangement that plays every new letter onto the board as built")
    func growsAnArrangementThatPlaysEveryNewLetterOntoTheBoardAsBuilt() throws {
        let rng = makeRng()
        for _ in 0..<25 {
            let board = try openingBoard(rng)
            let dealt = try extendPuzzle(
                board: board, bounds: Bounds(size: BOARD_SIZE),
                wordPool: commonWords, tileCount: 10, rng: rng
            )
            let solved = try #require(dealt.solution)

            // Every tile already down is untouched, and in the same place.
            for (key, letter) in board {
                #expect(solved[key] == letter)
            }
            // It adds exactly the 10 dealt letters and nothing else.
            let added = solved.keys.filter { !board.contains($0) }
            #expect(added.count == 10)
            #expect(sortedLetters(added.map { solved[$0]! }) == sortedLetters(dealt.letters))
            // It stays on the board...
            for key in added {
                let cell = parseKey(key)
                #expect(cell.row >= 0)
                #expect(cell.col >= 0)
                #expect(cell.row < BOARD_SIZE)
                #expect(cell.col < BOARD_SIZE)
            }
            // ...and it's a fully legal crossword, so the arrangement really is playable.
            let validation = validateBoard(solved, dictionary: generationDict)
            #expect(validation.ok == true)
            #expect(validation.tileCount == board.count + 10)
        }
    }

    @Test("carries a board through four more deals, 10 tiles at a time")
    func carriesABoardThroughFourMoreDeals10TilesAtATime() throws {
        let rng = makeRng()
        for _ in 0..<10 {
            var board = try openingBoard(rng)
            for _ in 2...5 {
                let dealt = try extendPuzzle(
                    board: board, bounds: Bounds(size: BOARD_SIZE),
                    wordPool: commonWords, tileCount: 10, rng: rng
                )
                #expect(dealt.letters.count == 10)
                // Play the arrangement and carry on from there, as a player would.
                board = try #require(dealt.solution)
                #expect(validateBoard(board, dictionary: generationDict).ok == true)
            }
            // 20 up front plus 10 a level for four more levels.
            #expect(board.count == 60)
        }
    }

    @Test("deals a standalone batch when there is nothing to grow from")
    func dealsAStandaloneBatchWhenThereIsNothingToGrowFrom() throws {
        let rng = makeRng()
        let dealt = try extendPuzzle(
            board: TileMap(), bounds: Bounds(size: BOARD_SIZE),
            wordPool: commonWords, tileCount: 10, rng: rng
        )
        #expect(dealt.letters.count == 10)
        for word in dealt.words {
            #expect(generationDict.contains(word) == true)
        }
    }

    /// Puzzle Flow hands back exactly what each word spent, so it asks for tiny
    /// batches — a one-letter play asks for one, which no word could ever bring.
    @Test("deals any batch down to a single tile")
    func dealsAnyBatchDownToASingleTile() throws {
        let rng = makeRng()
        for count in [1, 2, 3, 4, 5] {
            for _ in 0..<10 {
                let board = try openingBoard(rng)
                let dealt = try extendPuzzle(
                    board: board, bounds: Bounds(size: BOARD_SIZE),
                    wordPool: commonWords, tileCount: count, rng: rng
                )
                #expect(dealt.letters.count == count)
                #expect(isLowercase(dealt.letters.joined(), count: count))
            }
        }
    }
}
