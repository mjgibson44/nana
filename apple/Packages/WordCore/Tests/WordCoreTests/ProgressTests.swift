import Foundation
import Testing

@testable import WordCore

/// The cross-device merge (plan §9.1). The property that matters is that it
/// is *destructive-free*: no device's play can ever erase another's.

private func record(_ score: Int, at: Double, words: Int = 3) -> GameRecord {
    GameRecord(score: score, words: words, at: at)
}

@Suite("Progress: merging devices")
struct ProgressMergeTests {
    @Test("sums counters rather than letting the last writer win")
    func sumsCounters() {
        let phone = DeviceProgress(deviceID: "phone", gamesPlayed: 12, battleWins: 3)
        let pad = DeviceProgress(deviceID: "pad", gamesPlayed: 7, battleWins: 2)
        let merged = mergeProgress([phone, pad])
        #expect(merged.gamesPlayed == 19)
        #expect(merged.battleWins == 5)
    }

    @Test("takes the best score, not the newest")
    func takesTheBestScore() {
        let phone = DeviceProgress(deviceID: "phone", bestScore: 500, bestDailyScore: 120)
        let pad = DeviceProgress(deviceID: "pad", bestScore: 310, bestDailyScore: 240)
        let merged = mergeProgress([phone, pad])
        #expect(merged.bestScore == 500)
        #expect(merged.bestDailyScore == 240)
    }

    @Test("unions the days played, which is what makes a streak mergeable")
    func unionsDaysPlayed() {
        let phone = DeviceProgress(deviceID: "phone", dailyDays: [100, 98])
        let pad = DeviceProgress(deviceID: "pad", dailyDays: [99, 97, 98])
        let merged = mergeProgress([phone, pad])
        #expect(merged.dailyDays == [97, 98, 99, 100])
        // Neither device alone has a streak worth the name; together it's four.
        #expect(mergeProgress([phone]).dailyStreak(today: 100) == 1)
        #expect(merged.dailyStreak(today: 100) == 4)
    }

    @Test("is order-independent — there is no latest device to defer to")
    func isOrderIndependent() {
        let a = DeviceProgress(
            deviceID: "a", gamesPlayed: 4, bestScore: 90, dailyDays: [5],
            recent: [record(90, at: 30)])
        let b = DeviceProgress(
            deviceID: "b", gamesPlayed: 9, bestScore: 40, dailyDays: [6],
            recent: [record(40, at: 10)])
        let c = DeviceProgress(deviceID: "c", gamesPlayed: 1, bestScore: 300, dailyDays: [7])
        #expect(mergeProgress([a, b, c]) == mergeProgress([c, a, b]))
        #expect(mergeProgress([a, b, c]) == mergeProgress([b, c, a]))
    }

    @Test("interleaves recent games newest first across devices")
    func interleavesRecentGames() {
        let phone = DeviceProgress(
            deviceID: "phone", recent: [record(3, at: 300), record(1, at: 100)])
        let pad = DeviceProgress(
            deviceID: "pad", recent: [record(4, at: 400), record(2, at: 200)])
        let merged = mergeProgress([phone, pad])
        #expect(merged.recent.map(\.at) == [400, 300, 200, 100])
    }

    @Test("drops a game two devices both hold")
    func dropsDuplicateGames() {
        let shared = record(50, at: 500)
        let phone = DeviceProgress(deviceID: "phone", recent: [shared])
        // A restored backup can leave the same game on two devices.
        let pad = DeviceProgress(deviceID: "pad", recent: [shared, record(10, at: 100)])
        let merged = mergeProgress([phone, pad])
        #expect(merged.recent.count == 2)
    }

    @Test("caps recent at the same limit as one device's list")
    func capsRecent() {
        let many = (0..<40).map { record($0, at: Double($0)) }
        let merged = mergeProgress([
            DeviceProgress(deviceID: "a", recent: many),
            DeviceProgress(deviceID: "b", recent: many.map { record($0.score, at: $0.at + 0.5) }),
        ])
        #expect(merged.recent.count == RECENT_LIMIT)
    }

    @Test("an empty set of devices is an empty picture, not a crash")
    func emptyDevices() {
        #expect(mergeProgress([]) == MergedProgress())
    }

    @Test("ignores a hand-edited negative counter instead of going backwards")
    func ignoresNegativeCounters() {
        let good = DeviceProgress(deviceID: "a", gamesPlayed: 10, battleWins: 4)
        let bad = DeviceProgress(deviceID: "b", gamesPlayed: -5, battleWins: -99)
        let merged = mergeProgress([good, bad])
        #expect(merged.gamesPlayed == 10)
        #expect(merged.battleWins == 4)
    }

    @Test("clamps rather than trapping on an absurd total")
    func clampsAbsurdTotals() {
        let merged = mergeProgress([
            DeviceProgress(deviceID: "a", gamesPlayed: .max),
            DeviceProgress(deviceID: "b", gamesPlayed: .max),
        ])
        #expect(merged.gamesPlayed != 0)
    }
}

// MARK: - Store round-trip

/// An in-memory `SyncStore`, standing in for `NSUbiquitousKeyValueStore`.
final class FakeSyncStore: SyncStore {
    var values: [String: String] = [:]
    private(set) var synchronizeCount = 0

    func data(forKey key: String) -> String? { values[key] }
    func set(_ value: String, forKey key: String) { values[key] = value }
    func keys(withPrefix prefix: String) -> [String] {
        values.keys.filter { $0.hasPrefix(prefix) }.sorted()
    }
    @discardableResult func synchronize() -> Bool {
        synchronizeCount += 1
        return true
    }
}

@Suite("Progress: the sync store")
struct ProgressStoreTests {
    @Test("a device only ever writes its own key")
    func aDeviceOnlyWritesItsOwnKey() {
        let store = FakeSyncStore()
        saveDeviceProgress(DeviceProgress(deviceID: "phone", gamesPlayed: 3), to: store)
        saveDeviceProgress(DeviceProgress(deviceID: "pad", gamesPlayed: 4), to: store)
        #expect(store.keys(withPrefix: PROGRESS_KEY_PREFIX).count == 2)
        #expect(store.values[progressKey(for: "phone")] != nil)
        #expect(loadProgress(from: store).gamesPlayed == 7)
    }

    @Test("a device rewriting its blob replaces only its own contribution")
    func rewritingReplacesOnlyItsOwn() {
        let store = FakeSyncStore()
        saveDeviceProgress(DeviceProgress(deviceID: "phone", gamesPlayed: 3), to: store)
        saveDeviceProgress(DeviceProgress(deviceID: "pad", gamesPlayed: 4), to: store)
        saveDeviceProgress(DeviceProgress(deviceID: "phone", gamesPlayed: 10), to: store)
        #expect(loadProgress(from: store).gamesPlayed == 14, "3 replaced by 10, pad's 4 untouched")
    }

    @Test("one corrupt blob doesn't cost the player the others")
    func oneCorruptBlobIsSkipped() {
        let store = FakeSyncStore()
        saveDeviceProgress(DeviceProgress(deviceID: "phone", gamesPlayed: 6), to: store)
        store.set("{not json", forKey: progressKey(for: "broken"))
        #expect(loadProgress(from: store).gamesPlayed == 6)
    }

    @Test("an unknown device reads back as an empty blob to build on")
    func unknownDeviceReadsEmpty() {
        let store = FakeSyncStore()
        let device = loadDeviceProgress("new", from: store)
        #expect(device.deviceID == "new")
        #expect(device.gamesPlayed == 0)
    }

    @Test("round-trips a full blob")
    func roundTripsAFullBlob() {
        let store = FakeSyncStore()
        let device = DeviceProgress(
            deviceID: "phone", gamesPlayed: 5, bestScore: 220, battleWins: 2,
            dailyDays: [10, 11], bestDailyScore: 180, recent: [record(220, at: 99)],
            updatedAt: 1_000)
        saveDeviceProgress(device, to: store)
        #expect(loadDeviceProgress("phone", from: store) == device)
        #expect(store.synchronizeCount == 1)
    }

    @Test("ignores keys that aren't device blobs")
    func ignoresForeignKeys() {
        let store = FakeSyncStore()
        saveDeviceProgress(DeviceProgress(deviceID: "phone", gamesPlayed: 2), to: store)
        store.set("something else", forKey: "nana.theme.v1")
        #expect(loadProgress(from: store).gamesPlayed == 2)
    }
}
