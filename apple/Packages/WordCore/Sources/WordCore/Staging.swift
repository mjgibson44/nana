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
    /// Every word after the first has to touch a letter already down.
    case mustJoin
    case openerOffStart
    case notAWord([String])

    public var message: String {
        switch self {
        case .nothing: return "Nothing to place."
        case .notInALine: return "Your tiles have to lie in one line."
        case .brokenLine: return "Fill the gap between your tiles."
        case .mustJoin: return "Your word has to join a letter that’s already down."
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
public func judgeStaged(
    tiles: [CellKey: String], board: TileMap, opener: Bool, start: Cell,
    isWord: (String) -> Bool
) throws -> StagedWord {
    guard !tiles.isEmpty else { throw StagedRefusal.nothing }
    let cells = tiles.keys.map(parseKey)
    var next = board
    for (key, letter) in tiles { next[key] = letter }

    // One line, with nothing missing between the first tile and the last.
    var direction: Direction?
    if cells.count > 1 {
        let rows = Set(cells.map(\.row))
        let cols = Set(cells.map(\.col))
        if rows.count == 1 {
            direction = .across
            let row = cells[0].row
            for col in cells.map(\.col).min()!...cells.map(\.col).max()!
            where next[keyOf(row, col)] == nil {
                throw StagedRefusal.brokenLine
            }
        } else if cols.count == 1 {
            direction = .down
            let col = cells[0].col
            for row in cells.map(\.row).min()!...cells.map(\.row).max()!
            where next[keyOf(row, col)] == nil {
                throw StagedRefusal.brokenLine
            }
        } else {
            throw StagedRefusal.notInALine
        }
    }

    let runs = runsTouching(tiles.keys, in: next)
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
