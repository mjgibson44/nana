import Foundation
import Testing

@testable import WordCore

/// The Daily board has no TS counterpart to be a parity fixture for, so these
/// are the spec. The sweeps run the real generator over many seeds, because
/// the interesting claims here are claims about *every* day — that the puzzle
/// is always buildable, always reachable, and always the same for everyone.

private let sweepSeeds = (0..<120).map { "nana-daily-1f4a9c/daily/sweep-\($0)" }

@Suite("DailyBoard: construction")
struct DailyBoardConstruction {
    @Test("builds a board for every seed it's given")
    func buildsForEverySeed() throws {
        for seed in sweepSeeds {
            _ = try dailyBoard(seed: seed)
        }
    }

    @Test("is a pure function of the seed")
    func isDeterministic() throws {
        for seed in sweepSeeds.prefix(20) {
            let first = try dailyBoard(seed: seed)
            let second = try dailyBoard(seed: seed)
            #expect(first == second)
        }
    }

    @Test("different seeds give different boards")
    func differentSeedsDiffer() throws {
        let boards = try sweepSeeds.prefix(20).map { try dailyBoard(seed: $0) }
        let words = Set(boards.map(\.seedWord))
        // Not a claim that every day is unique — a repeated seed word is fine
        // and will happen — only that the seed is actually doing something.
        #expect(words.count > 10)
    }

    @Test("opens with the seed word on the board and nothing else")
    func opensWithTheSeedWord() throws {
        for seed in sweepSeeds {
            let day = try dailyBoard(seed: seed)
            #expect(day.board.count == day.seedWord.count)
            #expect(day.board.count == day.seedCells.count)
            #expect(Set(day.board.keys) == Set(day.seedCells))

            // The board reads as exactly one word, and it's the one named.
            let runs = extractRuns(day.board)
            #expect(runs.count == 1)
            #expect(runs.first?.word == day.seedWord)
            #expect(isConnected(day.board))
        }
    }

    @Test("the seed word is a real word of a usable length")
    func seedWordIsUsable() throws {
        let pool = Set(commonWords)
        for seed in sweepSeeds {
            let day = try dailyBoard(seed: seed)
            #expect(pool.contains(day.seedWord))
            #expect(DailyBoardRules.seedWordLengths.contains(day.seedWord.count))
        }
    }

    @Test("deals every tile the seed word didn't use")
    func dealsTheRest() throws {
        for seed in sweepSeeds {
            let day = try dailyBoard(seed: seed)
            #expect(day.letters.count + day.seedCells.count == DailyBoardRules.tileCount)
            #expect(day.letters.allSatisfy { $0.count == 1 })
            // Dealt into a fixed pile, so the hand has to fit it.
            #expect(day.letters.count <= DailyBoardRules.maxDeal)
        }
    }

    @Test("sits inside the board the game opens on")
    func sitsInsideTheOpeningBoard() throws {
        for seed in sweepSeeds {
            let day = try dailyBoard(seed: seed)
            for key in day.solution.keys {
                let cell = parseKey(key)
                #expect(cell.row >= 0 && cell.row < BOARD_SIZE)
                #expect(cell.col >= 0 && cell.col < BOARD_SIZE)
            }
        }
    }
}

@Suite("DailyBoard: the targets")
struct DailyBoardTargets {
    @Test("marks the right number of distinct empty cells")
    func marksDistinctEmptyCells() throws {
        for seed in sweepSeeds {
            let day = try dailyBoard(seed: seed)
            #expect(day.targets.count == DailyBoardRules.targets)
            #expect(Set(day.targets).count == DailyBoardRules.targets)
            // A target already covered at the start would be no target at all.
            #expect(day.targets.allSatisfy { !day.board.contains($0) })
        }
    }

    @Test("keeps the targets apart, and away from the opening word")
    func keepsTargetsApart() throws {
        for seed in sweepSeeds {
            let day = try dailyBoard(seed: seed)
            for (i, a) in day.targets.enumerated() {
                for b in day.targets[(i + 1)...] {
                    #expect(chebyshev(a, b) >= DailyBoardRules.minTargetGap)
                }
                let toSeed = day.seedCells.map { chebyshev(a, $0) }.min()!
                #expect(toSeed >= DailyBoardRules.minSeedGap)
            }
            // The first one is the far one — it's what makes the board span.
            let firstDistance = day.seedCells.map { chebyshev(day.targets[0], $0) }.min()!
            #expect(firstDistance >= DailyBoardRules.minFirstSeedGap)
        }
    }

    @Test("every target is reachable — the hidden crossword covers them all")
    func targetsAreReachable() throws {
        for seed in sweepSeeds {
            let day = try dailyBoard(seed: seed)
            for target in day.targets {
                #expect(day.solution.contains(target))
            }
        }
    }
}

@Suite("DailyBoard: par and the solvability guarantee")
struct DailyBoardPar {
    @Test("the hidden crossword is exactly the board plus the deal")
    func solutionIsBoardPlusDeal() throws {
        for seed in sweepSeeds {
            let day = try dailyBoard(seed: seed)
            #expect(day.solution.count == DailyBoardRules.tileCount)

            // The seed word sits in the solution exactly where it sits on the
            // board — so playing the deal into the rest of it is a legal
            // finish, which is what makes the day solvable by construction.
            for (key, letter) in day.board {
                #expect(day.solution[key] == letter)
            }

            let dealt = day.letters.sorted()
            let remaining = day.solution.keys
                .filter { !day.board.contains($0) }
                .map { day.solution[$0]! }
                .sorted()
            #expect(dealt == remaining)
        }
    }

    @Test("the hidden crossword is a legal, connected board of real words")
    func solutionIsLegal() throws {
        let pool = Set(commonWords)
        for seed in sweepSeeds {
            let day = try dailyBoard(seed: seed)
            #expect(isConnected(day.solution))
            for run in extractRuns(day.solution) {
                #expect(run.cells.count >= MIN_WORD_LENGTH)
                #expect(pool.contains(run.word))
            }
        }
    }

    @Test("par is the hidden crossword's own word count, and is beatable-shaped")
    func parIsTheSolutionsWordCount() throws {
        for seed in sweepSeeds {
            let day = try dailyBoard(seed: seed)
            #expect(day.par == extractRuns(day.solution).count)
            // Par counts the seed word, which is already down — so there is
            // always at least one word left for the player to find.
            #expect(day.par > 1)
        }
    }
}

@Suite("DailyBoard: progress and scoring")
struct DailyBoardScoring {
    @Test("the rings are a tier, complete only once every one is covered")
    func finishedOnlyWhenAllCovered() {
        let targets = [keyOf(1, 1), keyOf(5, 5), keyOf(9, 9)]
        var board = TileMap()
        board[keyOf(1, 1)] = "a"
        let partial = dailyProgress(board: board, targets: targets, validation: nil, tilesLeft: 4)
        #expect(partial.reached == 1)
        #expect(partial.covered == [true, false, false])
        #expect(!partial.ringsDone)

        board[keyOf(5, 5)] = "b"
        board[keyOf(9, 9)] = "c"
        let full = dailyProgress(board: board, targets: targets, validation: nil, tilesLeft: 4)
        #expect(full.reached == 3)
        #expect(full.ringsDone)
        // Tiles still in hand: reached, but not the clean sweep.
        #expect(!full.allTilesPlaced)
    }

    @Test("the all-tiles tier wants an empty pile and a legal board")
    func allTilesTier() {
        let board: TileMap = [keyOf(0, 0): "c", keyOf(0, 1): "a", keyOf(0, 2): "t"]
        let dictionary: Set<String> = ["cat"]
        let good = validateBoard(board, dictionary: dictionary)
        #expect(dailyProgress(board: board, targets: [], validation: good, tilesLeft: 0).allTilesPlaced)
        // Pile empty but the board isn't legal — no tier.
        let bad = validateBoard(board, dictionary: [])
        #expect(!dailyProgress(board: board, targets: [], validation: bad, tilesLeft: 0).allTilesPlaced)
        // Board legal but tiles in hand — no tier.
        #expect(!dailyProgress(board: board, targets: [], validation: good, tilesLeft: 3).allTilesPlaced)
    }

    @Test("reads strokes against par like golf")
    func readsUnderPar() {
        let under = result(strokes: 5, par: 7, points: 90, dealt: 20, tilesLeft: 0)
        #expect(under.underPar == 2)
        let over = result(strokes: 9, par: 7, points: 90, dealt: 20, tilesLeft: 2)
        #expect(over.underPar == -2)
    }

    @Test("every ring pays, and the par bonus waits for the last one")
    func ringsPayAndParWaits() {
        // Par used to be free money for a player who laid one word and
        // stopped. It is gated on the rings now, which is what stops "quit
        // early, bank the strokes" from being a strategy.
        let none = dailyScore(points: 100, strokes: 1, par: 7, reached: 0, tilesPlaced: 0)
        #expect(none == 100)
        let all = dailyScore(points: 100, strokes: 1, par: 7, reached: 3, tilesPlaced: 0)
        #expect(all == 100 + 3 * DAILY_TARGET_POINTS + 6 * DAILY_PAR_BONUS)
        // Two rings is two rings' worth, and no par bonus at all.
        let some = dailyScore(points: 100, strokes: 1, par: 7, reached: 2, tilesPlaced: 0)
        #expect(some == 100 + 2 * DAILY_TARGET_POINTS)
    }

    @Test("every tile played pays, so the number only ever climbs")
    func tilesPlayedPay() {
        let few = dailyScore(points: 200, strokes: 6, par: 7, reached: 3, tilesPlaced: 15)
        let all = dailyScore(points: 200, strokes: 6, par: 7, reached: 3, tilesPlaced: 20)
        #expect(all - few == 5 * DAILY_TILE_POINTS)
        // Charging for the leftover instead would rank identically — everyone
        // is dealt the same tiles on a given day — but would read zero for the
        // first third of the day, which looks broken rather than strict.
        #expect(dailyScore(points: 0, strokes: 0, par: 7, reached: 0, tilesPlaced: 0) == 0)
    }

    @Test("going over par costs nothing beyond the bonus you did not earn")
    func overParIsNotPunished() {
        // The mode's whole correction was to stop charging people for playing
        // more of it, so par is a prize rather than a tax.
        let atPar = dailyScore(points: 100, strokes: 7, par: 7, reached: 3, tilesPlaced: 20)
        let wayOver = dailyScore(points: 100, strokes: 20, par: 7, reached: 3, tilesPlaced: 20)
        #expect(atPar == wayOver)
    }

    @Test("stopping with tiles in hand never beats playing them")
    func playingOnBeatsStopping() {
        // The trap a voluntary ending sets, and the arithmetic that disarms
        // it: under the old strokes-first packing, quitting on three rings
        // and four words was the optimal line. Here, an ordinary word — three
        // tiles, a modest score — is worth more than the stroke it costs.
        let stopNow = dailyScore(points: 200, strokes: 5, par: 8, reached: 3, tilesPlaced: 11)
        let playOneMore = dailyScore(points: 212, strokes: 6, par: 8, reached: 3, tilesPlaced: 14)
        #expect(playOneMore > stopNow)

        // …and emptying the pile from there is worth far more again.
        let finishIt = dailyScore(
            points: 260 + ALL_TILES_BONUS, strokes: 8, par: 8, reached: 3, tilesPlaced: 20)
        #expect(finishIt > playOneMore)
    }

    @Test("the leaderboard ranks exactly the number the player was shown")
    func leaderboardRanksTheShownNumber() {
        let day = result(strokes: 6, par: 7, points: 180, dealt: 20, tilesLeft: 0)
        #expect(dailyLeaderboardScore(day) == day.score)

        // A better board wins; a shorter one that left the pile full does not.
        let quitEarly = result(strokes: 4, par: 7, points: 60, dealt: 20, tilesLeft: 11)
        #expect(day.score > quitEarly.score)
    }

    @Test("a day that did nothing at all still sorts")
    func neverNegative() {
        let hopeless = result(
            strokes: 0, par: 7, points: 0, dealt: 24, tilesLeft: 24, reached: 0)
        #expect(hopeless.score == 0)
    }

    private func result(
        strokes: Int, par: Int, points: Int, dealt: Int, tilesLeft: Int, reached: Int = 3
    ) -> DailyResult {
        DailyResult(
            strokes: strokes, par: par, points: points, reached: reached,
            tilesPlaced: dealt - tilesLeft, tilesLeft: tilesLeft,
            allTilesPlaced: tilesLeft == 0)
    }
}
