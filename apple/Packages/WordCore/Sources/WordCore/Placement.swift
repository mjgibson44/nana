/// Word-placement planning: where picks land, gap tiles, cursor movement.
/// Ported from `src/game/placement.ts`.

/// Rack index standing for a gap tile, which comes from no pile letter.
public let GAP = -1

/// A letter taken from the pile, remembered by its index there — or a gap tile,
/// a deliberate hole in the word that has to land on a letter already on the
/// board. Typing SOLAR with a gap where the L goes plays it over an existing L.
public struct Pick: Equatable {
    public var letter: String?
    public var rackIndex: Int

    public init(letter: String?, rackIndex: Int) {
        self.letter = letter
        self.rackIndex = rackIndex
    }
}

/// One letter actually landing on the board. Gaps produce no step.
public struct PlacementStep: Equatable {
    public var key: CellKey
    public var letter: String
    public var rackIndex: Int

    public init(key: CellKey, letter: String, rackIndex: Int) {
        self.key = key
        self.letter = letter
        self.rackIndex = rackIndex
    }
}

public struct PlacementPlan: Equatable {
    public var steps: [PlacementStep]
    /// Cells where a gap tile came down on an empty square, with no letter under it
    /// to stand on. The word is still laid out around them so the player can see
    /// the shape they're aiming, but it can't be played until they're all covered.
    public var unfilledGaps: [CellKey]
    /// True when every pick found a home and the word stayed on the grid.
    public var complete: Bool

    public init(steps: [PlacementStep], unfilledGaps: [CellKey], complete: Bool) {
        self.steps = steps
        self.unfilledGaps = unfilledGaps
        self.complete = complete
    }
}

/// Lay `picks` out from `anchor` heading in `dir`.
///
/// Tiles already on the board are flowed over rather than displaced: an occupied
/// cell contributes its own letter to the run and does not consume a letter pick.
/// That makes typing a word straight through an existing crossing work the way it
/// does on a real board.
///
/// A gap pick is the explicit version of the same thing — it claims one square,
/// expecting a letter to already be sitting there. When that square turns out to
/// be empty the gap still claims it and the rest of the word carries on past it,
/// so the whole shape stays visible while it's being aimed; the empty square is
/// reported in `unfilledGaps` and the plan is not `complete`, which is what stops
/// it being played. Running off the edge of the grid likewise leaves it
/// incomplete, with only the picks that fitted.
public func planPlacement(
    board: TileMap,
    bounds: Bounds,
    anchor: Cell,
    dir: Direction,
    picks: [Pick]
) -> PlacementPlan {
    var steps: [PlacementStep] = []
    var unfilledGaps: [CellKey] = []
    var row = anchor.row
    var col = anchor.col
    var i = 0

    while i < picks.count && bounds.contains(row: row, col: col) {
        let key = keyOf(row, col)
        let occupied = board[key] != nil
        let pick = picks[i]

        if pick.letter == nil {
            // A gap takes this square either way; it just needs a letter under it.
            if !occupied { unfilledGaps.append(key) }
            i += 1
        } else if !occupied {
            steps.append(PlacementStep(key: key, letter: pick.letter!, rackIndex: pick.rackIndex))
            i += 1
        }

        if dir == .across { col += 1 } else { row += 1 }
    }

    return PlacementPlan(
        steps: steps,
        unfilledGaps: unfilledGaps,
        complete: i == picks.count && unfilledGaps.isEmpty
    )
}

/// Where a word has to start for its first gap pick to land exactly on `target`
/// — the click-a-letter way of filling a gap: type SOLAR with a hole where the
/// L goes, click an L on the board, and the word arranges itself around it.
///
/// Walks planPlacement's rules backwards through the picks before the gap
/// (all letters, since this is the first gap): letters flow back over occupied
/// squares the same way they flow forward over them. The one square with no
/// give is the one right before the gap — a gap claims the very next square
/// after the letter before it, so that letter's square has to be free already.
///
/// Returns nil when the picks have no gap, a square a letter needs is taken,
/// or the walk falls off the grid. A non-nil anchor still needs its plan
/// checked for completeness — later gaps may miss their letters.
public func anchorForGapTarget(
    board: TileMap,
    bounds: Bounds,
    target: Cell,
    dir: Direction,
    picks: [Pick]
) -> Cell? {
    guard let gapAt = picks.firstIndex(where: { $0.letter == nil }) else { return nil }

    var row = target.row
    var col = target.col
    func back() {
        if dir == .across { col -= 1 } else { row -= 1 }
    }

    var i = gapAt - 1
    while i >= 0 {
        back()
        if i < gapAt - 1 {
            while bounds.contains(row: row, col: col) && board[keyOf(row, col)] != nil { back() }
        }
        if !bounds.contains(row: row, col: col) || board[keyOf(row, col)] != nil { return nil }
        i -= 1
    }
    return Cell(row: row, col: col)
}

/// Work out where a whole word's tiles would sit if its first letter moved to
/// `start` and it read in `dir`.
///
/// `own` is the set of cells the word currently occupies; those are treated as
/// free, since the word vacates them as it moves. Returns nil when the run
/// would leave the grid or land on a tile belonging to some other word — the
/// caller uses that to refuse the move (or grey out the control).
public func planWordCells(
    board: TileMap,
    bounds: Bounds,
    length: Int,
    own: [CellKey],
    dir: Direction,
    start: Cell
) -> [CellKey]? {
    var cells: [CellKey] = []
    var i = 0
    while i < length {
        let row = dir == .down ? start.row + i : start.row
        let col = dir == .across ? start.col + i : start.col
        if !bounds.contains(row: row, col: col) { return nil }
        let key = keyOf(row, col)
        if board[key] != nil && !own.contains(key) { return nil }
        cells.append(key)
        i += 1
    }
    return cells
}

/// Which directions a word can actually start in from `cell`.
///
/// An empty cell offers both: the first letter lands right there, and anything
/// further along is flowed over. (Even hard against the far edge it offers both —
/// a one-letter word still fits, and anything longer reports as overflowing.)
///
/// A cell that already holds a letter offers a direction only when the very next
/// cell is free. That existing letter becomes the word's first letter, so if its
/// neighbour is occupied too the first letter typed would leapfrog past it and
/// land somewhere unexpected. Such a cell offers nothing, and can only be read
/// or emptied rather than built on.
public func startableDirections(
    board: TileMap,
    bounds: Bounds,
    cell: Cell
) -> [Direction] {
    let row = cell.row
    let col = cell.col
    if board[keyOf(row, col)] == nil { return [.across, .down] }

    var dirs: [Direction] = []
    if col + 1 <= bounds.maxCol && board[keyOf(row, col + 1)] == nil { dirs.append(.across) }
    if row + 1 <= bounds.maxRow && board[keyOf(row + 1, col)] == nil { dirs.append(.down) }
    return dirs
}

/// Directions the tiles around this cell suggest the player means to type.
///
/// A letter immediately to the left reads as a word already running across into
/// this cell, so they're carrying on rightwards; a letter directly above says the
/// same for downwards. Nothing either side means no opinion.
public func impliedDirections(board: TileMap, cell: Cell) -> [Direction] {
    let row = cell.row
    let col = cell.col
    var dirs: [Direction] = []
    if board[keyOf(row, col - 1)] != nil { dirs.append(.across) }
    if board[keyOf(row - 1, col)] != nil { dirs.append(.down) }
    return dirs
}

/// The cell the next letter typed would land on — where the focus square sits.
///
/// Walks the same path `planPlacement` does, so it flows over tiles already on
/// the board: type through an existing word and the focus jumps out the far side
/// of it rather than sitting on letters that are already there.
public func cursorCell(
    board: TileMap,
    bounds: Bounds,
    anchor: Cell,
    dir: Direction,
    picks: [Pick]
) -> Cell? {
    var row = anchor.row
    var col = anchor.col
    var i = 0

    while bounds.contains(row: row, col: col) {
        let occupied = board[keyOf(row, col)] != nil

        if i >= picks.count {
            // Everything staged is placed; the next letter goes in the next free cell.
            if !occupied { return Cell(row: row, col: col) }
        } else if picks[i].letter == nil {
            // A gap holds its square whether or not a letter is under it yet.
            i += 1
        } else if !occupied {
            i += 1
        }

        if dir == .across { col += 1 } else { row += 1 }
    }
    return nil
}

/// Find the pile tile to consume for a typed letter: the first one that matches
/// and is not already spoken for by the word being built.
public func findAvailable(rack: [String], letter: String, taken: Set<Int>) -> Int {
    let wanted = letter.lowercased()
    for i in 0..<rack.count {
        if rack[i].lowercased() == wanted && !taken.contains(i) { return i }
    }
    return -1
}
