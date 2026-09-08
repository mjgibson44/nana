/// Prize cells: Solo, with something on the board worth racing for.
///
/// New on Apple platforms, with no counterpart in the web game. It replaces
/// Wildfire, and keeps the half of Wildfire that worked.
///
/// ## What Wildfire got right, and what it got wrong
///
/// Fire's good idea was that the board should give you somewhere to *go* —
/// Solo's freedom is calm, and calm is also why a long run has no shape.
/// Its bad idea was that the somewhere was a punishment. An unanswered fire
/// took a tile, scarred the ground and spread, so the mode's whole feedback
/// loop was negative: play well and nothing happens, play badly and the board
/// closes in. That is a death spiral wearing a mechanic's clothes, and it
/// made the sensible line "ignore the fire and keep building" for exactly as
/// long as you could afford to.
///
/// A prize inverts the sign and keeps the geometry. A cell lights up, it is
/// somewhere specific to reach, it is on a clock — and reaching it *pays*.
/// The pressure comes from the same place it always did (the pile, the drip),
/// and the board's job is now to offer you a decision rather than to punish
/// one. Ignoring a prize is a real choice with a real cost, but the cost is
/// an opportunity missed, which is a thing players chase rather than resent.
///
/// ## The rules in one breath
///
///  - A prize appears every `PRIZE_SPAWN_SECONDS` on an **empty cell within
///    `PRIZE_REACH` of a tile already down**, never more than
///    `PRIZE_MAX_LIVE` at a time. Close enough to reach with one word; far
///    enough that reaching it is a decision about where to build.
///  - It lives `PRIZE_SECONDS` and then vanishes, costing nothing.
///  - **Claim it by landing a tile on that exact square.** Exact, not
///    adjacent — the opposite of dousing a fire, and for the opposite reason:
///    a punishment must be answerable with what you happen to hold, while a
///    reward should be earned by putting a letter where you meant to.
///  - **What it pays decays with its own clock.** Full value the instant it
///    appears, sliding to a floor as the timer runs out. The prize is
///    therefore never "free points later" — it is a bid to change what you
///    were going to play *right now*, and the longer you think the less it is
///    worth. That is the whole mechanic; everything else is bookkeeping.
///
/// ## Two payouts, one rule
///
/// `PrizeKind` is what a claim buys, and it is the only difference between
/// the modifiers on the setup sheet:
///
///  - **Gold Rush** (`.points`) pays points — `GOLD_TOP_POINTS` down to
///    `GOLD_FLOOR_POINTS`. A scoring modifier: it changes what a good run is
///    worth without changing whether you survive it.
///  - **Salvage** (`.relief`) pays tiles off your pile — `SALVAGE_TOP_TILES`
///    down to `SALVAGE_FLOOR_TILES`. A survival modifier: it changes how long
///    you last without changing what a word is worth.
///
/// Same spawn rule, same clock, same claim, same decay — so the two are one
/// mechanic the player learns once, and the sheet is choosing what the board
/// is offering rather than choosing a different game.
///
/// ## One clock, and it is not the drip's
///
/// Wildfire rode the round boundary, which meant it had no clock of its own
/// and cost nothing to reason about. Prizes cannot: a 20-second life against
/// a 15-second round would make every prize's deadline land at an arbitrary
/// point inside a round, and the player would be reading two counters that
/// drift against each other. So a prize carries **its own seconds left**, and
/// `prizeAdvance` is handed the elapsed time since it last ran.
///
/// Storing seconds left rather than a deadline is the same decision
/// `SavedSoloGame` makes about the round clock, for the same reasons: a
/// paused game must not lose prizes to a pause, and a game restored tomorrow
/// must not find them all expired on arrival. The caller simply stops calling
/// while the clock is held.
///
/// Everything here is pure and testable: state in, state out, with the RNG
/// injected and the elapsed time passed rather than read. `PrizeField` is
/// `Codable`, so a game restored across process death comes back with the
/// cells that were lit and the time they had left.

/// What claiming a prize buys.
public enum PrizeKind: String, Equatable, Codable, Sendable {
    /// Gold Rush: points, straight into the banked bonus.
    case points
    /// Salvage: tiles taken off the pile.
    case relief
}

/// One lit cell, and how long it has.
///
/// The seconds are the prize's whole state: what it is worth is a function of
/// them (`prizeValue`), so there is no value to keep in step with a clock and
/// no way for the two to disagree.
public struct Prize: Equatable, Codable, Sendable {
    public var key: CellKey
    public var secondsLeft: Double

    public init(key: CellKey, secondsLeft: Double = PRIZE_SECONDS) {
        self.key = key
        self.secondsLeft = secondsLeft
    }
}

/// Every prize on the board, and the clock that puts the next one there.
public struct PrizeField: Equatable, Codable, Sendable {
    /// Lit cells, in the order they appeared. The order is part of the
    /// contract: a saved game resumes with the prizes it had, in the order
    /// the board drew them.
    public var prizes: [Prize]
    /// Seconds until the next one appears.
    public var untilNextSpawn: Double
    /// How many have appeared this game. Not a statistic — it is what the
    /// caller seeds the spawn RNG with, so a game restored from a blob goes
    /// on lighting the cells it would have lit rather than replaying the ones
    /// it already did.
    public var spawns: Int

    public init(
        prizes: [Prize] = [],
        untilNextSpawn: Double = PRIZE_FIRST_SPAWN_SECONDS,
        spawns: Int = 0
    ) {
        self.prizes = prizes
        self.untilNextSpawn = untilNextSpawn
        self.spawns = spawns
    }

    public var isEmpty: Bool { prizes.isEmpty }

    public func prize(at key: CellKey) -> Prize? {
        prizes.first { $0.key == key }
    }

    public func isLit(_ key: CellKey) -> Bool {
        prizes.contains { $0.key == key }
    }
}

/// How long a prize lives once it appears.
///
/// Twenty seconds is long enough to finish the word already in hand and then
/// build the one that reaches, and short enough that it cannot be banked for
/// later. It is deliberately *not* a multiple of either drip round, so a
/// prize's deadline moves around inside the round rather than always falling
/// at the same moment.
public let PRIZE_SECONDS = 20.0

/// How often a new one appears, and the wait for the very first.
///
/// The first is shorter so a game shows what the modifier does before the
/// opening phase is over, rather than a minute into a run.
public let PRIZE_SPAWN_SECONDS = 15.0
public let PRIZE_FIRST_SPAWN_SECONDS = 8.0

/// How many may be lit at once.
///
/// Two, so there is sometimes a choice between them and never a scavenger
/// hunt: with a 20-second life and a 15-second gap the board usually holds
/// one and occasionally holds two, which is the rhythm this is tuned for.
public let PRIZE_MAX_LIVE = 2

/// How far from the nearest tile a prize may appear, in Chebyshev distance.
///
/// Two. One would be a prize claimed by accident by whatever word you were
/// already playing, which pays for nothing. Three needs a word built in a
/// particular direction *and* of a particular length, which inside twenty
/// seconds is mostly a prize you watch expire. Two asks for a word that
/// crosses a letter and reaches one square past it — a real decision about
/// where to build, answerable with an ordinary hand.
///
/// The most likely thing on this page to want tuning after a playtest.
public let PRIZE_REACH = 2

/// Gold Rush's payout, full price down to floor.
///
/// A hundred is a lot on purpose — `wordScore` is triangular, so it is worth
/// roughly a seven-letter word, which is what makes a gold cell able to
/// outbid the word already in your hand. The floor is what a claim in the
/// last second is still worth: small, but never nothing, so a late scramble
/// is rewarded rather than mocked.
public let GOLD_TOP_POINTS = 100
public let GOLD_FLOOR_POINTS = 10

/// Salvage's payout, in tiles off the pile.
///
/// Ten is most of a batch at any pace and a third of a full pile — enough
/// that a claim visibly rescues a losing position, which is the only reason
/// to have a survival modifier at all. The floor is one, so the last second
/// still buys something.
public let SALVAGE_TOP_TILES = 10
public let SALVAGE_FLOOR_TILES = 1

/// What a prize of `kind` pays with `secondsLeft` on it.
///
/// Linear from the full price at the instant it appears to the floor as it
/// vanishes. Linear rather than any curve because the player has to be able
/// to price it at a glance: half the time left is half the prize, and that
/// is a sentence rather than a graph.
public func prizeValue(_ kind: PrizeKind, secondsLeft: Double) -> Int {
    let share = secondsLeft.isFinite ? min(1, max(0, secondsLeft / PRIZE_SECONDS)) : 0
    let (floor, top) =
        switch kind {
        case .points: (GOLD_FLOOR_POINTS, GOLD_TOP_POINTS)
        case .relief: (SALVAGE_FLOOR_TILES, SALVAGE_TOP_TILES)
        }
    return floor + Int((Double(top - floor) * share).rounded())
}

/// What a prize pays right now.
public func prizeValue(_ kind: PrizeKind, _ prize: Prize) -> Int {
    prizeValue(kind, secondsLeft: prize.secondsLeft)
}

/// Where a prize could appear: empty cells within `PRIZE_REACH` of a tile
/// already down, minus the cells already lit.
///
/// Enumerated by walking the board in its own insertion order and taking each
/// tile's neighbourhood in a fixed order, so the candidate list — which the
/// RNG indexes into — is the same list every time.
func prizeCandidates(board: TileMap, field: PrizeField) -> [CellKey] {
    var seen = Set<CellKey>()
    var candidates: [CellKey] = []
    for key in board.keys {
        let cell = parseKey(key)
        for dRow in -PRIZE_REACH...PRIZE_REACH {
            for dCol in -PRIZE_REACH...PRIZE_REACH {
                let candidate = keyOf(cell.row + dRow, cell.col + dCol)
                guard !board.contains(candidate),
                    !field.isLit(candidate),
                    !seen.contains(candidate)
                else { continue }
                seen.insert(candidate)
                candidates.append(candidate)
            }
        }
    }
    return candidates
}

/// What one tick did to the field.
public struct PrizeRound: Equatable {
    public var field: PrizeField
    /// Cells that ran out of time this tick. Nothing is owed for these — a
    /// prize left alone costs the player only what they could have had.
    public var expired: [CellKey]
    /// Cells lit this tick.
    public var lit: [CellKey]

    public init(field: PrizeField, expired: [CellKey] = [], lit: [CellKey] = []) {
        self.field = field
        self.expired = expired
        self.lit = lit
    }
}

/// Advance the field by `delta` seconds: age everything lit, drop what ran
/// out, then light a new cell if one is due.
///
/// At most one cell is lit per call however large `delta` is, and the spawn
/// clock is *set* rather than decremented past zero. That is what makes a
/// long gap — an app suspended in a pocket, a game picked up tomorrow —
/// arrive at an empty board with one prize due shortly, instead of a
/// backlogged burst of them all at once. The elapsed time is the caller's to
/// measure and the caller's to withhold: a held clock simply doesn't call.
public func prizeAdvance(
    _ field: PrizeField,
    board: TileMap,
    delta: Double,
    rng: () -> Double
) -> PrizeRound {
    guard delta.isFinite, delta > 0 else { return PrizeRound(field: field) }
    var next = field
    var expired: [CellKey] = []
    var lit: [CellKey] = []

    var surviving: [Prize] = []
    for prize in next.prizes {
        let left = prize.secondsLeft - delta
        if left > 0 {
            surviving.append(Prize(key: prize.key, secondsLeft: left))
        } else {
            expired.append(prize.key)
        }
    }
    next.prizes = surviving

    next.untilNextSpawn -= delta
    if next.untilNextSpawn <= 0 {
        // Due either way, so the clock is reset even when there is nowhere to
        // put one — an empty board must not build up a debt of spawns it pays
        // out the moment a word lands.
        next.untilNextSpawn = PRIZE_SPAWN_SECONDS
        if next.prizes.count < PRIZE_MAX_LIVE {
            let candidates = prizeCandidates(board: board, field: next)
            if !candidates.isEmpty {
                let index = min(Int(rng() * Double(candidates.count)), candidates.count - 1)
                let key = candidates[index]
                next.prizes.append(Prize(key: key))
                next.spawns += 1
                lit.append(key)
            }
        }
    }

    return PrizeRound(field: next, expired: expired, lit: lit)
}

/// Claim every prize the cells just played land on.
///
/// Exact coverage, unlike `wildfireDouse`'s adjacency, and deliberately: a
/// fire had to be answerable with the letters you happened to hold or it was
/// a coin flip, whereas a prize you stumble onto has asked nothing of you.
/// The claim is the point — a tile on that square, because you went there.
public func prizeClaim(
    _ field: PrizeField, covering cells: some Sequence<CellKey>
) -> (field: PrizeField, claimed: [Prize]) {
    let landed = Set(cells)
    guard !landed.isEmpty else { return (field, []) }
    var next = field
    let claimed = next.prizes.filter { landed.contains($0.key) }
    next.prizes.removeAll { landed.contains($0.key) }
    return (next, claimed)
}

/// What a round's claims are worth, all together.
public func prizeClaimValue(_ kind: PrizeKind, _ claimed: [Prize]) -> Int {
    claimed.reduce(0) { $0 + prizeValue(kind, $1) }
}
