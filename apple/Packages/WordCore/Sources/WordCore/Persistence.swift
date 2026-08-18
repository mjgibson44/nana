import Foundation

/// Everything the game remembers between visits, behind an injectable store.
/// Ported from `src/game/stats.ts`, `src/game/setups.ts`,
/// `src/game/onboarding.ts`, and the sound preference in `src/game/sounds.ts`.
///
/// The web build keeps all of this in `localStorage`. Here the same four
/// modules read and write through `KeyValueStore` instead, so the app decides
/// what backs them — UserDefaults, a file, an in-memory fake for tests. The
/// storage keys and the stored JSON shapes are kept identical to the web
/// build's, so a future migration can read web exports as-is.

// MARK: - Store

/// The slice of `localStorage` the game uses.
///
/// The TS modules wrap every read and write in try/catch because private
/// browsing and blocked storage throw on plain access. Here that posture is
/// baked into the protocol instead: a failed or missing read is a `nil` from
/// `get`, and `set`/`remove` never throw — a blocked store's write simply
/// doesn't persist, which is the "swallowed write" the web build lives with.
public protocol KeyValueStore {
    func get(_ key: String) -> String?
    func set(_ key: String, _ value: String)
    func remove(_ key: String)
}

// MARK: - Stats (stats.ts)

/// Game history, kept in storage so it survives between visits.
///
/// A game is recorded the moment it finishes — the last level is completed
/// (or skipped past its confirm). Abandoned games are never counted.

public struct GameRecord: Codable, Equatable {
    /// Final score for the game.
    public var score: Int
    /// How many words were on the finished board.
    public var words: Int
    /// When the game finished, as a Unix timestamp in ms.
    public var at: Double

    public init(score: Int, words: Int, at: Double) {
        self.score = score
        self.words = words
        self.at = at
    }
}

public struct Stats: Equatable {
    /// Every finished game, ever — not capped like `recent`.
    public var gamesPlayed: Int
    /// The latest finished games, newest first.
    public var recent: [GameRecord]

    public init(gamesPlayed: Int, recent: [GameRecord]) {
        self.gamesPlayed = gamesPlayed
        self.recent = recent
    }
}

private let STATS_KEY = "nana.stats.v1"

/// How many finished games `recent` holds onto.
public let RECENT_LIMIT = 30

private let EMPTY = Stats(gamesPlayed: 0, recent: [])

/// The stored stats blob, decoded the way the TS validates it: `recent` only
/// if it's an array, keeping only the elements that are objects with numeric
/// `score`/`words`/`at`; `gamesPlayed` only if it's a number. The lossy
/// per-element decode stands in for the TS `Array.prototype.filter`.
private struct StoredStats: Decodable {
    var gamesPlayed: Double?
    var recent: [GameRecord]

    /// One `recent` element: a valid record, or `nil` for anything else —
    /// a non-object, or an object missing or mistyping a field.
    private struct MaybeRecord: Decodable {
        let record: GameRecord?
        init(from decoder: Decoder) throws {
            record = try? GameRecord(from: decoder)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case gamesPlayed, recent
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        gamesPlayed = try? container.decode(Double.self, forKey: .gamesPlayed)
        let elements = (try? container.decode([MaybeRecord].self, forKey: .recent)) ?? []
        recent = elements.compactMap { $0.record }
    }
}

/// Read stats back, trusting nothing: storage can be missing (private
/// browsing), or hold something stale or hand-edited. Anything unusable
/// just means starting from zero.
public func loadStats(from store: KeyValueStore) -> Stats {
    guard let raw = store.get(STATS_KEY), !raw.isEmpty else { return EMPTY }
    guard let parsed = try? JSONDecoder().decode(StoredStats.self, from: Data(raw.utf8)) else {
        return EMPTY
    }
    let recent = parsed.recent
    let gamesPlayed: Int
    if let stored = parsed.gamesPlayed, stored >= Double(recent.count) {
        // `Math.floor(parsed.gamesPlayed)`. A JS number can outrun Int, so an
        // absurd hand-edited total clamps instead of trapping.
        gamesPlayed = Int(exactly: stored.rounded(.down)) ?? Int.max
    } else {
        gamesPlayed = recent.count
    }
    return Stats(gamesPlayed: gamesPlayed, recent: recent)
}

/// Add a finished game to the record. Returns the stats as they now stand.
///
/// The TS stamps `Date.now()` itself; here the caller passes the whole
/// record, `at` included (Unix ms — `Date().timeIntervalSince1970 * 1000`).
public func recordGame(_ record: GameRecord, in store: KeyValueStore) -> Stats {
    let stats = loadStats(from: store)
    let next = Stats(
        // JS addition can't trap; don't let a clamped total trap here either.
        gamesPlayed: stats.gamesPlayed == Int.max ? Int.max : stats.gamesPlayed + 1,
        recent: Array(([record] + stats.recent).prefix(RECENT_LIMIT))
    )
    // Storage full or blocked — the game still finishes, it just isn't kept.
    // (`set` never throws; a blocked store's write simply doesn't persist.)
    store.set(STATS_KEY, encodeStats(next))
    return next
}

/// `JSON.stringify` for `Stats`, byte-for-byte what the web build writes:
/// insertion-ordered keys, and whole timestamps without a fraction.
private func encodeStats(_ stats: Stats) -> String {
    let records = stats.recent.map { record in
        "{\"score\":\(record.score),\"words\":\(record.words),\"at\":\(jsonNumber(record.at))}"
    }
    return "{\"gamesPlayed\":\(stats.gamesPlayed),\"recent\":[\(records.joined(separator: ","))]}"
}

/// A `Double` the way `JSON.stringify` writes a JS number: whole values with
/// no fraction ("1700000000000", not "1700000000000.0") and, like JS, the
/// unserializable ones as null.
private func jsonNumber(_ value: Double) -> String {
    guard value.isFinite else { return "null" }
    if let whole = Int64(exactly: value) { return String(whole) }
    return String(value)
}

// MARK: - Solo setup (setups.ts)

/// What the Solo door was last set up as, remembered between visits.
///
/// The setup sheet opens on the last game's settings, which are nearly always
/// the ones wanted again — so playing the same thing twice is one tap on Play.
/// Keeping them here carries that across a reload too: the sheet a player sees
/// on Monday is the one they left on Sunday.
///
/// Only a deliberate choice is written — the Play button on the setup sheet.
/// Anything missing, stale or hand-edited reads as the defaults below.

/// Solo's settings: its pace, and nothing else so far.
public struct SoloSetup: Equatable {
    public var pace: SoloPace

    public init(pace: SoloPace) {
        self.pace = pace
    }
}

/// What a player who has never set Solo up gets.
public let DEFAULT_SOLO = SoloSetup(pace: .regular)

private let SOLO_KEY = "nana.setup.solo.v1"

/// Whatever is under `key`, as an object — or an empty one for anything that
/// isn't readable, isn't JSON, or isn't a plain object to begin with.
private func readSetup(_ key: String, from store: KeyValueStore) -> [String: Any] {
    guard let raw = store.get(key) else { return [:] }
    guard let parsed = try? JSONSerialization.jsonObject(with: Data(raw.utf8)) else { return [:] }
    return parsed as? [String: Any] ?? [:]
}

/// `value` if it's one of `allowed`, and `fallback` otherwise.
private func oneOf<T: Equatable>(_ value: T?, _ allowed: [T], _ fallback: T) -> T {
    guard let value, allowed.contains(value) else { return fallback }
    return value
}

public func loadSoloSetup(from store: KeyValueStore) -> SoloSetup {
    let stored = readSetup(SOLO_KEY, from: store)
    let pace = (stored["pace"] as? String).flatMap(SoloPace.init(rawValue:))
    return SoloSetup(pace: oneOf(pace, PACE_OPTIONS.map { $0.pace }, DEFAULT_SOLO.pace))
}

public func saveSoloSetup(_ setup: SoloSetup, to store: KeyValueStore) {
    // Bytes match the web's `JSON.stringify(setup)`: `{"pace":"regular"}`.
    // Storage full or blocked — the sheet just opens on the defaults next time.
    store.set(SOLO_KEY, "{\"pace\":\"\(setup.pace.rawValue)\"}")
}

// MARK: - Onboarding (onboarding.ts)

/// What a player has already been shown, remembered between visits.
///
/// Two things front a first game: the tutorial, once ever, and a short
/// explainer for each mode, once per mode. Both are one-way notes — nothing
/// here is ever unset, so neither can come back a second time.
///
/// A failed read reports "not seen yet", which shows the note again rather
/// than swallowing it; a failed write simply doesn't stick.

/// Set once the tutorial has been offered — it fronts the first game only.
private let TUTORIAL_KEY = "nana.tutorial.v1"

/// Holds the doors whose explainer has been read, comma separated.
private let DOORS_KEY = "nana.doors.v1"

public func hasSeenTutorial(in store: KeyValueStore) -> Bool {
    store.get(TUTORIAL_KEY) != nil
}

public func markTutorialSeen(in store: KeyValueStore) {
    // Presence is the flag; the value is a timestamp string, exactly the
    // web's `String(Date.now())`. Storage blocked or full — the tutorial
    // will simply be offered again.
    store.set(TUTORIAL_KEY, String(Int64(Date().timeIntervalSince1970 * 1000)))
}

private func doorsSeen(in store: KeyValueStore) -> [String] {
    // The TS `split(',').filter(Boolean)` — Swift's split drops the empty
    // pieces too, so a missing key reads as no doors seen.
    (store.get(DOORS_KEY) ?? "").split(separator: ",").map(String.init)
}

public func hasSeenDoor(_ door: GameDoor, in store: KeyValueStore) -> Bool {
    doorsSeen(in: store).contains(door.rawValue)
}

public func markDoorSeen(_ door: GameDoor, in store: KeyValueStore) {
    let seen = doorsSeen(in: store)
    if seen.contains(door.rawValue) { return }
    // As above: on a blocked store the explainer will just introduce this
    // mode once more.
    store.set(DOORS_KEY, (seen + [door.rawValue]).joined(separator: ","))
}

// MARK: - Sound preference (sounds.ts — the pref only; the voices are SoundSpec.swift)

private let SOUND_KEY = "nana.sound.v1"

/// Sound is on until it's turned off, so a first-time player hears the game:
/// anything but the exact stored value "off" — including nothing stored at
/// all, or a blocked read — means on.
public func isSoundEnabled(in store: KeyValueStore) -> Bool {
    store.get(SOUND_KEY) != "off"
}

public func setSoundEnabled(_ on: Bool, in store: KeyValueStore) {
    // Storage full or blocked — the choice just won't survive a reload.
    store.set(SOUND_KEY, on ? "on" : "off")
}
