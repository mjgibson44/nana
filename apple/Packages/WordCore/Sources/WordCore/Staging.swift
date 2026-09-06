/// Words built on the board rather than in the row: tiles dragged straight
/// out of the pile onto squares, judged as one placement when the player
/// confirms them.
///
/// The row builds a word first and finds it a home second; dragging does the
/// opposite, so the checks `planPlacement` gets by construction — one line,
/// no holes, touching something — have to be made here, after the fact. The
/// dictionary check is the same one every landing gets.
///
/// No TS counterpart: the web game dropped tiles loose and validated the
/// whole board later, while here nothing goes down that isn't a word.

/// Why a set of staged tiles can't land, with what to tell the player.
public enum StagedRefusal: Error, Equatable {
    case nothing
    case notInALine
    /// A hole between two of the tiles with nothing under it.
    case brokenLine
    /// Every word after the first has to touch a letter already down — one
    /// of your own, on a shared board.
    case mustJoin
    /// A rival's letter in the way. Occupy only: you can't build through one.
    case throughRival
    case openerOffStart
    case notAWord([String])

    public var message: String {
        switch self {
        case .nothing: return "Nothing to place."
        case .notInALine: return "Your tiles have to lie in one line."
        case .brokenLine: return "Fill the gap between your tiles."
        case .mustJoin: return "Your word has to join a letter that’s already down."
        case .throughRival: return "You can’t build through a rival’s letter."
        case .openerOffStart: return "Your first word has to cover your start square."
        case let .notAWord(words):
            let names = words.map { $0.uppercased() }
            return names.count == 1
                ? "\(names[0]) isn’t a word"
                : "\(names.joined(separator: ", ")) aren’t words"
        }
    }
}

/// Staged tiles that would land: how they read, and what they run through.
public struct StagedWord: Equatable {
    /// The line the tiles lie along. A lone tile reads in whichever
    /// direction makes the longer word.
    public var direction: Direction
    /// The letters already down that the word runs through along its line,
    /// in reading order — what an Occupy placement borrows, and captures.
    public var borrowed: [CellKey]
    /// Every run the placement makes or changes, all of them real words.
    public var runs: [WordRun]

    public init(direction: Direction, borrowed: [CellKey], runs: [WordRun]) {
        self.direction = direction
        self.borrowed = borrowed
        self.runs = runs
    }
}

/// Judge tiles dropped on the board as one word. `opener` says whether this
/// player still has their first word to place; a first word that joins
/// nothing has to cover `start`, and every other word has to join something.
///
/// `mine` says which of the letters already down this player may build with.
/// Everything on a solo board is, which is the default; on an Occupy board
/// only this seat's own tiles are, so a rival's letter is a wall rather than
/// something to join or read through.
public func judgeStaged(
    tiles: [CellKey: String], board: TileMap, opener: Bool, start: Cell,
    isWord: (String) -> Bool, mine: (CellKey) -> Bool = { _ in true }
) throws -> StagedWord {
    guard !tiles.isEmpty else { throw StagedRefusal.nothing }
    let cells = tiles.keys.map(parseKey)
    var next = board
    for (key, letter) in tiles { next[key] = letter }

    // Whether a square is this word's to lie along: its own tiles, and the
    // letters already down that this player may build with.
    func usable(_ key: CellKey) -> Bool { tiles[key] != nil || mine(key) }

    /// Nothing missing between the first tile and the last — and nothing in
    /// the way that isn't this player's to build through.
    func walk(_ line: [CellKey]) throws {
        for key in line where tiles[key] == nil {
            guard next[key] != nil else { throw StagedRefusal.brokenLine }
            guard mine(key) else { throw StagedRefusal.throughRival }
        }
    }

    // One line, with nothing missing between the first tile and the last.
    var direction: Direction?
    if cells.count > 1 {
        let rows = Set(cells.map(\.row))
        let cols = Set(cells.map(\.col))
        if rows.count == 1 {
            direction = .across
            let row = cells[0].row
            try walk((cells.map(\.col).min()!...cells.map(\.col).max()!).map { keyOf(row, $0) })
        } else if cols.count == 1 {
            direction = .down
            let col = cells[0].col
            try walk((cells.map(\.row).min()!...cells.map(\.row).max()!).map { keyOf($0, col) })
        } else {
            throw StagedRefusal.notInALine
        }
    }

    let runs = occupyRunsTouching(tiles.keys, in: next, mine: usable)
    let joins = runs.contains { run in run.cells.contains { tiles[$0] == nil } }
    if !joins {
        guard opener else { throw StagedRefusal.mustJoin }
        guard tiles[keyOf(start.row, start.col)] != nil else {
            throw StagedRefusal.openerOffStart
        }
    }

    guard !runs.isEmpty else { throw StagedRefusal.notAWord(tiles.values.sorted()) }
    let bad = runs.filter { $0.word.count < MIN_WORD_LENGTH || !isWord($0.word) }
    guard bad.isEmpty else { throw StagedRefusal.notAWord(bad.map(\.word)) }

    // The word itself: the run along the tiles' line — or, for a lone tile,
    // the longer of the two it sits in (across when they're equal).
    let main: WordRun
    if let direction {
        guard let run = runs.first(where: { $0.direction == direction }) else {
            throw StagedRefusal.notAWord(tiles.values.sorted())
        }
        main = run
    } else {
        main = runs.max {
            $0.cells.count == $1.cells.count
                ? ($0.direction == .down && $1.direction == .across)
                : $0.cells.count < $1.cells.count
        }!
    }
    return StagedWord(
        direction: main.direction,
        borrowed: main.cells.filter { tiles[$0] == nil },
        runs: runs)
}
