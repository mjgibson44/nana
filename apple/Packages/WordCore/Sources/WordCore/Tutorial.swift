/// The tutorial's script. Ported from `src/game/tutorial.ts`.
///
/// Every step deals exactly the tiles its word needs and waits for that word to
/// appear on the board before moving on, so each step's instructions can name
/// real letters the player is looking at. The deals get shorter as they go: step
/// two is one tile short because its word crosses a letter already down, and step
/// three is two short because its word has to be played through a gap tile.

public struct TutorialStep: Equatable {
    /// Tiles dealt into the pile as the step opens, in the order they're read.
    public let tiles: [String]
    /// The word the step is asking for, lowercase like the board.
    public let word: String
    /// Whether the word has to be played through a gap tile rather than simply
    /// typed over the letter already sitting there. The step teaching the gap
    /// refuses the word without one — otherwise the lesson can be walked past.
    public let needsGap: Bool
    /// Called out over the board the moment the word lands. The banner can't say
    /// this: by the time it's read it has already moved on to asking for the next
    /// word, so nothing else marks the step as done.
    public let done: String

    public init(tiles: [String], word: String, needsGap: Bool, done: String) {
        self.tiles = tiles
        self.word = word
        self.needsGap = needsGap
        self.done = done
    }
}

/// TS `TUTORIAL_SCRIPT`.
public let tutorialScript: [TutorialStep] = [
    // Spelled out in a row in the pile: the first word is there to be read off.
    TutorialStep(
        tiles: ["s", "o", "l", "a", "r"], word: "solar", needsGap: false,
        done: "SOLAR is down!"
    ),
    // No R — ORBIT crosses the one SOLAR just left on the board.
    TutorialStep(
        tiles: ["o", "b", "i", "t"], word: "orbit", needsGap: false,
        done: "ORBIT crossed on the R!"
    ),
    // No O either, and this time the board's O has to be claimed with a gap.
    TutorialStep(
        tiles: ["p", "l", "e"], word: "pole", needsGap: true,
        done: "POLE played through the gap — that’s the whole game!"
    ),
]

/// How many steps the player is walked through.
public let TUTORIAL_STEPS = tutorialScript.count

/// Where the tutorial would play a step's word itself — see `scriptedPlacement`.
public struct ScriptedPlacement: Equatable {
    public var anchor: Cell
    public var dir: Direction
    public var picks: [Pick]

    public init(anchor: Cell, dir: Direction, picks: [Pick]) {
        self.anchor = anchor
        self.dir = dir
        self.picks = picks
    }
}

/// Lay `step`'s word out from `anchor` and report the picks that would play it,
/// or nil when it doesn't fit there.
///
/// Follows exactly the rules `planPlacement` places by, so a fit found here
/// plays: each letter either comes out of the pile or is already on the board
/// with the right letter under it. A step that wants a gap tile claims those
/// board letters with gaps instead of flowing over them, which is the whole
/// difference between the two — and the reason the word it plays is the one the
/// step was teaching.
///
/// The squares just before and just after the word have to be empty, or what
/// lands isn't the word at all but the middle of some longer run.
private func fitWord(
    _ board: TileMap,
    _ bounds: Bounds,
    _ anchor: Cell,
    _ dir: Direction,
    _ step: TutorialStep,
    _ rack: [String]
) -> [Pick]? {
    let before = dir == .across
        ? keyOf(anchor.row, anchor.col - 1)
        : keyOf(anchor.row - 1, anchor.col)
    if board[before] != nil { return nil }

    var picks: [Pick] = []
    var taken = Set<Int>()
    var row = anchor.row
    var col = anchor.col

    for character in step.word {
        let letter = String(character)
        if !bounds.contains(row: row, col: col) { return nil }
        if let sitting = board[keyOf(row, col)] {
            if sitting != letter { return nil }
            if step.needsGap { picks.append(Pick(letter: nil, rackIndex: GAP)) }
        } else {
            let index = findAvailable(rack: rack, letter: letter, taken: taken)
            if index == -1 { return nil }
            taken.insert(index)
            picks.append(Pick(letter: rack[index], rackIndex: index))
        }
        if dir == .across { col += 1 } else { row += 1 }
    }

    if board[keyOf(row, col)] != nil { return nil }
    // Nothing to play — the word is already on the board here.
    if !picks.contains(where: { $0.letter != nil }) { return nil }
    return picks
}

/// Where the tutorial would play `step`'s word itself — what Skip uses, so the
/// board still matches what the next step's instructions describe.
///
/// Sweeps the board for the first spot the word fits. Since a step's pile is
/// deliberately short of the letters its word crosses, the only spots that can
/// fit are the ones that cross them, which is what makes a blind sweep enough.
/// Returns nil when there is no such spot — a board the player has rearranged
/// past recognising, say — leaving the caller to move the step along without
/// playing anything.
public func scriptedPlacement(
    board: TileMap,
    bounds: Bounds,
    step: TutorialStep,
    rack: [String]
) -> ScriptedPlacement? {
    // The opening word has the whole board to itself, so it goes in the middle
    // rather than wherever a sweep of an empty board happens to start.
    if board.isEmpty {
        let row = Int((Double(bounds.minRow + bounds.maxRow) / 2).rounded(.down))
        let col = Int((Double(bounds.minCol + bounds.maxCol) / 2).rounded(.down))
            - step.word.count / 2
        let anchor = Cell(row: row, col: col)
        if let picks = fitWord(board, bounds, anchor, .across, step, rack) {
            return ScriptedPlacement(anchor: anchor, dir: .across, picks: picks)
        }
    }

    for row in stride(from: bounds.minRow, through: bounds.maxRow, by: 1) {
        for col in stride(from: bounds.minCol, through: bounds.maxCol, by: 1) {
            for dir in [Direction.across, .down] {
                if let picks = fitWord(board, bounds, Cell(row: row, col: col), dir, step, rack) {
                    return ScriptedPlacement(anchor: Cell(row: row, col: col), dir: dir, picks: picks)
                }
            }
        }
    }
    return nil
}
