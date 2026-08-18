import Testing
@testable import WordCore

/// Golden-vector parity with the canonical TypeScript implementation.
/// These fixtures were produced by running the web game's actual code
/// (tools/gen-fixtures.ts); every test here failing means the Swift port
/// would deal different letters than a web client for the same seed.

// MARK: rng

private struct RngCase: Decodable {
    let seed: String
    let first: [Double] // raw u32 values, exact in a Double
}

@Suite("rng parity") struct RngParity {
    @Test func matchesJsVectors() {
        let cases: [RngCase] = loadFixture("rng")
        #expect(cases.count >= 8)
        for c in cases {
            let rng = seededRng(c.seed)
            for (i, expected) in c.first.enumerated() {
                let raw = rng() * 4294967296
                #expect(raw == expected, "seed \(c.seed.debugDescription) draw \(i)")
                if raw != expected { return } // one mismatch says it all
            }
        }
    }

    @Test func rangeIsZeroToOne() {
        let rng = seededRng("range-check")
        for _ in 0..<1000 {
            let v = rng()
            #expect(v >= 0 && v < 1)
        }
    }
}

// MARK: tile stream

private struct StreamCase: Decodable {
    let seed: String
    let pattern: [Int]
    let batches: [[String]]
}

@Suite("tile stream parity") struct StreamParity {
    @Test func matchesJsSequences() {
        let cases: [StreamCase] = loadFixture("stream")
        #expect(cases.count >= 12)
        for c in cases {
            let stream = TileStream(seed: c.seed)
            for (i, count) in c.pattern.enumerated() {
                let batch = stream.next(count)
                #expect(batch == c.batches[i], "seed \(c.seed) pattern \(c.pattern) batch \(i)")
                if batch != c.batches[i] { return }
            }
        }
    }
}

// MARK: generator

private struct PuzzleCase: Decodable {
    let seed: String
    let tileCount: Int
    let maxSpan: Int?
    let letters: [String]
    let solutionKeys: [String]?
    let solutionValues: [String]?
    let sourceWords: [String]
}

@Suite("generator parity") struct GeneratorParity {
    @Test func matchesJsPuzzles() throws {
        let cases: [PuzzleCase] = loadFixture("generator")
        #expect(cases.count >= 15)
        for c in cases {
            let rng = seededRng(c.seed)
            let puzzle = try generatePuzzle(
                wordPool: commonWords, tileCount: c.tileCount, rng: rng, maxSpan: c.maxSpan
            )
            #expect(puzzle.letters == c.letters, "letters for \(c.seed)")
            #expect(puzzle.sourceWords == c.sourceWords, "words for \(c.seed)")
            if let keys = c.solutionKeys, let values = c.solutionValues {
                let solution = try #require(puzzle.solution)
                #expect(solution.keys == keys, "solution key order for \(c.seed)")
                #expect(solution.values == values, "solution values for \(c.seed)")
            } else {
                #expect(puzzle.solution == nil)
            }
            if puzzle.letters != c.letters { return }
        }
    }
}

// MARK: extend chains

private struct ExtendStep: Decodable {
    let letters: [String]
    let words: [String]
}

private struct ExtendCase: Decodable {
    let seed: String
    let openingLetters: [String]
    let chain: [ExtendStep]
    let finalBoardSorted: [[String]]
}

@Suite("extend parity") struct ExtendParity {
    @Test func matchesJsChains() throws {
        let cases: [ExtendCase] = loadFixture("extend")
        for c in cases {
            let rng = seededRng(c.seed)
            let opening = try generatePuzzle(wordPool: commonWords, tileCount: 20, rng: rng)
            #expect(opening.letters == c.openingLetters, "opening for \(c.seed)")
            var hidden = opening.solution ?? TileMap()
            for (i, step) in c.chain.enumerated() {
                let grown = try extendPuzzle(
                    board: hidden, bounds: boardBounds(hidden),
                    wordPool: commonWords, tileCount: 5, rng: rng
                )
                if let solution = grown.solution { hidden = solution }
                #expect(grown.letters == step.letters, "chain \(i) letters for \(c.seed)")
                #expect(grown.words == step.words, "chain \(i) words for \(c.seed)")
            }
            let finalSorted = hidden.entries
                .map { [$0.key, $0.value] }
                .sorted { $0[0] < $1[0] }
            #expect(finalSorted == c.finalBoardSorted, "final board for \(c.seed)")
        }
    }
}
