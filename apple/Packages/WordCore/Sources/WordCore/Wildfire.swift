/// Wildfire: Solo, with a board that fights back.
///
/// New on Apple platforms, with no counterpart in the web game. The letters
/// keep arriving exactly as they do in Endless; what changes is that cells
/// catch fire, and an unanswered fire eats the board.
///
/// ## No health bar
///
/// A burnt tile comes back to your pile, and the pile is already the only
/// pressure the app's Solo has: reach `PILE_LIMIT` tiles in hand and the game
/// ends on the spot. So fire kills through the rule the player already knows,
/// with no second failure state and no new number on screen — and it is
/// priced in the currency they are already watching. "Three tiles burned"
/// needs no explanation; it is three more on the gauge, and the gauge is the
/// game. It also means fire can end a game outright, which is what gives an
/// ignored fire its weight.
///
/// ## One heartbeat
///
/// Fire runs on the round clock Endless already keeps (`endlessDripSeconds`).
/// At each round boundary, in order: tiles land, then `wildfireAdvance` runs,
/// then the pile is measured against its limit. So everything gets exactly one
/// round of grace — a cell that catches now burns at the end of the next
/// round — and the mode has one pulse with three consequences rather than two
/// clocks to track.
///
/// ## The rules in one breath
///
///  - Fire catches on **empty** cells next to tiles already down. Never in
///    open space: the board has to stay connected, so a fire you cannot build
///    next to is a fire with no legal answer.
///  - **Put it out** by playing a tile on it or beside it, any time before it
///    resolves. That pays `WILDFIRE_DOUSE_BONUS`, which is the difference
///    between a mechanic that reads as an opportunity and one that reads as a
///    tax.
///  - **Leave it** and at the end of the round it scars its own cell — dead
///    ground, forever — takes one of the tiles beside it back to your pile,
///    and spreads to a neighbouring cell. A word with a tile taken out of it
///    is broken, and its points go with it; the app's words are permanent,
///    but fire is not the player taking one back.
///  - Scars are the one thing fire will not cross, so a fire that walks into
///    old burnt ground dies out. The places you lost tiles are the places it
///    cannot go later.
///
/// Scarring is proportional to how badly the game is going: answer your fires
/// and the board stays whole, drown and it closes in around you. That is the
/// death spiral, and it is also why late Wildfire looks nothing like early
/// Wildfire — the open plain closes up and words have to thread between the
/// holes.
///
/// Everything here is pure and testable: state in, state out, with the RNG
/// injected. The fire itself is `Codable`, so a game restored across process
/// death comes back with the cells that were alight and the ground already
/// lost — the state is saved rather than replayed, and the RNG does not have
/// to be rewound to match.

/// Everything fire has done to a board.
///
/// Fires carry no age, because they never need one: a fire is lit at the end
/// of one round and resolves at the end of the next, so everything alight when
/// `wildfireAdvance` runs has had exactly its round of grace. That makes the
/// rule the player learns a very short one — **every fire you can see burns at
/// the end of this round unless you put it out** — and it makes the state a
/// list of cells rather than a little simulation.
public struct Wildfire: Equatable, Codable {
    /// Cells alight, in the order they caught. The order is part of the
    /// contract: a saved game resumes with the fires it had, in the order the
    /// board drew them.
    public var fires: [CellKey]
    /// Dead ground. Nothing may be placed here again, and fire will not cross
    /// it.
    public var scars: Set<CellKey>

    public init(fires: [CellKey] = [], scars: Set<CellKey> = []) {
        self.fires = fires
        self.scars = scars
    }

    public var isEmpty: Bool { fires.isEmpty && scars.isEmpty }

    public func isBurning(_ key: CellKey) -> Bool {
        fires.contains(key)
    }

    public func isScarred(_ key: CellKey) -> Bool {
        scars.contains(key)
    }
}

/// Points for putting a fire out. Worth about a four-letter word, so
/// answering the board is never a pure cost.
public let WILDFIRE_DOUSE_BONUS = 10

/// Fires lit per round to begin with, and the ceiling however long you last.
public let WILDFIRE_FIRST_IGNITIONS = 1
public let WILDFIRE_MAX_IGNITIONS = 3

/// How many rounds a given number of fires lasts before another joins in.
/// The same shape as `endlessDripTiles` — the escalation the player already
/// feels in the batch size, felt again in the board.
public let WILDFIRE_IGNITION_ROUNDS = 6

/// Extra room in the pile for a game playing under fire.
///
/// Burnt tiles feed the same gauge the drip feeds, so the limit is under
/// attack from two sides now; holding it where Solo holds it would make
/// Wildfire a mode about the gauge rather than about the fire. Roughly a
/// round's worth of burning, so falling behind still costs you — it just
/// doesn't cost you the game before you have seen what fire does.
public let WILDFIRE_PILE_RELIEF = 4

/// The pile limit a game under `hazard` plays to, given the limit its mode
/// would otherwise use.
///
/// Takes the base limit rather than naming one, because the limit is the
/// app's to set (`PILE_LIMIT` in `GameModel`) and the relief is the rule's.
public func hazardPileLimit(_ base: Int, _ hazard: SoloHazard) -> Int {
    hazard == .wildfire ? base + WILDFIRE_PILE_RELIEF : base
}

/// How many fires the round after `intervalsElapsed` drip intervals lights:
/// one to begin with, another every `WILDFIRE_IGNITION_ROUNDS` rounds, never
/// more than `WILDFIRE_MAX_IGNITIONS`. A function of the round index alone, so
/// a paused or resumed game lights the same fires as one played straight
/// through.
public func wildfireIgnitions(_ intervalsElapsed: Int) -> Int {
    let grown = max(0, intervalsElapsed) / WILDFIRE_IGNITION_ROUNDS
    return min(WILDFIRE_MAX_IGNITIONS, WILDFIRE_FIRST_IGNITIONS + grown)
}

/// The four orthogonal neighbours of a cell, in a fixed order.
func neighbours(of key: CellKey) -> [CellKey] {
    let cell = parseKey(key)
    return [
        keyOf(cell.row - 1, cell.col),
        keyOf(cell.row + 1, cell.col),
        keyOf(cell.row, cell.col - 1),
        keyOf(cell.row, cell.col + 1),
    ]
}

/// Where a fire could catch: empty cells touching a tile that's already down,
/// minus dead ground and cells already alight.
///
/// Enumerated by walking the board in its own insertion order and taking each
/// tile's neighbours in a fixed order, so the candidate list — which the RNG
/// indexes into — is the same list every time.
func wildfireCandidates(board: TileMap, fire: Wildfire) -> [CellKey] {
    var seen = Set<CellKey>()
    var candidates: [CellKey] = []
    for key in board.keys {
        for neighbour in neighbours(of: key) {
            guard !board.contains(neighbour),
                  !fire.isScarred(neighbour),
                  !fire.isBurning(neighbour),
                  !seen.contains(neighbour)
            else { continue }
            seen.insert(neighbour)
            candidates.append(neighbour)
        }
    }
    return candidates
}

/// What one round of fire did.
public struct WildfireRound: Equatable {
    public var fire: Wildfire
    /// Cells whose tiles the fire took, in the order it took them. Remove
    /// these from the board.
    public var burnt: [CellKey]
    /// The letters those tiles carried, in `burnt` order — these go back to
    /// the pile.
    public var returned: [String]
    /// Cells that caught this round, whether by spreading or freshly lit.
    public var lit: [CellKey]
    /// Cells that turned to dead ground this round.
    public var scarred: [CellKey]

    public init(
        fire: Wildfire,
        burnt: [CellKey],
        returned: [String],
        lit: [CellKey],
        scarred: [CellKey]
    ) {
        self.fire = fire
        self.burnt = burnt
        self.returned = returned
        self.lit = lit
        self.scarred = scarred
    }
}

/// Advance the fire one round: resolve everything alight, then light
/// `ignitions` new cells.
///
/// Everything alight resolves, because everything alight was lit by the
/// previous round's call — the fires this one lights are appended afterwards
/// and are not touched again until next time. That is the round of grace, and
/// it needs no bookkeeping to enforce.
///
/// Resolving happens first, against the board as it stands, so a tile the
/// player placed during the round has already had its chance to put a fire out
/// (see `wildfireDouse`): the board handed in here is the board after the
/// round's play and after the round's tiles have landed.
public func wildfireAdvance(
    _ fire: Wildfire,
    board: TileMap,
    ignitions: Int,
    rng: () -> Double
) -> WildfireRound {
    var next = fire
    var burnt: [CellKey] = []
    var returned: [String] = []
    var lit: [CellKey] = []
    var scarred: [CellKey] = []

    // Walk the fires in the order they caught, and rebuild the list as we go
    // so the cells they spread to keep that same order.
    var spreadTo: [CellKey] = []
    for burning in next.fires {
        // Dead ground, and fire will not cross it again.
        next.scars.insert(burning)
        scarred.append(burning)

        // It takes one of the tiles beside it back to the pile. Choosing at
        // random rather than always reaching the same way stops a fire being
        // answerable by rote.
        let touching = neighbours(of: burning).filter { board.contains($0) && !burnt.contains($0) }
        if !touching.isEmpty {
            let victim = touching[min(Int(rng() * Double(touching.count)), touching.count - 1)]
            burnt.append(victim)
            returned.append(board[victim]!)
        }

        // And it moves on — to open ground beside a tile if there is any, so
        // fire walks toward the board rather than off into nothing.
        // Never onto a cell another fire is sitting on: every one of those is
        // scarred before this loop is done, and a cell cannot be both alight
        // and dead ground. `fire.fires` is the list as it came in, so this
        // covers the ones this pass hasn't reached yet as well as the ones it
        // has.
        let open = neighbours(of: burning).filter {
            !board.contains($0) && !next.scars.contains($0)
                && !fire.fires.contains($0) && !spreadTo.contains($0)
        }
        let hungry = open.filter { cell in neighbours(of: cell).contains { board.contains($0) } }
        let spread = hungry.isEmpty ? open : hungry
        if !spread.isEmpty {
            let cell = spread[min(Int(rng() * Double(spread.count)), spread.count - 1)]
            spreadTo.append(cell)
            lit.append(cell)
        }
        // Nowhere to go — ringed by dead ground or tiles — and the fire is out.
    }
    next.fires = spreadTo

    // Then the round's new fires. Candidates are recomputed against the board
    // and the fire as they now stand, so nothing lights on ground that just
    // scarred or a cell that just caught.
    for _ in 0..<max(0, ignitions) {
        let candidates = wildfireCandidates(board: board, fire: next)
        guard !candidates.isEmpty else { break }
        let cell = candidates[min(Int(rng() * Double(candidates.count)), candidates.count - 1)]
        next.fires.append(cell)
        lit.append(cell)
    }

    return WildfireRound(fire: next, burnt: burnt, returned: returned, lit: lit, scarred: scarred)
}

/// Put out every fire the cells just played touch — on the cell itself or
/// orthogonally beside it.
///
/// Adjacency rather than exact coverage on purpose: needing a tile on the
/// burning cell would mean losing to the letters you happened to hold, and a
/// fire should cost you a decision, not a coin flip. Beside it is forgiving
/// and still tells you where to play, which is the entire point of the mode.
public func wildfireDouse(_ fire: Wildfire, played cells: some Sequence<CellKey>) -> (fire: Wildfire, doused: [CellKey]) {
    var reach = Set<CellKey>()
    for key in cells {
        reach.insert(key)
        for neighbour in neighbours(of: key) { reach.insert(neighbour) }
    }
    var next = fire
    let doused = next.fires.filter { reach.contains($0) }
    next.fires.removeAll { reach.contains($0) }
    return (next, doused)
}

/// Points for a round's dousing.
public func wildfireDouseBonus(_ doused: Int) -> Int {
    max(0, doused) * WILDFIRE_DOUSE_BONUS
}

/// Whether a cell can hold a tile. Dead ground never can — this is what the
/// placement code has to ask before letting a word land.
public func wildfireAllows(_ fire: Wildfire, _ key: CellKey) -> Bool {
    !fire.isScarred(key)
}

/// Whether a whole word could land: every cell it would occupy has to be live
/// ground.
public func wildfireAllows(_ fire: Wildfire, cells: some Sequence<CellKey>) -> Bool {
    cells.allSatisfy { !fire.isScarred($0) }
}
