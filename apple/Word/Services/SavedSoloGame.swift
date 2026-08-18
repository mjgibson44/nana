import Foundation
import WordCore

/// An in-progress solo game, serialized so it survives process death.
///
/// New on Apple platforms and deliberately so (plan §6.1): the OS routinely
/// kills backgrounded apps, and losing a 30-minute endless run to a phone call
/// is a regression web players never hit. The board is plain serializable data,
/// so the whole game is a small JSON blob.
///
/// The clock is stored as **remaining seconds**, not a deadline: a game resumed
/// tomorrow must not find its round already expired. That matches how the web
/// freezes a countdown behind a readable overlay — a resumed game comes back
/// held, and starts ticking when the player dismisses the card.
struct SavedSoloGame: Codable, Equatable {
    /// Bumped if the shape changes; a stale blob is dropped, never migrated.
    static let version = 1
    static let key = "nana.solo.save.v1"

    var version: Int = Self.version
    var seed: String
    var pace: String
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
    /// When it was put away, for the "resume?" prompt's wording.
    var savedAt: Double

    var soloPace: SoloPace { SoloPace(rawValue: pace) ?? .regular }
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
