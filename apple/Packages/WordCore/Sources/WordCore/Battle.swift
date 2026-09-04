/// Multiplayer: a Battle — two to eight players on one shared deal, every
/// attack split across the field, run until one player stands.
/// Ported from `src/game/battle.ts`.
///
/// Everything here is pure and serializable — the networking layer moves
/// these values between devices, and the host runs the referee functions
/// below. Fairness rests on one idea: tiles are never sent over the wire.
/// Each client regrows the identical deal from a shared seed (see
/// `TileStream`), so the host has no privileged knowledge of what's coming.

import Foundation

/// Where a battle currently stands, for everyone in it.
public enum BattlePhase: String, Codable {
    case lobby, playing, finished
}

public struct BattlePlayer: Codable, Equatable, Identifiable {
    /// The player's stable identity, so a dropped connection can be
    /// re-attached to the same seat. (On GameKit this is `gamePlayerID`.)
    public var id: String
    public var name: String
    public var host: Bool
    /// Live score while playing; final score once buried or finished.
    public var score: Int
    /// Buried under loose tiles — out of the current game.
    public var buried: Bool
    /// False while the player's connection is down. The game plays on without
    /// them — their seat is held for a short grace.
    public var connected: Bool
    /// Gone for good — left by choice, or never came back from a drop.
    public var left: Bool
    /// Joined while a game was running; playing from the next start.
    public var waiting: Bool
    /// How many tiles are in the player's pile right now — the pile gauge.
    public var tiles: Int
    /// When this player fell out of the running — 1 for the first buried (or
    /// gone for good), counting up. Nil while still standing. The host writes
    /// it once and never rewrites it.
    public var outOrder: Int?

    public init(
        id: String, name: String, host: Bool = false, score: Int = 0,
        buried: Bool = false, connected: Bool = true, left: Bool = false,
        waiting: Bool = false, tiles: Int = 0, outOrder: Int? = nil
    ) {
        self.id = id
        self.name = name
        self.host = host
        self.score = score
        self.buried = buried
        self.connected = connected
        self.left = left
        self.waiting = waiting
        self.tiles = tiles
        self.outOrder = outOrder
    }
}

/// The whole shared truth, owned by the host and broadcast on every change.
public struct BattleState: Codable, Equatable {
    public var phase: BattlePhase
    public var players: [BattlePlayer]
    /// Counts the games started in this lobby, so clients can tell restarts apart.
    public var game: Int
    /// Who won, once the phase is 'finished'. Nil for a draw.
    public var winnerId: String?
    /// Which game this lobby plays. New on Apple platforms — the web's lobby
    /// only ever holds a Battle, which is what a snapshot without it means.
    public var mode: GameMode
    /// The shared board, while the lobby plays Occupy (`Occupy.swift`).
    public var occupy: OccupyState?

    public init(
        phase: BattlePhase, players: [BattlePlayer], game: Int, winnerId: String?,
        mode: GameMode = .battle, occupy: OccupyState? = nil
    ) {
        self.phase = phase
        self.players = players
        self.game = game
        self.winnerId = winnerId
        self.mode = mode
        self.occupy = occupy
    }

    private enum Key: String, CodingKey {
        case phase, players, game, winnerId, mode, occupy
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Key.self)
        phase = try container.decode(BattlePhase.self, forKey: .phase)
        players = try container.decode([BattlePlayer].self, forKey: .players)
        game = try container.decode(Int.self, forKey: .game)
        winnerId = try container.decodeIfPresent(String.self, forKey: .winnerId)
        mode = try container.decodeIfPresent(GameMode.self, forKey: .mode) ?? .battle
        occupy = try container.decodeIfPresent(OccupyState.self, forKey: .occupy)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Key.self)
        try container.encode(phase, forKey: .phase)
        try container.encode(players, forKey: .players)
        try container.encode(game, forKey: .game)
        try container.encode(winnerId, forKey: .winnerId)
        try container.encode(mode, forKey: .mode)
        try container.encodeIfPresent(occupy, forKey: .occupy)
    }
}

// MARK: - Join codes

/// Letters only — no digits at all, so a code is always read and typed as a
/// word. I, L and O stay out too: they're the letters that get mistaken for
/// 1 and 0.
///
/// Three places, not five: a code exists to be read out loud across a room
/// and typed on a phone, and three letters is what fits in one glance.
/// Twenty-three letters over three places is 12,167 codes — small enough that
/// two lobbies can genuinely collide, which is why claiming one retries
/// (`hostBattle`) rather than trusting the draw.
let CODE_ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ"
public let CODE_LENGTH = 3

public func newBattleCode() -> String {
    var code = ""
    for _ in 0..<CODE_LENGTH {
        code.append(CODE_ALPHABET.randomElement()!)
    }
    return code
}

/// Forgive how a code was typed: trim, uppercase, and drop anything that
/// isn't a letter. Normalizing never invents a character the generator
/// couldn't have dealt, so whatever comes out can be judged as typed.
public func normalizeBattleCode(_ raw: String) -> String {
    String(
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
            .filter { $0 >= "A" && $0 <= "Z" }
    )
}

public func isValidBattleCode(_ code: String) -> Bool {
    if code.count != CODE_LENGTH { return false }
    for ch in code where !CODE_ALPHABET.contains(ch) {
        return false
    }
    return true
}

/// The link a host shares. Pure port of `battleLink` — the web version reads
/// `window.location`; here the caller supplies its origin and path.
public func battleLink(code: String, origin: String, pathname: String) -> String {
    "\(origin)\(pathname)#battle=\(code)"
}

/// The code carried by a share link, or nil when the URL isn't one.
/// Mirrors the TS regex `^#battle=([A-Za-z0-9]+)$`.
public func codeFromHash(_ hash: String) -> String? {
    guard hash.hasPrefix("#battle=") else { return nil }
    let raw = String(hash.dropFirst("#battle=".count))
    guard !raw.isEmpty,
          raw.allSatisfy({ ($0 >= "A" && $0 <= "Z") || ($0 >= "a" && $0 <= "z") || ($0 >= "0" && $0 <= "9") })
    else { return nil }
    let code = normalizeBattleCode(raw)
    return isValidBattleCode(code) ? code : nil
}

// MARK: - Tile stream

/// The fixed size the stream grows its hidden board by, whatever callers ask
/// for — see the determinism contract on `TileStream`.
let STREAM_CHUNK = 5

/// The battle deal: a hidden crossword grown word by word, driven by a seeded
/// RNG, and grown off its own private solution board rather than the player's
/// real one. Players' boards diverge immediately, so growing from them would
/// deal different letters; growing from the shared hidden board keeps every
/// player's letters identical while still weaving real crossing words.
///
/// Determinism contract: two streams with the same seed deal the same opening
/// batch (every client asks for the same one) and after it the identical
/// sequence of letters, however the requests are sized — the hidden board
/// always grows by the same fixed chunk and requests just drain the sequence.
public final class TileStream {
    private let rng: () -> Double
    private let wordPool: [String]
    private var hidden: TileMap?
    /// Letters grown but not yet handed out.
    private var pending: [String] = []

    /// - Precondition: `wordPool` contains at least one usable (3–8 letter,
    ///   lowercase) word — the bundled pool always does.
    public init(seed: String, wordPool: [String] = commonWords) {
        precondition(!usableWords(wordPool).isEmpty, "word pool is empty")
        self.rng = seededRng(seed)
        self.wordPool = wordPool
    }

    public func next(_ count: Int) -> [String] {
        // The TS stream tolerates a non-positive count (network-derived
        // attack counts flow in here): it still sizes the opening board on
        // the first call, then hands back nothing.
        let take = max(0, count)
        if hidden == nil {
            // The opening deal sizes the hidden board — but never below what
            // a crossword needs, so a stream can serve requests of any size
            // (attacks ask for as little as one tile).
            let puzzle = try! generatePuzzle(
                wordPool: wordPool, tileCount: max(count, STREAM_CHUNK), rng: rng
            )
            hidden = puzzle.solution ?? TileMap()
            pending.append(contentsOf: puzzle.letters)
        }
        while pending.count < take {
            let grown = try! extendPuzzle(
                board: hidden!, bounds: boardBounds(hidden!),
                wordPool: wordPool, tileCount: STREAM_CHUNK, rng: rng
            )
            if let solution = grown.solution { hidden = solution }
            pending.append(contentsOf: grown.letters)
        }
        let batch = Array(pending.prefix(take))
        pending.removeFirst(take)
        return batch
    }
}

/// The bundled generation word pool (`Resources/common-words.txt`, byte-
/// identical to the web's `src/assets/common-words.txt` — CI checks). Its
/// FILE ORDER is determinism-critical: it fixes the generator's bucket order.
public let commonWords: [String] = {
    let url = Bundle.module.url(forResource: "common-words", withExtension: "txt")!
    let text = try! String(contentsOf: url, encoding: .utf8)
    // Split on any newline, not the Character "\n" — in Swift "\r\n" is one
    // grapheme, so a plain split(separator: "\n") would leave a CRLF file as
    // a single garbage entry, empty the usable pool, and kill every battle
    // at startup. Trim mirrors JS trim() for the same reason.
    return text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
}()

// MARK: - Referee

/// The slice of a player the referee functions need.
public protocol Contestant {
    var score: Int { get }
    var buried: Bool { get }
    /// Permanently out — left by choice or never reconnected. A merely
    /// disconnected player is NOT left: their seat is held while they redial.
    var left: Bool { get }
    var waiting: Bool { get }
}

/// A contestant with a recorded elimination order, for the standings.
public protocol OutOrdered: Contestant {
    var outOrder: Int? { get }
}

extension BattlePlayer: OutOrdered {}

/// In the current game and still able to change their score.
func isAlive(_ player: Contestant) -> Bool {
    !player.waiting && !player.buried && !player.left
}

/// Whether a battle is decided: at least two players are dealt in and at most
/// one is still alive. The size of the field doesn't matter — a Battle of
/// eight ends exactly when one of two does, on the last player standing.
public func battleOver(_ players: [Contestant]) -> Bool {
    let inGame = players.filter { !$0.waiting }
    if inGame.count < 2 { return false }
    return inGame.filter(isAlive).count <= 1
}

/// Who won a decided battle: the last player alive, or nil when nobody is —
/// a draw, which in practice takes the last players going down together.
public func battleWinner<T: Contestant>(_ players: [T]) -> T? {
    let alive = players.filter { !$0.waiting }.filter(isAlive)
    return alive.count == 1 ? alive[0] : nil
}

/// One row of the standings: a player and where they sit.
public struct RankedPlayer<T: OutOrdered> {
    public var player: T
    /// Competition ranking: tied scores share a rank, and the next rank
    /// skips past them (1, 2, 2, 4).
    public var rank: Int
}

/// The standings of a survival game, best first: whoever is still standing
/// (outOrder nil) leads, then everyone else in reverse order of falling —
/// the later you went out, the higher you place. Waiting players sat this
/// game out — filter them out before calling.
public func rankByElimination<T: OutOrdered>(_ players: [T]) -> [RankedPlayer<T>] {
    func later(_ a: T, _ b: T) -> Int {
        switch (a.outOrder, b.outOrder) {
        case (nil, nil): return 0
        case (nil, _): return -1
        case (_, nil): return 1
        case let (aOut?, bOut?): return bOut - aOut
        }
    }
    // Swift's sorted(by:) is documented stable, matching JS's stable sort.
    let sorted = players.sorted { later($0, $1) < 0 }
    var ranked: [RankedPlayer<T>] = []
    for i in 0..<sorted.count {
        let tied = i > 0 && later(sorted[i], sorted[i - 1]) == 0
        ranked.append(RankedPlayer(player: sorted[i], rank: tied ? ranked[i - 1].rank : i + 1))
    }
    return ranked
}

/// Who took a decided game: the survivor the host named — and nobody at all
/// for the draw where the last players went down together. Waiting players
/// sat this game out and can't have won it.
public func battleWinners(_ state: BattleState) -> [BattlePlayer] {
    let contestants = state.players.filter { !$0.waiting }
    guard let winnerId = state.winnerId else { return [] }
    return contestants.filter { $0.id == winnerId }
}

/// "1st", "2nd", "3rd"… for the rank badge and the results screen.
public func ordinal(_ rank: Int) -> String {
    let tens = rank % 100
    if tens >= 11 && tens <= 13 { return "\(rank)th" }
    switch rank % 10 {
    case 1: return "\(rank)st"
    case 2: return "\(rank)nd"
    case 3: return "\(rank)rd"
    default: return "\(rank)th"
    }
}
