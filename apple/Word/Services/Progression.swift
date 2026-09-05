import Foundation
import Observation
import WordCore

/// Everything a player accumulates across games and devices, and every score
/// waiting to reach Game Center.
///
/// This is phase 3's logic layer with the GameKit call site left as one small
/// protocol (`ProgressionSubmitter`). That split is deliberate: the plan's
/// §7.1 requires the game to be fully playable **signed out** — auth declined,
/// restricted, or simply never attempted — so the interesting behavior is all
/// in what happens when there is nobody to submit to. That behavior is
/// testable today; the submission is a dozen lines that need an Apple
/// Developer account to run at all.
@Observable @MainActor
final class Progression {
    /// Stable per install. Only this device ever writes its own blob, which
    /// is what stops two devices clobbering each other in iCloud (§9.1).
    private static let deviceKey = "nana.device.v1"

    private let store: KeyValueStore
    private let sync: SyncStore
    let deviceID: String

    /// The merged picture across every device the player owns.
    private(set) var merged: MergedProgress
    private(set) var pendingScores: PendingScores

    /// Set once Game Center auth succeeds. Nil means signed out, which is a
    /// designed state, not an error.
    var submitter: ProgressionSubmitter?

    /// Guards `flush` against overlapping itself — see the note there.
    /// Readable so a test can wait for a flush it didn't start — `record`
    /// fires one of its own that nothing awaits.
    private(set) var isFlushing = false
    private var flushAgain = false

    init(store: KeyValueStore = UserDefaultsStore(), sync: SyncStore? = nil) {
        self.store = store
        if let existing = store.get(Self.deviceKey), !existing.isEmpty {
            deviceID = existing
        } else {
            let fresh = UUID().uuidString
            store.set(Self.deviceKey, fresh)
            deviceID = fresh
        }
        self.sync = sync ?? LocalSyncStore(store: store)
        merged = loadProgress(from: self.sync)
        pendingScores = PendingScores.load(from: store)
    }

    /// Fold a finished game in: update this device's blob, work out what it
    /// scored, and either submit or queue it.
    @discardableResult
    func record(_ outcome: GameOutcome, at now: Date = .now) -> RecordedProgress {
        let stamp = now.timeIntervalSince1970 * 1_000

        // 1. This device's own contribution — the only blob it ever writes.
        var device = loadDeviceProgress(deviceID, from: sync)
        if outcome.mode != .tutorial {
            device.gamesPlayed += 1
            device.bestScore = max(device.bestScore, outcome.score)
        }
        if let daily = outcome.daily {
            if !device.dailyDays.contains(daily.day) { device.dailyDays.append(daily.day) }
            device.bestDailyScore = max(device.bestDailyScore, outcome.score)
        }
        if outcome.mode == .battle, outcome.report.battleWon { device.battleWins += 1 }
        if outcome.mode != .tutorial {
            device.recent = Array(
                ([GameRecord(score: outcome.score, words: outcome.words, at: stamp)]
                    + device.recent
                ).prefix(RECENT_LIMIT))
        }
        device.updatedAt = stamp
        saveDeviceProgress(device, to: sync)
        merged = loadProgress(from: sync)

        // 2. What it should post.
        let scores = submissions(
            mode: outcome.mode,
            pace: outcome.report.pace,
            score: outcome.score,
            daily: outcome.daily,
            dailyWithinDay: outcome.daily.map { dailyDayNumber(at: now) == $0.day } ?? true,
            battleWins: merged.battleWins,
            at: stamp)

        queue(scores: scores, now: stamp)
        return RecordedProgress(merged: merged, scores: scores)
    }

    /// Hold the score locally, then try to send. Queueing *first* is what
    /// makes a mid-submission crash lossless — the worst case is submitting
    /// the same score twice, which Game Center already tolerates.
    private func queue(scores: [PendingScore], now: Double) {
        for score in scores { pendingScores.add(score) }
        pendingScores.prune(now: now)
        persistQueue()
        Task { await flush() }
    }

    /// Send whatever is waiting. A no-op while signed out — which is the
    /// normal state, not a failure — and safe to call as often as you like.
    ///
    /// **One at a time.** `record` fires a flush of its own and `signedIn`
    /// runs another, so two can easily overlap — and `submit` is a suspension
    /// point that leaves the main actor, so an overlapping pair really does
    /// run concurrently. Submitting twice would be harmless (a leaderboard
    /// keeps the best score), but hammering the network with a duplicate of
    /// every queued score isn't, and it makes the queue's mutations
    /// interleave for no reason. A second caller arriving mid-flush instead
    /// marks the queue dirty, and the flush in progress goes round again —
    /// so nothing queued during a send is left sitting there either.
    func flush() async {
        guard submitter != nil else { return }
        guard !isFlushing else {
            flushAgain = true
            return
        }
        isFlushing = true
        defer { isFlushing = false }

        repeat {
            flushAgain = false
            await drainQueue()
        } while flushAgain
    }

    private func drainQueue() async {
        guard let submitter else { return }
        for score in pendingScores.ordered {
            guard await submitter.submit(score) else { continue }
            pendingScores.clear(score)
        }
        persistQueue()
    }

    /// Called when Game Center auth succeeds — the moment a signed-out
    /// player's held scores become sendable (§7.1).
    func signedIn(as submitter: ProgressionSubmitter) async {
        self.submitter = submitter
        await flush()
    }

    func signedOut() {
        submitter = nil
    }

    private func persistQueue() {
        pendingScores.save(to: store)
    }

    var dailyStreak: Int { merged.dailyStreak(today: dailyDayNumber(at: .now)) }
}

/// What one finished game did.
struct RecordedProgress: Equatable {
    var merged: MergedProgress
    var scores: [PendingScore]
}

/// The GameKit call site, kept behind a protocol so everything above is
/// testable without an account. Phase 3's remaining half implements this with
/// `GKLeaderboard.submitScore`.
protocol ProgressionSubmitter: Sendable {
    /// True once the score is accepted; false leaves it queued.
    func submit(_ score: PendingScore) async -> Bool
}

/// Progress storage backed by the same local defaults as everything else.
///
/// The merge is built for iCloud, but it is correct — and useful — on one
/// device too: it is what keeps this device's blob in the shape the sync will
/// expect. Swapping in `NSUbiquitousKeyValueStore` once the iCloud entitlement
/// exists is a one-line change here and nothing anywhere else.
struct LocalSyncStore: SyncStore {
    let store: KeyValueStore
    /// The prefix index, since `KeyValueStore` can't enumerate.
    private static let indexKey = "nana.progress.index.v1"

    func data(forKey key: String) -> String? { store.get(key) }

    func set(_ value: String, forKey key: String) {
        store.set(key, value)
        var known = keys(withPrefix: "")
        guard !known.contains(key) else { return }
        known.append(key)
        store.set(Self.indexKey, known.joined(separator: "\n"))
    }

    func keys(withPrefix prefix: String) -> [String] {
        (store.get(Self.indexKey) ?? "")
            .split(separator: "\n")
            .map(String.init)
            .filter { $0.hasPrefix(prefix) }
    }

    @discardableResult
    func synchronize() -> Bool { true }
}
