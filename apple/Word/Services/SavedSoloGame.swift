import Foundation
import WordCore

/// An in-progress solo game, serialized so it survives process death.
///
/// New on Apple platforms and deliberately so (plan §6.1): the OS routinely
/// kills backgrounded apps, and losing a 30-minute run to a phone call is a
/// regression web players never hit. The board is plain serializable data, so
/// the whole game is a small JSON blob.
///
/// The clock is stored as **remaining seconds**, not a deadline: a game resumed
/// tomorrow must not find its round already expired. That matches how the game
/// freezes a countdown behind a readable overlay — a resumed game comes back
/// held, and starts ticking when the player dismisses the card.
struct SavedSoloGame: Codable, Equatable {
    /// Bumped if the shape changes; a stale blob is dropped, never migrated.
    /// v3 dropped the Daily Deal's fields along with the mode; v4 added the
    /// hazard and the fire it lit; v5 brought the Daily back, as the day it
    /// was and the strokes spent on it; v6 retired Wildfire and put the
    /// prize field where the fire was.
    static let version = 6
    static let key = "nana.solo.save.v1"

    var version: Int = Self.version
    var seed: String
    /// Which game this was — `GameMode`'s raw value. Solo unless it says
    /// otherwise, since Solo is the only thing older blobs held.
    var mode: String = GameMode.endless.rawValue
    var pace: String
    /// What the board was up to — `SoloModifier`'s raw value. Defaulted so a
    /// blob can still be built by naming only the fields a plain game has.
    var modifier: String = SoloModifier.none.rawValue
    /// The gold squares and their clocks. Saved rather than replayed: a
    /// restored game comes back to exactly the board it left, with the
    /// seconds each square had left, and without having to rewind the spawn
    /// randomness — `PrizeField.spawns` is the stream's position.
    ///
    /// Seconds left rather than deadlines, for the same reason
    /// `remainingSeconds` is: a game picked back up tomorrow must not find
    /// every prize already expired on arrival.
    var prizes: PrizeField = PrizeField()
    var board: TileMap
    var rack: [String]
    var phase: String
    var dripsElapsed: Int
    var bankedBonus: Int
    /// Seconds left on the current round, or nil if the game had no clock.
    var remainingSeconds: Double?
    /// How many clock deals have happened — the deal stream's position, so a
    /// resumed game keeps dealing the same letters it would have.
    var dealSerial: Int
    /// The Daily: which day's puzzle, and how many words it has cost so far.
    /// The puzzle itself isn't stored — it is a pure function of the day's
    /// seed, so it is rebuilt rather than carried.
    var dailyDay: Int? = nil
    var strokes: Int = 0
    /// When it was put away.
    var savedAt: Double

    var soloPace: SoloPace { SoloPace(rawValue: pace) ?? .regular }
    var soloModifier: SoloModifier { SoloModifier(rawValue: modifier) ?? .none }
    var gameMode: GameMode { GameMode(rawValue: mode) ?? .endless }
    /// The day this was, rebuilt from its number — everything about a day
    /// follows from that, the seed included.
    var deal: DailyDeal? { dailyDay.map { dailyDeal(day: $0) } }
    var soloPhase: SoloPhase { phase == "drip" ? .drip : .initial }

    var savedDate: Date { Date(timeIntervalSince1970: savedAt) }

    // MARK: Storage

    static func load(from store: KeyValueStore) -> SavedSoloGame? {
        guard let text = store.get(key), let data = text.data(using: .utf8) else { return nil }
        guard let saved = try? JSONDecoder().decode(SavedSoloGame.self, from: data) else {
            // Garbage (or an older shape) falls back to no save, mirroring the
            // web's defensive parsing everywhere else.
            store.remove(key)
            return nil
        }
        guard saved.version == version, !saved.board.isEmpty || !saved.rack.isEmpty else {
            store.remove(key)
            return nil
        }
        return saved
    }

    func save(to store: KeyValueStore) {
        guard let data = try? JSONEncoder().encode(self),
            let text = String(data: data, encoding: .utf8)
        else { return }
        store.set(Self.key, text)
    }

    static func clear(in store: KeyValueStore) {
        store.remove(key)
    }
}
