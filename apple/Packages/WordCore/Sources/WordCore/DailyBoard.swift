/// The Daily board: one crossword a day, started for you.
///
/// New on Apple platforms, like `DailyDeal` itself — there is no
/// `src/game/dailyBoard.ts` to port. `DailyDeal` decides *which* day is live
/// and what seed it deals from; this file decides what that seed puts on the
/// screen: a **seed word** already on the board, a deal of the letters that
/// finish the crossword it came from, three **target cells** to reach, and the
/// **par** to beat.
///
/// ## Why the seed word and the targets are one idea
///
/// The board has no origin. `boardBounds` grows the playable rectangle around
/// whatever has been played, cell keys run negative quite happily, and
/// `normalize` slides every generated solution back to (0, 0) before it is
/// dealt. So on an empty board "the target is at row 3, column 7" says
/// nothing: the player builds wherever they like, and any single target is
/// covered by starting on top of it.
///
/// Put a word down first and the coordinate system is pinned. Now a target is
/// a real place — four left of the seed word and two down — and reaching it
/// means building in a direction you did not choose, with letters you were
/// given. That is the whole mode. It also means two players' boards are the
/// same *position* rather than merely the same letters, which is what makes
/// comparing them after the fact worth doing.
///
/// ## The construction
///
/// Everything falls out of one `generatePuzzle` call, and every guarantee the
/// generator already makes survives:
///
///  1. Generate a hidden crossword of `tileCount` tiles from the day's seed.
///  2. Take one of its own words as the **seed word** and leave it on the
///     board, at the position it occupies in that crossword.
///  3. **Deal** the letters of every other cell, shuffled.
///  4. Mark three of those other cells as **targets**, spread apart.
///  5. **Par** is how many words the hidden crossword used.
///
/// The targets are reachable because they are cells of a crossword the deal is
/// known to build; par is achievable because that crossword achieves it, and
/// beatable because the letters come from several ordinary overlapping words,
/// so there are normally tighter arrangements too. Par is therefore *derived*
/// rather than tuned — it is honest on every deal, with no balancing pass.
///
/// ## Determinism
///
/// The whole construction is a pure function of the seed, so every player on a
/// given day gets the identical board. Nothing here indexes an RNG into an
/// unordered collection, and every choice among equals is broken by a total
/// rule rather than by sort stability (Swift's `sort` is not stable), so the
/// answer does not depend on the standard library's mood. If the web ever
/// adopts the same date seed (plan §16.3 q5) it must mirror these rules
/// exactly — a different seed word is a different puzzle.

/// The knobs the shape of the puzzle depends on. Measured rather than guessed:
/// each was chosen by running this construction over 500 seeds against the
/// canonical TypeScript generator and looking at what came out (see
/// `docs/daily-and-modifiers.md`).
public enum DailyBoardRules {
    /// Tiles in the day's crossword, the seed word included — so the player is
    /// dealt this many less the length of the word already down, which lands
    /// between twenty and twenty-three. Enough to need real building, few
    /// enough to finish in a sitting, and few enough to fit the pile (see
    /// `maxDeal`). (`DailyRules` next door owns the calendar — which day is
    /// live, when it rolls over, and the seed. The rules of the puzzle itself
    /// are here.)
    public static let tileCount = 28

    /// The most tiles a day may deal into the hand.
    ///
    /// The app draws the pile as three rows of eight and buries a player who
    /// fills it, so a deal larger than that would arrive already overflowing.
    /// `tileCount` is chosen so this never binds — the largest deal it can
    /// produce is a seed word of three, which the preference order never
    /// reaches — but the puzzle is dealt to a fixed pile and it should say so
    /// rather than leave it to arithmetic elsewhere.
    public static let maxDeal = 24

    /// How many cells the player must reach.
    public static let targets = 3

    /// Seed-word lengths, best first. A six lands in the middle of the board
    /// and still leaves the player two dozen tiles; the longest word the
    /// generator deals would be a bigger giveaway and a smaller deal. The tail
    /// is fallback — over 500 seeds the first two lengths covered all but one.
    public static let seedWordLengths = [6, 5, 7, 8, 4, 3]

    /// The closest two targets may sit, as a Chebyshev distance. Below this
    /// they stop being separate places to reach.
    public static let minTargetGap = 4

    /// How far every target must sit from the seed word, so none of them is
    /// covered incidentally by the first word played…
    public static let minSeedGap = 2

    /// …and how far the *first* one must sit, which is what makes the puzzle
    /// span the board rather than huddle around the opening.
    public static let minFirstSeedGap = 3

    /// How many deals to try before giving up. Over 500 seeds the first deal
    /// was accepted every time but twice, so this is headroom, not a budget.
    public static let buildAttempts = 12
}

public enum DailyBoardError: Error, Equatable {
    /// Every attempt was rejected — see `DailyBoardRules.buildAttempts`.
    case exhausted
}

/// A day's puzzle, ready to play.
public struct DailyBoard: Equatable {
    /// The board as the player finds it: the seed word, and nothing else.
    public var board: TileMap
    /// The seed word itself, for the card that fronts the day.
    public var seedWord: String
    /// The cells it occupies, in reading order.
    public var seedCells: [CellKey]
    /// The deal — every other letter of the hidden crossword, shuffled.
    public var letters: [String]
    /// The three cells the player has to reach, in the order they were chosen
    /// (farthest from the seed word first).
    public var targets: [CellKey]
    /// How many words the hidden crossword used. The number to beat.
    public var par: Int
    /// The crossword this all came from, in board coordinates — the seed word
    /// plus every dealt letter in a place that works. Kept for the same reason
    /// `Puzzle.solution` is: it is the proof that the targets can be reached
    /// and that par can be made, it is what a hint would read, and it is what
    /// lets a test check both instead of taking them on trust.
    public var solution: TileMap

    public init(
        board: TileMap,
        seedWord: String,
        seedCells: [CellKey],
        letters: [String],
        targets: [CellKey],
        par: Int,
        solution: TileMap
    ) {
        self.board = board
        self.seedWord = seedWord
        self.seedCells = seedCells
        self.letters = letters
        self.targets = targets
        self.par = par
        self.solution = solution
    }
}

/// Chebyshev distance — king moves. Diagonal steps count as one, which is the
/// right measure for "are these two targets in different parts of the board":
/// a crossword reaches diagonally about as easily as it reaches straight.
func chebyshev(_ a: CellKey, _ b: CellKey) -> Int {
    let p = parseKey(a)
    let q = parseKey(b)
    return max(abs(p.row - q.row), abs(p.col - q.col))
}

/// Build the day's board from its seed.
///
/// Rejects and re-rolls rather than settling: a deal whose crossword has no
/// usable seed word, or whose remaining cells cannot hold three targets far
/// enough apart, is thrown away and another dealt from the same RNG. A
/// `nil` solution — the generator's disjoint-word fallback — is rejected for
/// the same reason: everything here is built out of the solution, so a deal
/// without one has no board to offer.
public func dailyBoard(
    seed: String,
    tileCount: Int = DailyBoardRules.tileCount,
    wordPool: [String] = commonWords
) throws -> DailyBoard {
    let rng = seededRng(seed)

    for _ in 0..<DailyBoardRules.buildAttempts {
        guard let candidate = try buildDailyBoard(wordPool: wordPool, tileCount: tileCount, rng: rng)
        else { continue }
        return candidate
    }
    throw DailyBoardError.exhausted
}

/// One attempt. Returns nil for a deal that doesn't meet the shape wanted —
/// the caller re-rolls. Throws only what the generator throws (an unusable
/// word pool or tile count), which is a programming error rather than a deal
/// to try again.
private func buildDailyBoard(
    wordPool: [String],
    tileCount: Int,
    rng: () -> Double
) throws -> DailyBoard? {
    let puzzle = try generatePuzzle(wordPool: wordPool, tileCount: tileCount, rng: rng)
    guard let solution = puzzle.solution else { return nil }

    let runs = extractRuns(solution)
    guard !runs.isEmpty else { return nil }
    // A legal crossword has no run too short to be a word. The generator has
    // never produced one, but par counts runs, so it has to be true.
    guard runs.allSatisfy({ $0.cells.count >= MIN_WORD_LENGTH }) else { return nil }

    guard let seedRun = pickSeedWord(runs, in: solution) else { return nil }
    let seedCells = Set(seedRun.cells)

    // Everything the player is dealt, in the solution's own insertion order.
    let rest = solution.keys.filter { !seedCells.contains($0) }
    guard rest.count <= DailyBoardRules.maxDeal else { return nil }
    guard let targets = pickTargets(rest, seedCells: seedRun.cells) else { return nil }

    // Slide the whole frame so the crossword sits in the middle of the board
    // the game opens on. Solutions are normalized to (0, 0) and span well
    // under BOARD_SIZE, so both offsets come out positive.
    var height = 0
    var width = 0
    for key in solution.keys {
        let cell = parseKey(key)
        height = max(height, cell.row + 1)
        width = max(width, cell.col + 1)
    }
    let rowOffset = (BOARD_SIZE - height) / 2
    let colOffset = (BOARD_SIZE - width) / 2
    let shift: (CellKey) -> CellKey = { key in
        let cell = parseKey(key)
        return keyOf(cell.row + rowOffset, cell.col + colOffset)
    }

    var board = TileMap()
    for key in seedRun.cells { board[shift(key)] = solution[key] }

    var shifted = TileMap()
    for key in solution.keys { shifted[shift(key)] = solution[key] }

    return DailyBoard(
        board: board,
        seedWord: seedRun.word,
        seedCells: seedRun.cells.map(shift),
        letters: shuffle(rest.map { solution[$0]! }, rng),
        targets: targets.map(shift),
        par: runs.count,
        solution: shifted
    )
}

/// Which of the crossword's own words to leave on the board: the most
/// preferred length available, and among those the one sitting nearest the
/// middle — an opening in the corner would push the whole puzzle off to one
/// side. Returns nil if no run is a length we'd use, which re-rolls the deal.
private func pickSeedWord(_ runs: [WordRun], in solution: TileMap) -> WordRun? {
    // Twice the middle of the crossword's bounding box, kept doubled so the
    // comparison below stays in whole numbers.
    var minRow = Int.max, maxRow = Int.min, minCol = Int.max, maxCol = Int.min
    for key in solution.keys {
        let cell = parseKey(key)
        minRow = min(minRow, cell.row); maxRow = max(maxRow, cell.row)
        minCol = min(minCol, cell.col); maxCol = max(maxCol, cell.col)
    }
    let midRow2 = minRow + maxRow
    let midCol2 = minCol + maxCol

    /// How far off-centre a run sits, doubled. Measured from the run's middle
    /// cell rather than its mean so the whole comparison is integer — a mean
    /// would put float ordering in the middle of a determinism contract.
    func offCentre(_ run: WordRun) -> Int {
        let middle = parseKey(run.cells[run.cells.count / 2])
        return abs(2 * middle.row - midRow2) + abs(2 * middle.col - midCol2)
    }

    var best: WordRun?
    var bestRank = DailyBoardRules.seedWordLengths.count
    var bestOffCentre = Int.max
    for run in runs {
        guard let rank = DailyBoardRules.seedWordLengths.firstIndex(of: run.cells.count)
        else { continue }
        let off = offCentre(run)
        // Strictly better only — so scanning in `runs` order settles every tie
        // the same way every time, without leaning on sort stability.
        if rank < bestRank || (rank == bestRank && off < bestOffCentre) {
            best = run
            bestRank = rank
            bestOffCentre = off
        }
    }
    return best
}

/// Pick the cells to reach: farthest-point sampling over what's left of the
/// crossword, starting from the cell furthest from the seed word and taking
/// whichever remaining cell is furthest from everything chosen so far.
///
/// Returns nil — re-roll the deal — if the cells left can't be spread out
/// enough to be three separate places to get to.
private func pickTargets(_ rest: [CellKey], seedCells: [CellKey]) -> [CellKey]? {
    func distanceToSeed(_ key: CellKey) -> Int {
        seedCells.reduce(Int.max) { min($0, chebyshev(key, $1)) }
    }

    // Nothing sitting right against the opening: those get covered by the
    // first word played, which is not a target, it's a formality.
    let pool = rest.filter { distanceToSeed($0) >= DailyBoardRules.minSeedGap }
    guard pool.count >= DailyBoardRules.targets else { return nil }

    // The first target is the far one, and it's what makes the board span.
    var first: CellKey?
    var firstDistance = -1
    for key in pool where distanceToSeed(key) >= DailyBoardRules.minFirstSeedGap {
        if distanceToSeed(key) > firstDistance {
            first = key
            firstDistance = distanceToSeed(key)
        }
    }
    guard let first else { return nil }

    var chosen = [first]
    while chosen.count < DailyBoardRules.targets {
        var best: CellKey?
        var bestGap = -1
        for key in pool where !chosen.contains(key) {
            let gap = chosen.reduce(Int.max) { min($0, chebyshev(key, $1)) }
            if gap > bestGap {
                best = key
                bestGap = gap
            }
        }
        guard let best, bestGap >= DailyBoardRules.minTargetGap else { return nil }
        chosen.append(best)
    }
    return chosen
}

// MARK: - Playing one

/// How a day's puzzle stands right now.
///
/// The Daily cannot be lost, only left unfinished: there is no clock and no
/// pile limit, so `done` is the only verdict and it only ever goes one way.
/// That is deliberate for a one-attempt-a-day mode — the tension belongs in
/// your number against par, not in a loss you can't play again.
public struct DailyProgress: Equatable {
    /// Targets covered by a tile, in the board's target order.
    public var covered: [Bool]
    public var reached: Int
    /// Every target covered — the puzzle is finished.
    public var done: Bool
    /// Every dealt tile placed on a fully valid, connected board as well.
    public var allTilesPlaced: Bool

    public init(covered: [Bool], reached: Int, done: Bool, allTilesPlaced: Bool) {
        self.covered = covered
        self.reached = reached
        self.done = done
        self.allTilesPlaced = allTilesPlaced
    }
}

public func dailyProgress(
    board: TileMap,
    targets: [CellKey],
    validation: BoardValidation?,
    tilesLeft: Int
) -> DailyProgress {
    let covered = targets.map { board.contains($0) }
    let reached = covered.filter { $0 }.count
    return DailyProgress(
        covered: covered,
        reached: reached,
        done: reached == targets.count,
        allTilesPlaced: tilesLeft == 0 && (validation?.ok ?? false)
    )
}

/// What a finished daily is worth.
///
/// Two numbers, because the mode is about two things at once: **strokes** —
/// words played, low is good — and the points the board is worth. They pull
/// against each other productively. `wordScore` is triangular and every run
/// pays, so points want a densely crossed board with many runs; par wants few
/// words. The move that serves both is one word that lands across three
/// others: four new runs for one stroke.
///
/// There is no "taken back" to record. The app's words are permanent in every
/// mode, so a stroke is a word played and that is the end of it — the question
/// of whether an undo should refund one never comes up. What softens that is
/// staging: tiles sit ghosted on the board and can be moved or cleared freely
/// until the ✓, so the thinking happens before the stroke is spent.
public struct DailyResult: Equatable {
    public var strokes: Int
    public var par: Int
    /// Strokes under par — negative is over, like golf.
    public var underPar: Int
    public var points: Int
    public var reached: Int
    public var allTilesPlaced: Bool

    public init(
        strokes: Int,
        par: Int,
        points: Int,
        reached: Int,
        allTilesPlaced: Bool
    ) {
        self.strokes = strokes
        self.par = par
        self.underPar = par - strokes
        self.points = points
        self.reached = reached
        self.allTilesPlaced = allTilesPlaced
    }
}

/// The most strokes a daily score can express. Well past any plausible board —
/// par runs to eight and a deal is two dozen tiles — so the encoding below
/// never has to clamp a real game.
public let DAILY_STROKE_CAP = 200

/// Points a daily can carry into the leaderboard before the encoding would
/// collide with the next stroke. Two dozen tiles cannot approach it.
public let DAILY_POINT_CAP = 100_000

/// A Game Center recurring leaderboard takes one integer, and this score is
/// two-dimensional — so pack it, strokes first, points as the tiebreak.
///
/// Strokes lead because that is what the mode is about; points settle two
/// players who got there in the same number of words, and the player with the
/// better-crossed board wins that. Both are clamped so a nonsense game can
/// never bleed into the stroke digits.
///
/// **This encoding is permanent.** A leaderboard's scores cannot be
/// reinterpreted once submitted, so changing it means a new leaderboard.
public func dailyLeaderboardScore(_ result: DailyResult) -> Int {
    let strokes = min(max(result.strokes, 0), DAILY_STROKE_CAP)
    let points = min(max(result.points, 0), DAILY_POINT_CAP - 1)
    return (DAILY_STROKE_CAP - strokes) * DAILY_POINT_CAP + points
}
