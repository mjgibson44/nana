import Foundation
import WordCore

/// One finished Daily Deal.
struct DailyResult: Codable, Equatable {
    /// The day the game was *started* on — the streak key, and the
    /// leaderboard occurrence a score would belong to.
    var day: Int
    var date: String
    var score: Int
    var words: Int
    /// Tiles never placed. Zero and a valid board is the perfect run.
    var tilesLeft: Int
    var bonusEarned: Bool
    /// False when the puzzle rolled over mid-game.
    ///
    /// A recurring Game Center leaderboard will happily take a stale game's
    /// score into the *new* day's board, which is exactly the bug plan §8.2
    /// says to pin rather than discover: the occurrence is decided when the
    /// game starts, so a game finished after the flip is recorded for its own
    /// day and marked ineligible. Phase 3 reads this to decide whether to
    /// submit.
    var withinDay: Bool
    var at: Double

    var finishedDate: Date { Date(timeIntervalSince1970: at) }
}

/// Every Daily Deal the player has finished on this device.
///
/// Stored as a list rather than a rolling summary because §9.1's iCloud merge
/// is a *set union* across devices — a pre-collapsed streak can't be merged,
/// a set of days can.
struct DailyHistory: Codable, Equatable {
    /// Bumped if the shape changes; a stale blob is dropped, never migrated.
    static let version = 1
    static let key = "nana.daily.v1"
    /// Comfortably over a year, so a streak is never truncated in practice.
    static let limit = 500

    var version: Int = Self.version
    var results: [DailyResult] = []

    var playedDays: Set<Int> { Set(results.map(\.day)) }

    func result(for day: Int) -> DailyResult? {
        results.first { $0.day == day }
    }

    func streak(today: Int) -> Int {
        dailyStreak(playedDays: playedDays, today: today)
    }

    var best: DailyResult? {
        results.max { $0.score < $1.score }
    }

    /// Newest first, for the stats page.
    var recent: [DailyResult] {
        results.sorted { $0.day > $1.day }
    }

    /// One attempt a day: a result already recorded for that day stands.
    mutating func record(_ result: DailyResult) {
        guard self.result(for: result.day) == nil else { return }
        results.append(result)
        if results.count > Self.limit {
            results = Array(results.sorted { $0.day > $1.day }.prefix(Self.limit))
        }
    }

    // MARK: Storage

    static func load(from store: KeyValueStore) -> DailyHistory {
        guard let text = store.get(key), let data = text.data(using: .utf8) else {
            return DailyHistory()
        }
        guard let history = try? JSONDecoder().decode(DailyHistory.self, from: data),
            history.version == version
        else {
            // Garbage falls back to empty, mirroring the web's defensive
            // parsing everywhere else. Writes never throw.
            store.remove(key)
            return DailyHistory()
        }
        return history
    }

    func save(to store: KeyValueStore) {
        guard let data = try? JSONEncoder().encode(self),
            let text = String(data: data, encoding: .utf8)
        else { return }
        store.set(Self.key, text)
    }
}

/// What the home screen needs to know about today, in one value.
struct DailyStatus: Equatable {
    var deal: DailyDeal
    var result: DailyResult?
    var streak: Int

    var isPlayed: Bool { result != nil }
    /// Whether there's a game to start (one attempt a day).
    var canPlay: Bool { result == nil }
}
