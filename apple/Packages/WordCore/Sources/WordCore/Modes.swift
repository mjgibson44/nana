/// Game modes. Ported from `src/game/modes.ts`.
///
/// One board and one set of rules for building words, played three ways:
///
///  - Endless: no levels. New tiles keep arriving on a clock; let too many
///    pile up loose and the game ends. Played solo — the Solo door — at
///    either of two paces, see `SoloPace`.
///  - Battle: a room of two to eight players on one shared deal. Placed
///    words are permanent, and every word you place scatters tiles across
///    your rivals. Overflow your pile and you're out; the last player
///    standing wins.
///  - Tutorial: a guided walk through placing words, at your own pace.

public enum GameMode: String, Sendable, Codable {
    case endless, battle, tutorial
    /// New on Apple platforms, with no counterpart in `modes.ts`: one fixed
    /// deal a day, identical for every player (plan §8.2, `DailyDeal.swift`).
    /// A deliberate product divergence, not a porting slip.
    case daily
    /// Also new on Apple platforms: two to four players on one fixed, shared
    /// board, fighting over the same squares (`Occupy.swift`).
    case occupy
}

/// How hard Solo leans on the player. Both paces are the same game — same
/// board, same loose limit, same clear bonus — and differ only in how long
/// the opening phase runs, how long a round is, and how many tiles a round
/// deals:
///
///  - `regular`: two minutes to open, then five-tile rounds of 45 seconds
///    tightening to 30, and batches that grow to seven.
///  - `fast`: one minute to open, then a 15-second round forever, starting at
///    three tiles and growing by one every eight rounds up to ten.
public enum SoloPace: String, CaseIterable, Sendable {
    case regular, fast
}

public struct ModeInfo {
    public let name: String
    public let tagline: String
    /// Short bullet lines for the explainer that fronts the mode's first game.
    public let details: [String]

    public init(name: String, tagline: String, details: [String]) {
        self.name = name
        self.tagline = tagline
        self.details = details
    }
}

/// The doors out of the home screen — the buttons that lead to a game.
/// Not the same list as GameMode: Solo raises a setup sheet for its pace on
/// the way in, while Battle and Occupy lead to a lobby before any game starts.
public enum GameDoor: String, CaseIterable {
    case solo, battle, occupy
}

public let SOLO_INFO = ModeInfo(
    name: "Solo",
    tagline: "Survive the ever-growing pile.",
    details: [
        "Tiles keep arriving on a clock — weave them in as they land",
        "Over 20 loose tiles when a round ends and you’re out",
        "Two speeds: Regular, or Fast for tiles arriving four times as quickly",
    ]
)

/// What the splash cards call each Solo pace.
public let PACE_NAMES: [SoloPace: String] = [
    .regular: "Solo · Regular",
    .fast: "Solo · Fast",
]

/// The Speed setting's tabs, in the order they're offered. What each pace
/// actually costs you is SOLO_INFO's business, on the card that fronts the
/// mode; here it's a two-way switch.
public let PACE_OPTIONS: [(pace: SoloPace, name: String)] = [
    (pace: .regular, name: "Regular"),
    (pace: .fast, name: "Fast"),
]

/// Battle's home-screen card. The rules in one breath: permanent words,
/// attack tiles split across the field, a hard pile limit, and the game runs
/// until one player is left. See `splitAttackTiles` for the split, and
/// `Battle.swift` for the elimination bookkeeping.
public let BATTLE_ROYALE_INFO = ModeInfo(
    name: "Battle",
    tagline: "Free-for-all. Last one standing wins (2–8 players).",
    details: [
        "Two to eight players, same tiles",
        "Words are permanent — attack tiles are split across your rivals",
        "Overflow 25 tiles and you’re out; outlast everyone to win",
    ]
)

/// Occupy's card: one board, capture by crossing, and a clock.
public let OCCUPY_INFO = ModeInfo(
    name: "Occupy",
    tagline: "One board. Hold the most of it when the clock runs out (2–4 players).",
    details: [
        "Everyone plays on the same board, from opposite corners",
        "Borrow a rival’s letter and it’s yours — every tile is worth its longest word",
        "Most value when the clock runs out wins; a stuck board ends early",
    ]
)

/// The card that offers the tutorial, before it starts. It fronts a first
/// player's very first game as well as the tutorial they pick deliberately, so
/// it reads as an offer either way — and either way it can be skipped.
public let TUTORIAL_INFO = ModeInfo(
    name: "Tutorial",
    tagline: "New here? Learn the game in three quick steps.",
    details: [
        "Place your first word",
        "Cross it on a shared letter",
        "Borrow a letter with the gap tile",
    ]
)

/// The Daily Deal's card. It leads with the thing that makes the mode work —
/// everyone gets the same letters — because that's the reason to come back
/// tomorrow, and the reason a score is worth comparing.
public let DAILY_DEAL_INFO = ModeInfo(
    name: "Daily Deal",
    tagline: "One deal a day. Same letters for everyone.",
    details: [
        "\(DailyRules.tileCount) tiles, no clock — take as long as you like",
        "Everybody in the world plays the same letters today",
        "One go per day; place every tile for a \(ALL_TILES_BONUS)-point bonus",
    ]
)

/// Which explainer each door raises the first time it's opened.
public let DOOR_INFO: [GameDoor: ModeInfo] = [
    .solo: SOLO_INFO,
    .battle: BATTLE_ROYALE_INFO,
    .occupy: OCCUPY_INFO,
]

// MARK: - Endless

/// Tiles in the opening Endless deal, at either pace.
public let ENDLESS_START_TILES = 20

/// The opening phase: this long to work the starting pile before tiles start
/// arriving — and before the loose-tile count switches on. The fast pace gives
/// you half as long for the same twenty tiles.
public let ENDLESS_INITIAL_SECONDS = 120
public let FAST_INITIAL_SECONDS = 60

/// The screw turns twice after the opening phase: five rounds of 45 seconds,
/// then the clock tightens to 30-second rounds — five of those at the small
/// batch, and after that every round deals the big batch forever.
public let ENDLESS_SLOW_SECONDS = 45
public let ENDLESS_FAST_SECONDS = 30

/// How many drip rounds run at the slower opening pace.
public let ENDLESS_SLOW_ROUNDS = 5

/// The batch size rounds start at, and how many rounds it lasts — the five
/// slow rounds plus the first five fast ones.
public let ENDLESS_SMALL_BATCH = 5
public let ENDLESS_SMALL_BATCH_ROUNDS = 10

/// The batch size every round deals once the small rounds are spent.
public let ENDLESS_BIG_BATCH = 7

/// The fast pace never touches its clock: every round after the opening
/// minute is fifteen seconds, and the batch is what grows instead.
public let FAST_DRIP_SECONDS = 15

/// The batch the fast pace opens on, and the one it tops out at.
public let FAST_SMALL_BATCH = 3
public let FAST_MAX_BATCH = 10

/// How many fast rounds a batch size lasts before growing by one — eight
/// fifteen-second rounds, so two minutes at each size.
public let FAST_BATCH_ROUNDS = 8

/// How long the opening phase runs at `pace`.
public func endlessInitialSeconds(_ pace: SoloPace) -> Int {
    pace == .fast ? FAST_INITIAL_SECONDS : ENDLESS_INITIAL_SECONDS
}

/// How long the wait for the next batch is, given how many drip intervals have
/// already run out. Regular: 45 seconds for the first five, 30 forever after.
/// Fast: fifteen seconds, always.
public func endlessDripSeconds(_ intervalsElapsed: Int, _ pace: SoloPace) -> Int {
    if pace == .fast { return FAST_DRIP_SECONDS }
    return intervalsElapsed < ENDLESS_SLOW_ROUNDS ? ENDLESS_SLOW_SECONDS : ENDLESS_FAST_SECONDS
}

/// How many tiles the batch landing after `intervalsElapsed` drip intervals
/// brings. Regular: five for each of the first ten rounds, then seven forever.
/// Fast: three to begin with, one more every eight rounds, and no more than
/// ten however long you last.
public func endlessDripTiles(_ intervalsElapsed: Int, _ pace: SoloPace) -> Int {
    if pace == .fast {
        let grown = max(0, intervalsElapsed) / FAST_BATCH_ROUNDS
        return min(FAST_MAX_BATCH, FAST_SMALL_BATCH + grown)
    }
    return intervalsElapsed < ENDLESS_SMALL_BATCH_ROUNDS ? ENDLESS_SMALL_BATCH : ENDLESS_BIG_BATCH
}

/// Clearing the pile — every tile placed and connected — feeds the board a
/// small fixed batch, whatever size the timed drops have grown to.
public let ENDLESS_CLEAR_TILES = 5

/// Points for having every tile placed on a fully connected, valid board.
public let ENDLESS_CONNECT_BONUS = 25

/// Loose tiles — in the pile, or on the board but not validly connected —
/// are the pressure gauge. Going over this limit is survivable; still being
/// over it when a drip round ends is what ends the game.
public let ENDLESS_LOOSE_LIMIT = 20

// MARK: - Battle

/// How many players a Battle seats. Two is the head-to-head floor; eight is
/// where a phone's header, the lobby roster and the attack arithmetic all
/// still breathe.
public let BATTLE_MIN_PLAYERS = 2
public let BATTLE_MAX_PLAYERS = 8

/// Tiles in each player's opening Battle deal.
public let BATTLE_START_TILES = 15

/// A Battle pile may never exceed this many tiles — one over and you're out.
public let BATTLE_PILE_LIMIT = 25

/// The pile counter starts pleading before the limit: flashing orange at a
/// medium blink from this many tiles…
public let BATTLE_PILE_WARN = 15

/// …and flashing red, faster, from this many.
public let BATTLE_PILE_URGENT = 20

/// How many rounds a battle has. The last one runs until it's decided.
public let BATTLE_ROUNDS = 3

/// Rounds one and two are this long; the final round has no clock.
public let BATTLE_ROUND_SECONDS = 180

/// How often the drip lands a tile (or several) in each player's pile.
public let BATTLE_DRIP_SECONDS = 20

/// How many tiles the drip brings per round: 1, then 2, then 4.
let BATTLE_DRIP_TILES = [1, 2, 4]

/// How hard words hit per round: attacks are ×1, then ×1.5, then ×2.
let BATTLE_ATTACK_MULTIPLIERS: [Double] = [1, 1.5, 2]

func clampRound(_ round: Int) -> Int {
    max(1, min(BATTLE_ROUNDS, round))
}

public func battleDripTiles(round: Int) -> Int {
    BATTLE_DRIP_TILES[clampRound(round) - 1]
}

public func battleAttackMultiplier(round: Int) -> Double {
    BATTLE_ATTACK_MULTIPLIERS[clampRound(round) - 1]
}

/// Which round a battle is in `seconds` into the game: rounds one and two are
/// `BATTLE_ROUND_SECONDS` each, and the final round runs forever.
public func battleRoundAt(seconds: Double) -> Int {
    // Clamp in Double space so a huge or infinite clock value degrades to a
    // valid round instead of trapping in the Int conversion — ±infinity
    // clamps exactly as in JS (+inf → final round, -inf → round 1). Only
    // NaN needs a guard (JS propagates it; Swift can't).
    guard !seconds.isNaN else { return 1 }
    let round = (seconds / Double(BATTLE_ROUND_SECONDS)).rounded(.down) + 1
    return Int(min(max(round, 1), Double(BATTLE_ROUNDS)))
}

/// How many tiles the drip numbered `dripIndex` (0-based) deals. Pure in the
/// index so every player — whose clocks may drift — draws identical batches
/// from the shared stream: drip k is drip k on every screen.
public func battleDripTilesAt(dripIndex: Int) -> Int {
    let at = (dripIndex + 1) * BATTLE_DRIP_SECONDS
    return battleDripTiles(round: battleRoundAt(seconds: Double(at)))
}

/// How many tiles placing a word sends across the field: nothing under four
/// letters, then one per letter past three — 4→1, 5→2, 6→3 — scaled up by the
/// round's multiplier and rounded to the nearest whole tile.
///
/// `grewFrom` lists the lengths of the words already on the board that this
/// word absorbed — the word it extends, or the two it bridges. Only the growth
/// is paid for: the new word's base value minus what the absorbed words were
/// worth, so stretching HEART to HEARTS earns the S, not the whole word again.
/// A word built from nothing (an empty list) earns its full value.
public func battleAttackTiles(wordLength: Int, round: Int, grewFrom: [Int] = []) -> Int {
    func base(_ length: Int) -> Int { max(0, length - 3) }
    let absorbed = grewFrom.reduce(0) { sum, length in sum + base(length) }
    let growth = max(0, base(wordLength) - absorbed)
    // JS Math.round is half-up; growth is never negative here.
    return Int((Double(growth) * battleAttackMultiplier(round: round) + 0.5).rounded(.down))
}

/// Split one attack across the rivals still standing. A word earns its
/// `battleAttackTiles` total once — but with up to seven targets, sending the
/// whole attack to each of them would multiply the pressure by the size of
/// the room. So the total is divided across the field: everyone takes the
/// fair floor, and the remainder lands one tile each on the targets starting
/// at `from` (wrapping round), so the caller can rotate who takes the odd
/// tile rather than always the same seat.
///
/// The shares always sum to the attack, so a 1-tile attack still lands
/// somewhere instead of rounding away to nothing — and as players fall, the
/// same words hit the survivors harder, which is the endgame tightening by
/// itself. With one rival left the whole attack lands on them, head-to-head.
public func splitAttackTiles(count: Double, targets: Int, from: Int = 0) -> [Int] {
    if !count.isFinite || targets <= 0 { return [] }
    // Unlike JS, Int(Double) traps on values past Int.max; a hostile or
    // corrupt count must degrade, not crash. Anything at this scale is
    // nonsense — cap it (the game layer clamps real attacks to 50 anyway).
    let floored = max(0, count.rounded(.down))
    let total = floored < 9_007_199_254_740_992 ? Int(floored) : Int.max
    let base = total / targets
    let extra = total % targets
    let start = ((from % targets) + targets) % targets
    var shares = [Int](repeating: base, count: targets)
    for i in 0..<extra { shares[(start + i) % targets] += 1 }
    return shares
}

// MARK: - shared

/// Whole seconds as "m:ss" for the header clock and splashes.
public func formatSeconds(_ totalSeconds: Double) -> String {
    // Non-finite or absurd clock values render as a stopped clock rather
    // than trapping in the Int conversion.
    guard totalSeconds.isFinite else { return "0:00" }
    let clamped = Int(min(max(0, totalSeconds.rounded(.down)), 9_007_199_254_740_991))
    let minutes = clamped / 60
    let seconds = clamped % 60
    return "\(minutes):" + (seconds < 10 ? "0\(seconds)" : "\(seconds)")
}
