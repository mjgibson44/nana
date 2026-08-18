/// Word extraction, dictionary + connectivity validation.
/// Ported from `src/game/board.ts`.

/// Shortest word the game will accept. Two-letter runs never count.
public let MIN_WORD_LENGTH = 3

/// A maximal horizontal or vertical run of 2+ adjacent letters.
public struct WordRun: Equatable {
    public var word: String
    public var direction: Direction
    public var cells: [CellKey]
    /// Filled in by `validateBoard`; `extractRuns` leaves it `false`.
    public var valid: Bool

    public init(word: String, direction: Direction, cells: [CellKey], valid: Bool = false) {
        self.word = word
        self.direction = direction
        self.cells = cells
        self.valid = valid
    }
}

public struct BoardValidation: Equatable {
    public var runs: [WordRun]
    /// Runs that aren't a legal word: too short, or not in the dictionary.
    public var invalidRuns: [WordRun]
    /// Tiles that are not part of any 2+ letter run.
    public var isolatedTiles: [CellKey]
    /// Tiles cut off from the main body of the board — every one of these has
    /// to be joined up before the board counts as finished.
    public var disconnectedTiles: [CellKey]
    /// True when every placed tile is orthogonally connected into one group
    /// (vacuously true for an empty board).
    public var connected: Bool
    public var tileCount: Int
    /// Board is a fully legal crossword: at least one tile, every run is a
    /// legal word, no isolated tiles, and everything is connected.
    public var ok: Bool
}

/// Extract every maximal 2+ letter run, reading across and down.
/// Emitted in board insertion order, like the TS original.
public func extractRuns(_ tiles: TileMap) -> [WordRun] {
    var runs: [WordRun] = []

    for key in tiles.keys {
        let cell = parseKey(key)
        let row = cell.row
        let col = cell.col

        // Only start a run at a cell with no occupied neighbor before it.
        if !tiles.contains(keyOf(row, col - 1)) {
            var cells: [CellKey] = []
            var c = col
            while tiles.contains(keyOf(row, c)) {
                cells.append(keyOf(row, c))
                c += 1
            }
            if cells.count >= 2 {
                runs.append(WordRun(
                    word: cells.map { tiles[$0]! }.joined(),
                    direction: .across,
                    cells: cells
                ))
            }
        }

        if !tiles.contains(keyOf(row - 1, col)) {
            var cells: [CellKey] = []
            var r = row
            while tiles.contains(keyOf(r, col)) {
                cells.append(keyOf(r, col))
                r += 1
            }
            if cells.count >= 2 {
                runs.append(WordRun(
                    word: cells.map { tiles[$0]! }.joined(),
                    direction: .down,
                    cells: cells
                ))
            }
        }
    }

    return runs
}

/// Split the board into orthogonally-connected groups of tiles, largest first.
/// A finished board is a single group; anything else is islands to be joined
/// up. Ties keep traversal order (the TS relies on stable sort; Swift's
/// `sorted` is documented stable).
public func components(_ tiles: TileMap) -> [[CellKey]] {
    var seen = Set<CellKey>()
    var groups: [[CellKey]] = []

    for start in tiles.keys {
        if seen.contains(start) { continue }
        var group: [CellKey] = []
        var queue: [CellKey] = [start]
        seen.insert(start)
        while let key = queue.popLast() {
            group.append(key)
            let cell = parseKey(key)
            for nk in [
                keyOf(cell.row - 1, cell.col),
                keyOf(cell.row + 1, cell.col),
                keyOf(cell.row, cell.col - 1),
                keyOf(cell.row, cell.col + 1),
            ] {
                if tiles.contains(nk) && !seen.contains(nk) {
                    seen.insert(nk)
                    queue.append(nk)
                }
            }
        }
        groups.append(group)
    }

    return groups.sorted { $0.count > $1.count }
}

/// True when all tiles form a single orthogonally-connected component.
public func isConnected(_ tiles: TileMap) -> Bool {
    components(tiles).count <= 1
}

public func validateBoard(_ tiles: TileMap, dictionary: Set<String>) -> BoardValidation {
    var runs = extractRuns(tiles)
    for i in runs.indices {
        // Two-letter runs are out regardless of the dictionary.
        runs[i].valid = runs[i].word.count >= MIN_WORD_LENGTH && dictionary.contains(runs[i].word)
    }
    let invalidRuns = runs.filter { !$0.valid }

    var covered = Set<CellKey>()
    for run in runs {
        for cell in run.cells { covered.insert(cell) }
    }
    let isolatedTiles = tiles.keys.filter { !covered.contains($0) }

    // Everything outside the biggest group is adrift from the main board.
    let groups = components(tiles)
    let disconnectedTiles = groups.dropFirst().flatMap { $0 }

    let tileCount = tiles.count

    return BoardValidation(
        runs: runs,
        invalidRuns: invalidRuns,
        isolatedTiles: isolatedTiles,
        disconnectedTiles: disconnectedTiles,
        connected: groups.count <= 1,
        tileCount: tileCount,
        ok: tileCount > 0
            && invalidRuns.isEmpty
            && isolatedTiles.isEmpty
            && disconnectedTiles.isEmpty
    )
}
