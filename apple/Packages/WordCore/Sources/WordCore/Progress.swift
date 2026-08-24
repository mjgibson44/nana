import Foundation

/// Progress that outlives one device.
///
/// New on Apple platforms (plan §9.1) — the web game has one browser and one
/// `localStorage`, so it never had to answer this. iCloud does:
/// `NSUbiquitousKeyValueStore` is **last-writer-wins per key**, so a single
/// shared stats blob would silently eat itself — play on the phone Monday and
/// the iPad Tuesday, and whichever syncs last erases the other's games.
///
/// The fix is to never let two devices write the same key. Each device owns
/// one blob and only ever writes its own; reading merges all of them. That
/// turns a destructive race into arithmetic:
///
///  - **counters sum** (games played, battle wins) — each device counts only
///    the games it saw, so adding them is exactly right;
///  - **bests take the max**;
///  - **day sets union** — which is why streaks are stored as the days played
///    rather than a precomputed number: a length can't be merged, a set can;
///  - **recent games** interleave by time, deduped, then capped.
///
/// All of it is pure, so it tests in CI. Only the store underneath needs an
/// iCloud entitlement.

// MARK: - One device's contribution

public struct DeviceProgress: Codable, Equatable {
    /// Stable per install. Only this device ever writes this blob.
    public var deviceID: String
    /// Finished games this device saw — summed across devices, never shared.
    public var gamesPlayed: Int
    public var bestScore: Int
    /// Battles won here. The cumulative total is the sum, which is what makes
    /// the battle-wins leaderboard (§8.1) correct across devices.
    public var battleWins: Int
    /// Daily Deals completed here, as day numbers — a *set*, so merging is a
    /// union and a streak can be recomputed from the whole picture.
    public var dailyDays: [Int]
    public var bestDailyScore: Int
    /// Newest first, capped like the local `recent`.
    public var recent: [GameRecord]
    /// Unix ms. Not used for conflict resolution — there is no conflict to
    /// resolve — only to spot a device that has gone quiet.
    public var updatedAt: Double

    public init(
        deviceID: String,
        gamesPlayed: Int = 0,
        bestScore: Int = 0,
        battleWins: Int = 0,
        dailyDays: [Int] = [],
        bestDailyScore: Int = 0,
        recent: [GameRecord] = [],
        updatedAt: Double = 0
    ) {
        self.deviceID = deviceID
        self.gamesPlayed = gamesPlayed
        self.bestScore = bestScore
        self.battleWins = battleWins
        self.dailyDays = dailyDays
        self.bestDailyScore = bestDailyScore
        self.recent = recent
        self.updatedAt = updatedAt
    }
}

// MARK: - The merged picture

public struct MergedProgress: Equatable {
    public var gamesPlayed: Int
    public var bestScore: Int
    public var battleWins: Int
    public var dailyDays: Set<Int>
    public var bestDailyScore: Int
    public var recent: [GameRecord]

    public init(
        gamesPlayed: Int = 0,
        bestScore: Int = 0,
        battleWins: Int = 0,
        dailyDays: Set<Int> = [],
        bestDailyScore: Int = 0,
        recent: [GameRecord] = []
    ) {
        self.gamesPlayed = gamesPlayed
        self.bestScore = bestScore
        self.battleWins = battleWins
        self.dailyDays = dailyDays
        self.bestDailyScore = bestDailyScore
        self.recent = recent
    }

    /// The current Daily Deal streak across every device the player owns.
    public func dailyStreak(today: Int) -> Int {
        WordCore.dailyStreak(playedDays: dailyDays, today: today)
    }
}

/// Fold every device's blob into one picture. Order-independent by
/// construction — sums, maxima and set unions don't care who arrives first,
/// which is the whole point: there is no "latest" device to defer to.
public func mergeProgress(_ devices: [DeviceProgress]) -> MergedProgress {
    var merged = MergedProgress()
    var days = Set<Int>()
    for device in devices {
        // A hand-edited or overflowing blob clamps rather than trapping, the
        // same posture `recordGame` takes with a corrupt total.
        merged.gamesPlayed = merged.gamesPlayed.addingReportingOverflow(
            max(0, device.gamesPlayed)
        ).partialValue
        merged.battleWins = merged.battleWins.addingReportingOverflow(
            max(0, device.battleWins)
        ).partialValue
        merged.bestScore = max(merged.bestScore, device.bestScore)
        merged.bestDailyScore = max(merged.bestDailyScore, device.bestDailyScore)
        days.formUnion(device.dailyDays)
        merged.recent.append(contentsOf: device.recent)
    }
    merged.dailyDays = days
    merged.recent = mergeRecent(merged.recent)
    return merged
}

/// Interleave every device's recent games by time, newest first.
///
/// Deduped on the whole record: two devices can legitimately hold the same
/// game if a blob was ever copied (a restored backup, say), and the same
/// game listed twice would also inflate nothing — the counters are summed
/// separately — but it would read as a bug to the player.
func mergeRecent(_ records: [GameRecord]) -> [GameRecord] {
    var seen = Set<String>()
    var unique: [GameRecord] = []
    for record in records.sorted(by: { $0.at > $1.at }) {
        let key = "\(record.at)/\(record.score)/\(record.words)"
        guard seen.insert(key).inserted else { continue }
        unique.append(record)
    }
    return Array(unique.prefix(RECENT_LIMIT))
}

// MARK: - Storage

/// A key-value store whose keys can be enumerated — which `KeyValueStore`
/// deliberately can't, because `localStorage`'s semantics are all this game
/// ever needed from it. iCloud needs one more thing: to find every *other*
/// device's blob without knowing their IDs in advance.
public protocol SyncStore {
    func data(forKey key: String) -> String?
    func set(_ value: String, forKey key: String)
    func keys(withPrefix prefix: String) -> [String]
    /// Best-effort push. False simply means "not now" — never an error to
    /// show a player, since the game is fully playable unsynced.
    @discardableResult
    func synchronize() -> Bool
}

/// Every device blob lives under this prefix and nothing else does, so
/// enumerating it is how a device discovers the others.
public let PROGRESS_KEY_PREFIX = "nana.progress.device."

public func progressKey(for deviceID: String) -> String {
    PROGRESS_KEY_PREFIX + deviceID
}

/// Read and merge every device's blob. Anything unreadable is skipped rather
/// than failing the whole read — one corrupt blob must not cost a player the
/// rest of their history.
public func loadProgress(from store: SyncStore) -> MergedProgress {
    let decoder = JSONDecoder()
    let devices = store.keys(withPrefix: PROGRESS_KEY_PREFIX).compactMap { key -> DeviceProgress? in
        guard let raw = store.data(forKey: key), let data = raw.data(using: .utf8) else {
            return nil
        }
        return try? decoder.decode(DeviceProgress.self, from: data)
    }
    return mergeProgress(devices)
}

/// Read back just this device's blob, so it can be added to.
public func loadDeviceProgress(_ deviceID: String, from store: SyncStore) -> DeviceProgress {
    guard let raw = store.data(forKey: progressKey(for: deviceID)),
        let data = raw.data(using: .utf8),
        let device = try? JSONDecoder().decode(DeviceProgress.self, from: data)
    else {
        return DeviceProgress(deviceID: deviceID)
    }
    return device
}

/// Write this device's blob — and only ever this device's.
public func saveDeviceProgress(_ device: DeviceProgress, to store: SyncStore) {
    guard let data = try? JSONEncoder().encode(device),
        let text = String(data: data, encoding: .utf8)
    else { return }
    store.set(text, forKey: progressKey(for: device.deviceID))
    store.synchronize()
}
