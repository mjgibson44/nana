/// Occupy: two to four players on one fixed, shared board, each starting in
/// the centre of a quadrant, racing to hold the most valuable ground when the
/// clock runs out.
///
/// New on Apple platforms, with no counterpart in the web game. Everything
/// here is pure and serializable: the host runs `occupyApply` as the referee,
/// every client runs the same function to show its own word the instant it
/// lands (and takes it back if the host says no), and the results screen
/// reads `occupyRanking` off the final state. One rule set, one function,
/// so what a player sees and what the host decides can never disagree.
///
/// The rules in one breath:
///
///  - The board is `occupyBoardSize` square and never grows. Each seat opens
///    from its own start square (`occupyStartCell`) — and every seat sees the
///    board turned so that square sits top-left (`occupyRotation`), so
///    everyone's own words run left to right, toward the middle. A rival's
///    words therefore read backwards on your screen, and a run counts as a
///    word if it reads as one in either direction (`occupyIsWord`).
///  - Every word after the opener borrows a letter through a gap tile. The
///    borrowed letter is **captured**: it flips to the borrower's colour.
///  - Every tile is worth the length of the longest word it sits in, and a
///    player scores the tiles they own. Long words are worth more than the
///    same letters as short ones, and a capture carries the tile's value.
///  - A letter already in both an across and a down word has no free
///    direction, so it can't be crossed again — a long word is defended by
///    crossing its own letters.
///  - The pile is dealt to `OCCUPY_HAND` and refilled after every word; it
///    never buries anyone.
///  - The game ends on the clock, or early once nobody has placed a word for
///    `OCCUPY_STALL_SECONDS` — after an opening grace during which it can't
///    end at all. Most value wins; ties go to quadrants held, then to whoever
///    reached their score first.

import Foundation

// MARK: - Constants

/// How many players an Occupy game seats. Two sit diagonal; four take every
/// quadrant; three leave one corner empty.
public let OCCUPY_MIN_PLAYERS = 2
public let OCCUPY_MAX_PLAYERS = 4

/// Every hand is dealt to this and refilled to it after every word. It's the
/// app's pile limit, so a full pile is the normal state of things here rather
/// than the end.
public let OCCUPY_HAND = 24

/// Fifteen is Scrabble's board and fits an iPhone's width without zooming;
/// nineteen is Go's, and gives four crosswords room to meet.
public let OCCUPY_SMALL_BOARD = 15
public let OCCUPY_LARGE_BOARD = 19

/// Three minutes head-to-head — Battle's round length — and an extra minute
/// on the bigger board, which has more than half again the area.
public let OCCUPY_SHORT_SECONDS = 180
public let OCCUPY_LONG_SECONDS = 240

/// A full minute of nobody placing a word is a locked board, and the game
/// ends early. Long enough to compose a long word and hunt for a crossing;
/// short enough that a stuck board doesn't run out the whole clock.
public let OCCUPY_STALL_SECONDS: Double = 60

/// The opening grace: the stall clock doesn't run for this long, so a slow
/// start can't end the game.
public let OCCUPY_GRACE_SECONDS: Double = 30

/// The stall countdown shows on screen once this much of it is left, so the
/// end is never a surprise.
public let OCCUPY_STALL_WARNING_SECONDS: Double = 20

public func occupyBoardSize(players: Int) -> Int {
    players <= 2 ? OCCUPY_SMALL_BOARD : OCCUPY_LARGE_BOARD
}

public func occupySeconds(players: Int) -> Int {
    players <= 2 ? OCCUPY_SHORT_SECONDS : OCCUPY_LONG_SECONDS
}

// MARK: - Geometry

/// Where a seat starts: the centre of its quadrant. Seats are numbered so two
/// players sit diagonal from each other — 0 top-left, 1 bottom-right, then 2
/// top-right and 3 bottom-left.
public func occupyStartCell(seat: Int, size: Int) -> Cell {
    let near = size / 4
    let far = size - 1 - near
    switch seat {
    case 0: return Cell(row: near, col: near)
    case 1: return Cell(row: far, col: far)
    case 2: return Cell(row: near, col: far)
    default: return Cell(row: far, col: near)
    }
}

/// How the board is turned for a seat: quarter turns clockwise of the host's
/// board, chosen so the seat's own start square lands where seat 0's is —
/// the top-left quadrant. Every player then opens from their top-left and
/// writes left to right, toward the middle; what crosses the wire is still
/// the host's frame, so a right-hand seat's word is stored reversed there.
public enum OccupyRotation: Int, CaseIterable, Equatable {
    case upright = 0
    case quarter = 1
    case half = 2
    case threeQuarters = 3

    /// The turn that undoes this one.
    public var inverse: OccupyRotation {
        OccupyRotation(rawValue: (4 - rawValue) % 4)!
    }
}

/// The turn that puts a seat's start square top-left.
public func occupyRotation(seat: Int) -> OccupyRotation {
    switch seat {
    case 1: return .half
    case 2: return .threeQuarters
    case 3: return .quarter
    default: return .upright
    }
}

/// A cell after `rotation` quarter turns clockwise of a `size`-square board.
public func rotateCell(_ cell: Cell, size: Int, by rotation: OccupyRotation) -> Cell {
    let n = size - 1
    switch rotation {
    case .upright: return cell
    case .quarter: return Cell(row: cell.col, col: n - cell.row)
    case .half: return Cell(row: n - cell.row, col: n - cell.col)
    case .threeQuarters: return Cell(row: n - cell.col, col: cell.row)
    }
}

public func rotateKey(_ key: CellKey, size: Int, by rotation: OccupyRotation) -> CellKey {
    guard rotation != .upright else { return key }
    let cell = rotateCell(parseKey(key), size: size, by: rotation)
    return keyOf(cell.row, cell.col)
}

public func rotateOwners(
    _ owners: [CellKey: Int], size: Int, by rotation: OccupyRotation
) -> [CellKey: Int] {
    guard rotation != .upright else { return owners }
    var turned: [CellKey: Int] = [:]
    for (key, seat) in owners { turned[rotateKey(key, size: size, by: rotation)] = seat }
    return turned
}

extension TileMap {
    /// The same letters on a turned board. Insertion order is kept, so a
    /// turned board deals the same hand as its original would.
    public func rotated(size: Int, by rotation: OccupyRotation) -> TileMap {
        guard rotation != .upright else { return self }
        return TileMap(entries.map { (rotateKey($0.key, size: size, by: rotation), $0.value) })
    }
}

/// Whether a run reads as a word in either direction along its line. Every
/// seat writes left to right in its own frame, so in the host's frame — and
/// on every rival's screen — some words are stored backwards.
public func occupyIsWord(_ word: String, isWord: (String) -> Bool) -> Bool {
    isWord(word) || isWord(String(word.reversed()))
}

/// The quadrant a cell sits in, numbered like the seats, or nil on the centre
/// lines of an odd-sized board — those belong to nobody.
public func occupyQuadrant(of cell: Cell, size: Int) -> Int? {
    let mid = size / 2
    if size % 2 == 1, cell.row == mid || cell.col == mid { return nil }
    let top = cell.row < mid
    let left = cell.col < mid
    switch (top, left) {
    case (true, true): return 0
    case (false, false): return 1
    case (true, false): return 2
    case (false, true): return 3
    }
}

/// The squares the gap picks would sit on, laid out from `anchor` the same
/// way `planPlacement` lays the word — the letters a placement borrows, and
/// so the letters it captures. Every one of them holds a letter when the
/// plan is complete.
public func gapCells(
    board: TileMap, bounds: Bounds, anchor: Cell, dir: Direction, picks: [Pick]
) -> [CellKey] {
    var gaps: [CellKey] = []
    var row = anchor.row
    var col = anchor.col
    var i = 0
    while i < picks.count && bounds.contains(row: row, col: col) {
        let key = keyOf(row, col)
        let occupied = board[key] != nil
        let pick = picks[i]
        if pick.letter == nil {
            gaps.append(key)
            i += 1
        } else if !occupied {
            i += 1
        }
        if dir == .across { col += 1 } else { row += 1 }
    }
    return gaps
}

// MARK: - The shared state

/// One word landing: the new tiles, and the letters it borrowed through gaps.
/// This is what crosses the wire — the outcome rather than the picks, so the
/// host judges exactly the squares the client showed.
public struct OccupyPlacement: Codable, Equatable {
    public var tiles: [CellKey: String]
    public var borrowed: [CellKey]

    public init(tiles: [CellKey: String], borrowed: [CellKey]) {
        self.tiles = tiles
        self.borrowed = borrowed
    }

    /// The same word on a turned board — how a client's word, laid in its own
    /// frame, is put into the host's before it's sent.
    public func rotated(size: Int, by rotation: OccupyRotation) -> OccupyPlacement {
        guard rotation != .upright else { return self }
        var turned: [CellKey: String] = [:]
        for (key, letter) in tiles { turned[rotateKey(key, size: size, by: rotation)] = letter }
        return OccupyPlacement(
            tiles: turned, borrowed: borrowed.map { rotateKey($0, size: size, by: rotation) })
    }
}

/// Why a game ended.
public enum OccupyEnd: String, Codable, Equatable {
    /// The clock ran out.
    case clock
    /// Nobody placed a word for `OCCUPY_STALL_SECONDS`.
    case stall
    /// Everyone else left.
    case field
}

/// The whole shared board, owned by the host and broadcast on every change.
public struct OccupyState: Codable, Equatable {
    /// The board is `size` × `size`, from the origin.
    public var size: Int
    /// Player ids by seat.
    public var seats: [String]
    public var board: TileMap
    /// Which seat owns each tile.
    public var owners: [CellKey: Int]
    /// Per seat: whether the opener is down.
    public var opened: [Bool]
    /// Per seat: the value of the tiles they own.
    public var scores: [Int]
    /// Per seat: when their score last changed, on the host's clock. Only
    /// ever compared with each other, so the clock's domain doesn't matter.
    public var settledAt: [Double]
    public var end: OccupyEnd?

    public init(
        size: Int, seats: [String], board: TileMap = TileMap(), owners: [CellKey: Int] = [:],
        opened: [Bool]? = nil, scores: [Int]? = nil, settledAt: [Double]? = nil,
        end: OccupyEnd? = nil
    ) {
        self.size = size
        self.seats = seats
        self.board = board
        self.owners = owners
        self.opened = opened ?? [Bool](repeating: false, count: seats.count)
        self.scores = scores ?? [Int](repeating: 0, count: seats.count)
        self.settledAt = settledAt ?? [Double](repeating: 0, count: seats.count)
        self.end = end
    }

    public var bounds: Bounds { Bounds(size: size) }

    public func seat(of player: String) -> Int? {
        seats.firstIndex(of: player)
    }

    public func startCell(seat: Int) -> Cell {
        occupyStartCell(seat: seat, size: size)
    }
}

// MARK: - Value

/// What every tile on the board is worth: the length of the longest word it
/// sits in. A tile in no word at all — which the rules never allow to land —
/// is worth one.
public func occupyTileValues(_ board: TileMap) -> [CellKey: Int] {
    var values: [CellKey: Int] = [:]
    for key in board.keys { values[key] = 1 }
    for run in extractRuns(board) {
        for cell in run.cells {
            values[cell] = max(values[cell] ?? 1, run.cells.count)
        }
    }
    return values
}

/// Each seat's score: the value of the tiles it owns.
public func occupyScores(board: TileMap, owners: [CellKey: Int], seats: Int) -> [Int] {
    var scores = [Int](repeating: 0, count: seats)
    let values = occupyTileValues(board)
    for (key, seat) in owners where seat >= 0 && seat < seats {
        scores[seat] += values[key] ?? 0
    }
    return scores
}

/// How many quadrants each seat holds — a quadrant goes to whoever owns the
/// most tiles in it, and to nobody on a tie.
public func occupyQuadrantsHeld(owners: [CellKey: Int], size: Int, seats: Int) -> [Int] {
    var counts = [[Int]](repeating: [Int](repeating: 0, count: seats), count: 4)
    for (key, seat) in owners where seat >= 0 && seat < seats {
        guard let quadrant = occupyQuadrant(of: parseKey(key), size: size) else { continue }
        counts[quadrant][seat] += 1
    }
    var held = [Int](repeating: 0, count: seats)
    for quadrant in counts {
        guard let top = quadrant.max(), top > 0 else { continue }
        let leaders = quadrant.indices.filter { quadrant[$0] == top }
        if leaders.count == 1 { held[leaders[0]] += 1 }
    }
    return held
}

// MARK: - The referee

/// Every way a placement can be turned down, with what to tell the player.
public enum OccupyRefusal: Error, Equatable {
    case notSeated
    case nothingPlaced
    case badLetter(String)
    case offTheBoard(CellKey)
    /// Someone got there first — the one refusal a client can't see coming.
    case taken(CellKey)
    case nothingToBorrow(CellKey)
    case notInALine
    case notAWord([String])
    case mustBorrow
    case openerOffStart

    public var message: String {
        switch self {
        case .notSeated: return "You’re not in this game."
        case .nothingPlaced: return "Nothing to place."
        case let .badLetter(letter): return "\(letter.uppercased()) isn’t a letter."
        case .offTheBoard: return "That runs off the board."
        case .taken: return "Someone got there first."
        case .nothingToBorrow: return "There’s no letter there to borrow."
        case .notInALine: return "A word has to lie in a line."
        case let .notAWord(words):
            let names = words.map { $0.uppercased() }
            return names.count == 1
                ? "\(names[0]) isn’t a word"
                : "\(names.joined(separator: ", ")) aren’t words"
        case .mustBorrow: return "Borrow a letter that’s already down."
        case .openerOffStart: return "Your first word has to cover your start square."
        }
    }
}

/// Land a word: judge it against the board as it stands, and return the
/// board with it down — or say why not. The host runs this on every
/// placement that arrives; a client runs it on its own the moment the word
/// is let go of, which is what makes the word appear at once and the host's
/// answer a formality unless somebody beat them to a square.
///
/// `now` stamps the seats whose scores change, for the tiebreak.
public func occupyApply(
    _ placement: OccupyPlacement, seat: Int, at now: Double, to state: OccupyState,
    isWord: (String) -> Bool
) throws -> OccupyState {
    guard state.seats.indices.contains(seat) else { throw OccupyRefusal.notSeated }
    guard !placement.tiles.isEmpty else { throw OccupyRefusal.nothingPlaced }

    var next = state
    let bounds = state.bounds

    // Every new tile lands on an empty square inside the board.
    for (key, letter) in placement.tiles {
        guard TileMap.isValidKey(key) else { throw OccupyRefusal.offTheBoard(key) }
        let cell = parseKey(key)
        guard bounds.contains(row: cell.row, col: cell.col) else {
            throw OccupyRefusal.offTheBoard(key)
        }
        guard letter.count == 1, let ch = letter.first, ch >= "a", ch <= "z" else {
            throw OccupyRefusal.badLetter(letter)
        }
        guard state.board[key] == nil else { throw OccupyRefusal.taken(key) }
    }

    // Every borrowed square already holds a letter.
    for key in placement.borrowed {
        guard TileMap.isValidKey(key), state.board[key] != nil else {
            throw OccupyRefusal.nothingToBorrow(key)
        }
        guard placement.tiles[key] == nil else { throw OccupyRefusal.taken(key) }
    }

    // The opener is the one word placed by fiat, and only from home.
    if placement.borrowed.isEmpty {
        let start = keyOf(state.startCell(seat: seat).row, state.startCell(seat: seat).col)
        guard !state.opened[seat], placement.tiles[start] != nil else {
            throw state.opened[seat] ? OccupyRefusal.mustBorrow : OccupyRefusal.openerOffStart
        }
    }

    for (key, letter) in placement.tiles { next.board[key] = letter }

    // One word: the placed and borrowed squares share a row or a column, and
    // nothing along it between them is empty.
    let cells = (Array(placement.tiles.keys) + placement.borrowed).map(parseKey)
    if cells.count > 1 {
        let rows = Set(cells.map(\.row))
        let cols = Set(cells.map(\.col))
        guard rows.count == 1 || cols.count == 1 else { throw OccupyRefusal.notInALine }
        if rows.count == 1 {
            let row = cells[0].row
            for col in cells.map(\.col).min()!...cells.map(\.col).max()! {
                guard next.board[keyOf(row, col)] != nil else { throw OccupyRefusal.notInALine }
            }
        } else {
            let col = cells[0].col
            for row in cells.map(\.row).min()!...cells.map(\.row).max()! {
                guard next.board[keyOf(row, col)] != nil else { throw OccupyRefusal.notInALine }
            }
        }
    }

    // Only real words go down — read either way along the line, since every
    // seat writes toward the middle in its own frame (`occupyIsWord`).
    let touched = Array(placement.tiles.keys) + placement.borrowed
    let runs = runsTouching(touched, in: next.board)
    guard !runs.isEmpty else { throw OccupyRefusal.notAWord(placement.tiles.values.sorted()) }
    let bad = runs.filter {
        $0.word.count < MIN_WORD_LENGTH || !occupyIsWord($0.word, isWord: isWord)
    }
    guard bad.isEmpty else { throw OccupyRefusal.notAWord(bad.map(\.word)) }

    for key in placement.tiles.keys { next.owners[key] = seat }
    // Capture by crossing: the borrowed letter is the borrower's now.
    for key in placement.borrowed { next.owners[key] = seat }
    next.opened[seat] = true

    let scores = occupyScores(board: next.board, owners: next.owners, seats: state.seats.count)
    for index in scores.indices where scores[index] != next.scores[index] {
        next.settledAt[index] = now
    }
    next.scores = scores
    return next
}

// MARK: - Standings and the end

public struct OccupyStanding: Equatable {
    public var seat: Int
    /// Competition ranking: tied seats share a rank, and the next rank skips
    /// past them (1, 2, 2, 4).
    public var rank: Int

    public init(seat: Int, rank: Int) {
        self.seat = seat
        self.rank = rank
    }
}

/// The field ranked, best first: by value, then quadrants held, then whoever
/// reached their score first. Seats in `left` sit at the bottom whatever
/// they own — a game can't be won by walking out of it.
public func occupyRanking(_ state: OccupyState, left: Set<Int> = []) -> [OccupyStanding] {
    let held = occupyQuadrantsHeld(owners: state.owners, size: state.size, seats: state.seats.count)
    func key(_ seat: Int) -> (Int, Int, Int, Double) {
        (left.contains(seat) ? 1 : 0, -state.scores[seat], -held[seat], state.settledAt[seat])
    }
    func before(_ a: Int, _ b: Int) -> Bool {
        let ka = key(a)
        let kb = key(b)
        if ka.0 != kb.0 { return ka.0 < kb.0 }
        if ka.1 != kb.1 { return ka.1 < kb.1 }
        if ka.2 != kb.2 { return ka.2 < kb.2 }
        return ka.3 < kb.3
    }
    let order = Array(state.seats.indices).sorted(by: before)
    var ranked: [OccupyStanding] = []
    for (index, seat) in order.enumerated() {
        let tied = index > 0 && key(seat) == key(order[index - 1])
        ranked.append(OccupyStanding(seat: seat, rank: tied ? ranked[index - 1].rank : index + 1))
    }
    return ranked
}

/// The seat that took the game, or nil for a dead heat.
public func occupyWinner(_ state: OccupyState, left: Set<Int> = []) -> Int? {
    let ranking = occupyRanking(state, left: left)
    let leaders = ranking.filter { $0.rank == 1 }
    return leaders.count == 1 ? leaders[0].seat : nil
}

/// How long the board has been quiet for the stall rule's purposes: the
/// time since the last word landed, or since the grace ran out, whichever is
/// later — so a slow opening can't end the game the moment the grace does.
public func occupyQuiet(elapsed: Double, sinceLastWord: Double) -> Double {
    min(sinceLastWord, elapsed - OCCUPY_GRACE_SECONDS)
}

/// Whether the game is over, `elapsed` seconds in and `sinceLastWord` seconds
/// after the last word landed — and why.
public func occupyEnd(elapsed: Double, sinceLastWord: Double, players: Int) -> OccupyEnd? {
    if elapsed >= Double(occupySeconds(players: players)) { return .clock }
    if occupyQuiet(elapsed: elapsed, sinceLastWord: sinceLastWord) >= OCCUPY_STALL_SECONDS {
        return .stall
    }
    return nil
}

/// Seconds until the stall rule ends the game, once that's close enough to
/// show — nil while the grace holds it off or the board is busy.
public func occupyStallSecondsLeft(elapsed: Double, sinceLastWord: Double) -> Double? {
    let left = OCCUPY_STALL_SECONDS - occupyQuiet(elapsed: elapsed, sinceLastWord: sinceLastWord)
    guard left <= OCCUPY_STALL_WARNING_SECONDS else { return nil }
    return max(0, left)
}
