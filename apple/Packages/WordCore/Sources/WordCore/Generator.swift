/// Puzzle generation. Ported from `src/game/generator.ts`.
///
/// Rather than dealing random letters and hoping they spell something, we
/// build an actual hidden crossword out of common words — each new word
/// crossing an already-placed one — until it uses exactly `tileCount` tiles.
/// The player receives those letters shuffled, so at least one fully valid,
/// fully connected arrangement is guaranteed by construction.
///
/// DETERMINISM: this port mirrors the TS control flow *exactly*, including
/// how many RNG draws each rejection path consumes and every iteration order
/// the RNG indexes into (`TileMap` preserves JS object insertion order).
/// Restructuring the loops below desynchronizes battle clients from web-
/// generated fixtures — see docs/apple-port-plan.md §5 and the golden tests.

public struct Puzzle: Equatable {
    /// The dealt letters, shuffled. Count == requested tileCount.
    public var letters: [String]
    /// One known-good arrangement (proof of solvability). Nil only when the
    /// crossword builder fell back to disjoint word sampling.
    public var solution: TileMap?
    /// The words the letters were drawn from.
    public var sourceWords: [String]
}

public struct ExtendedDeal: Equatable {
    public var letters: [String]
    public var words: [String]
    public var solution: TileMap?
}

public enum GeneratorError: Error, Equatable {
    case emptyWordPool
    case tileCountTooSmall
    case exhausted
}

let MIN_WORD_LEN = 3
let MAX_WORD_LEN = 8

func shuffle<T>(_ items: [T], _ rng: () -> Double) -> [T] {
    var arr = items
    var i = arr.count - 1
    while i > 0 {
        let j = Int((rng() * Double(i + 1)).rounded(.down))
        arr.swapAt(i, j)
        i -= 1
    }
    return arr
}

func pick<T>(_ items: [T], _ rng: () -> Double) -> T {
    items[Int((rng() * Double(items.count)).rounded(.down))]
}

/// Adding a word that crosses one existing tile adds word.count - 1 tiles.
/// The remainder after placing must be 0 (done) or >= MIN_WORD_LEN - 1
/// (still fillable by another crossing word).
func usableLengths(_ remaining: Int) -> [Int] {
    var lengths: [Int] = []
    for len in MIN_WORD_LEN...MAX_WORD_LEN {
        let rest = remaining - (len - 1)
        if rest == 0 || rest >= MIN_WORD_LEN - 1 { lengths.append(len) }
    }
    return lengths
}

struct BuildState {
    var grid: TileMap
    var words: [String]
}

/// Check that `word` can be placed with its `crossIndex`-th letter on the
/// occupied cell (crossRow, crossCol), running in `dir`, without touching or
/// conflicting with anything else. Rejecting all other adjacency means every
/// word on the built grid is exactly one of our chosen words.
func canPlace(
    _ grid: TileMap,
    _ word: [String],
    _ crossRow: Int,
    _ crossCol: Int,
    _ crossIndex: Int,
    _ dir: Direction
) -> Cell? {
    let dr = dir == .down ? 1 : 0
    let dc = dir == .across ? 1 : 0
    let startRow = crossRow - dr * crossIndex
    let startCol = crossCol - dc * crossIndex

    // Cells immediately before the start and after the end must be empty.
    if grid.contains(keyOf(startRow - dr, startCol - dc)) { return nil }
    if grid.contains(keyOf(startRow + dr * word.count, startCol + dc * word.count)) { return nil }

    for i in 0..<word.count {
        let r = startRow + dr * i
        let c = startCol + dc * i
        let k = keyOf(r, c)

        if i == crossIndex {
            if grid[k] != word[i] { return nil }
            continue
        }
        if grid.contains(k) { return nil }
        // Lateral neighbors must be empty so we don't butt up against another word.
        if grid.contains(keyOf(r + dc, c + dr)) { return nil }
        if grid.contains(keyOf(r - dc, c - dr)) { return nil }
    }

    return Cell(row: startRow, col: startCol)
}

func place(_ state: inout BuildState, _ word: [String], _ row: Int, _ col: Int, _ dir: Direction) {
    let dr = dir == .down ? 1 : 0
    let dc = dir == .across ? 1 : 0
    for i in 0..<word.count {
        state.grid[keyOf(row + dr * i, col + dc * i)] = word[i]
    }
    state.words.append(word.joined())
}

/// One attempt at growing a crossword to exactly tileCount tiles. `maxSpan`
/// caps the finished grid's width and height, for boards with real edges.
func tryBuild(
    _ byLetter: [String: [String]],
    _ byLength: [Int: [String]],
    _ tileCount: Int,
    _ rng: () -> Double,
    _ maxSpan: Int?
) -> BuildState? {
    // Seed word: prefer a mid-length word, but never one that strands an
    // unfillable remainder.
    let seedLengths = usableLengths(tileCount + 1).filter { len in
        len <= tileCount && len <= (maxSpan ?? Int.max)
    }
    if seedLengths.isEmpty { return nil }
    let preferred = seedLengths.filter { $0 >= 5 }
    let seedLen = pick(preferred.count > 0 ? preferred : seedLengths, rng)
    guard let seedPool = byLength[seedLen], !seedPool.isEmpty else { return nil }

    var state = BuildState(grid: TileMap(), words: [])
    place(&state, Array(pick(seedPool, rng)).map(String.init), 0, 0, .across)

    // The grid's bounding box so far, for holding the build under maxSpan.
    var minRow = 0
    var maxRow = 0
    var minCol = 0
    var maxCol = seedLen - 1

    var tiles = state.grid.count
    var failures = 0

    while tiles < tileCount && failures < 500 {
        let lengths = usableLengths(tileCount - tiles)
        if lengths.isEmpty { return nil }

        let anchors = state.grid.keys
        let anchorKey = pick(anchors, rng)
        let anchor = parseKey(anchorKey)
        let anchorLetter = state.grid[anchorKey]!

        guard let candidates = byLetter[anchorLetter], !candidates.isEmpty else {
            failures += 1
            continue
        }

        let word = Array(pick(candidates, rng)).map(String.init)
        if !lengths.contains(word.count) {
            failures += 1
            continue
        }

        // Random occurrence of the anchor letter within the word.
        var positions: [Int] = []
        for i in 0..<word.count where word[i] == anchorLetter {
            positions.append(i)
        }
        let crossIndex = pick(positions, rng)
        let dir: Direction = rng() < 0.5 ? .across : .down

        guard let start = canPlace(state.grid, word, anchor.row, anchor.col, crossIndex, dir) else {
            failures += 1
            continue
        }

        // A word that would stretch the grid past maxSpan can never fit the
        // board this puzzle is bound for, however it's slid around.
        let endRow = dir == .down ? start.row + word.count - 1 : start.row
        let endCol = dir == .across ? start.col + word.count - 1 : start.col
        let nextMinRow = min(minRow, start.row)
        let nextMaxRow = max(maxRow, endRow)
        let nextMinCol = min(minCol, start.col)
        let nextMaxCol = max(maxCol, endCol)
        if let maxSpan,
           nextMaxRow - nextMinRow + 1 > maxSpan || nextMaxCol - nextMinCol + 1 > maxSpan {
            failures += 1
            continue
        }

        place(&state, word, start.row, start.col, dir)
        minRow = nextMinRow
        maxRow = nextMaxRow
        minCol = nextMinCol
        maxCol = nextMaxCol
        tiles = state.grid.count
    }

    return tiles == tileCount ? state : nil
}

/// Normalize a grid so its top-left occupied bound is (0,0).
func normalize(_ grid: TileMap) -> TileMap {
    var minRow = Int.max
    var minCol = Int.max
    for key in grid.keys {
        let cell = parseKey(key)
        minRow = min(minRow, cell.row)
        minCol = min(minCol, cell.col)
    }
    var out = TileMap()
    for (key, letter) in grid {
        let cell = parseKey(key)
        out[keyOf(cell.row - minRow, cell.col - minCol)] = letter
    }
    return out
}

/// Fallback if crossword construction somehow fails: sample disjoint words
/// whose lengths sum to exactly tileCount. The letters still spell real
/// words, we just don't hold a pre-connected arrangement.
func fallbackSample(
    _ byLength: [Int: [String]],
    _ tileCount: Int,
    _ rng: () -> Double
) -> (letters: [String], words: [String])? {
    for _ in 0..<200 {
        var words: [String] = []
        var remaining = tileCount
        var dead = false
        while remaining > 0 {
            var lengths: [Int] = []
            if remaining >= MIN_WORD_LEN {
                for len in MIN_WORD_LEN...min(MAX_WORD_LEN, remaining) {
                    let rest = remaining - len
                    if (rest == 0 || rest >= MIN_WORD_LEN) && byLength[len] != nil {
                        lengths.append(len)
                    }
                }
            }
            if lengths.isEmpty {
                dead = true
                break
            }
            let word = pick(byLength[pick(lengths, rng)]!, rng)
            words.append(word)
            remaining -= word.count
        }
        if !dead {
            return (letters: words.joined().map(String.init), words: words)
        }
    }
    return nil
}

/// Letters for a count too small to spell anything. They're drawn a letter at
/// a time from real words, so the mix still reads like English, but no word
/// and no arrangement is promised.
func sampleLetters(_ usable: [String], _ count: Int, _ rng: () -> Double) -> [String] {
    var letters: [String] = []
    while letters.count < count {
        let word = Array(pick(usable, rng)).map(String.init)
        letters.append(word[Int((rng() * Double(word.count)).rounded(.down))])
    }
    return letters
}

/// Would a word laid from here stay on the board?
func fitsBoard(_ start: Cell, _ length: Int, _ dir: Direction, _ bounds: Bounds) -> Bool {
    let endRow = dir == .down ? start.row + length - 1 : start.row
    let endCol = dir == .across ? start.col + length - 1 : start.col
    return start.row >= bounds.minRow
        && start.col >= bounds.minCol
        && endRow <= bounds.maxRow
        && endCol <= bounds.maxCol
}

/// One attempt at growing exactly `tileCount` *new* tiles onto tiles that are
/// already there, every added word crossing something already on the board.
func tryExtend(
    _ initial: TileMap,
    _ bounds: Bounds,
    _ byLetter: [String: [String]],
    _ tileCount: Int,
    _ rng: () -> Double
) -> BuildState? {
    var state = BuildState(grid: initial, words: [])
    let before = initial.count
    var added = 0
    var failures = 0
    // The cells a new word can cross, listed once and extended as words land.
    var anchors = state.grid.keys

    while added < tileCount && failures < 800 {
        let lengths = usableLengths(tileCount - added)
        if lengths.isEmpty { return nil }

        let anchorKey = pick(anchors, rng)
        let anchor = parseKey(anchorKey)
        let anchorLetter = state.grid[anchorKey]!

        guard let candidates = byLetter[anchorLetter], !candidates.isEmpty else {
            failures += 1
            continue
        }

        let word = Array(pick(candidates, rng)).map(String.init)
        if !lengths.contains(word.count) {
            failures += 1
            continue
        }

        var positions: [Int] = []
        for i in 0..<word.count where word[i] == anchorLetter {
            positions.append(i)
        }
        let crossIndex = pick(positions, rng)
        let dir: Direction = rng() < 0.5 ? .across : .down

        guard let start = canPlace(state.grid, word, anchor.row, anchor.col, crossIndex, dir),
              fitsBoard(start, word.count, dir, bounds)
        else {
            failures += 1
            continue
        }

        place(&state, word, start.row, start.col, dir)
        anchors = state.grid.keys
        added = anchors.count - before
    }

    return added == tileCount ? state : nil
}

/// Build the letter → words index (bucket order = pool order; per-word letter
/// order = first occurrence, mirroring JS `new Set(word)` iteration).
func buildByLetter(_ words: [String]) -> [String: [String]] {
    var byLetter: [String: [String]] = [:]
    for word in words {
        var seen = Set<Character>()
        for ch in word where !seen.contains(ch) {
            seen.insert(ch)
            byLetter[String(ch), default: []].append(word)
        }
    }
    return byLetter
}

/// Deal `tileCount` more letters for a board that's already been built on.
/// The letters come from words grown off the tiles already down, so at least
/// one way to play every one of them onto the board as it stands is known to
/// exist by construction. `solution` is that arrangement; it is nil only if
/// no extension could be found and the letters fall back to a standalone
/// sample.
public func extendPuzzle(
    board: TileMap,
    bounds: Bounds,
    wordPool: [String],
    tileCount: Int,
    rng: () -> Double
) throws -> ExtendedDeal {
    // Nothing to grow from: this is just a fresh little puzzle of its own.
    if board.isEmpty { return try standalone(wordPool, tileCount, rng) }

    // A single tile is fewer than any word could bring — the shortest word
    // crossing a letter already down adds two.
    if tileCount < MIN_WORD_LEN - 1 { return try standalone(wordPool, tileCount, rng) }

    let byLetter = buildByLetter(usableWords(wordPool))

    for _ in 0..<200 {
        guard let built = tryExtend(board, bounds, byLetter, tileCount, rng) else { continue }
        let letters = built.grid.keys
            .filter { !board.contains($0) }
            .map { built.grid[$0]! }
        return ExtendedDeal(letters: shuffle(letters, rng), words: built.words, solution: built.grid)
    }

    // A board too congested to grow off of. The player just isn't handed a
    // guaranteed home for these letters.
    return try standalone(wordPool, tileCount, rng)
}

/// Letters owing nothing to the board they're joining: a whole little puzzle
/// of their own where that's possible, and a plain draw from the pool where
/// the count is too small for even one word.
func standalone(_ wordPool: [String], _ tileCount: Int, _ rng: () -> Double) throws -> ExtendedDeal {
    if tileCount < MIN_WORD_LEN {
        let usable = usableWords(wordPool)
        if usable.isEmpty { throw GeneratorError.emptyWordPool }
        return ExtendedDeal(letters: sampleLetters(usable, tileCount, rng), words: [], solution: nil)
    }
    let puzzle = try generatePuzzle(wordPool: wordPool, tileCount: tileCount, rng: rng)
    return ExtendedDeal(letters: puzzle.letters, words: puzzle.sourceWords, solution: nil)
}

func usableWords(_ wordPool: [String]) -> [String] {
    wordPool.filter { w in
        w.count >= MIN_WORD_LEN && w.count <= MAX_WORD_LEN
            && w.allSatisfy { $0 >= "a" && $0 <= "z" }
    }
}

/// Deal a fresh puzzle of exactly `tileCount` letters. `maxSpan` (optional)
/// caps the hidden solution's width and height, so the deal is known to fit
/// a board of that size.
public func generatePuzzle(
    wordPool: [String],
    tileCount: Int = 20,
    rng: () -> Double,
    maxSpan: Int? = nil
) throws -> Puzzle {
    let usable = usableWords(wordPool)
    if usable.isEmpty { throw GeneratorError.emptyWordPool }
    if tileCount < MIN_WORD_LEN { throw GeneratorError.tileCountTooSmall }

    let byLetter = buildByLetter(usable)
    var byLength: [Int: [String]] = [:]
    for word in usable {
        byLength[word.count, default: []].append(word)
    }

    // A span cap makes attempts fail more often, so a bounded deal gets more.
    let attempts = maxSpan == nil ? 100 : 400
    for _ in 0..<attempts {
        if let built = tryBuild(byLetter, byLength, tileCount, rng, maxSpan) {
            let solution = normalize(built.grid)
            return Puzzle(
                letters: shuffle(solution.values, rng),
                solution: solution,
                sourceWords: built.words
            )
        }
    }

    guard let fallback = fallbackSample(byLength, tileCount, rng) else {
        throw GeneratorError.exhausted
    }
    return Puzzle(
        letters: shuffle(fallback.letters, rng),
        solution: nil,
        sourceWords: fallback.words
    )
}
