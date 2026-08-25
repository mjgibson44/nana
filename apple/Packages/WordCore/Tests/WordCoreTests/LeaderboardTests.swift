import Foundation
import Testing

@testable import WordCore

/// A local stand-in for storage (the persistence suite keeps its own private
/// one; duplicating four lines beats making either file's fixture shared).
private final class MemoryKeyValueStore: KeyValueStore {
    var values: [String: String]
    init(_ values: [String: String] = [:]) { self.values = values }
    func get(_ key: String) -> String? { values[key] }
    func set(_ key: String, _ value: String) { values[key] = value }
    func remove(_ key: String) { values[key] = nil }
}

/// Leaderboards and the signed-out queue (plan §7.1, §8.1).

@Suite("Leaderboards: boards")
struct LeaderboardBoardTests {
    @Test("each Solo pace has its own board")
    func eachPaceHasItsOwnBoard() {
        #expect(LeaderboardID.solo(.regular) == .soloRegular)
        #expect(LeaderboardID.solo(.fast) == .soloFast)
        #expect(LeaderboardID.solo(.regular) != LeaderboardID.solo(.fast))
    }

    @Test("only the daily board is recurring")
    func onlyTheDailyBoardIsRecurring() {
        #expect(LeaderboardID.daily.isRecurring)
        #expect(LeaderboardID.allCases.filter(\.isRecurring) == [.daily])
    }

    @Test("ids are stable — the GameKit bundle is matched on these strings")
    func idsAreStable() {
        #expect(LeaderboardID.soloRegular.rawValue == "solo.regular")
        #expect(LeaderboardID.soloFast.rawValue == "solo.fast")
        #expect(LeaderboardID.daily.rawValue == "daily.deal")
        #expect(LeaderboardID.battleWins.rawValue == "battle.wins")
    }
}

@Suite("Leaderboards: what a finished game submits")
struct LeaderboardSubmissionTests {
    private let deal = dailyDeal(day: 20_000)

    @Test("a Solo game posts to its pace's board")
    func soloPostsToItsPaceBoard() {
        let posts = submissions(
            mode: .endless, pace: .fast, score: 420, daily: nil, dailyWithinDay: true,
            battleWins: 0, at: 1)
        #expect(posts.count == 1)
        #expect(posts[0].board == .soloFast)
        #expect(posts[0].score == 420)
        #expect(posts[0].day == nil, "a classic board has one occurrence")
    }

    @Test("a daily posts against the day it was started on")
    func dailyPostsAgainstItsOwnDay() {
        let posts = submissions(
            mode: .daily, pace: .regular, score: 200, daily: deal, dailyWithinDay: true,
            battleWins: 0, at: 1)
        #expect(posts.count == 1)
        #expect(posts[0].board == .daily)
        #expect(posts[0].day == deal.day)
    }

    @Test("a daily that outlived its puzzle posts nothing")
    func aLateDailyPostsNothing() {
        // The bug plan §8.2 says to pin: a recurring board would happily file
        // this against the *new* day.
        let posts = submissions(
            mode: .daily, pace: .regular, score: 200, daily: deal, dailyWithinDay: false,
            battleWins: 0, at: 1)
        #expect(posts.isEmpty)
    }

    @Test("a battle posts the running win total, since Game Center sums nothing")
    func battlePostsTheRunningTotal() {
        let posts = submissions(
            mode: .battle, pace: .regular, score: 0, daily: nil, dailyWithinDay: true,
            battleWins: 7, at: 1)
        #expect(posts == [PendingScore(board: .battleWins, score: 7, at: 1)])
    }

    @Test("the tutorial posts nothing")
    func tutorialPostsNothing() {
        #expect(
            submissions(
                mode: .tutorial, pace: .regular, score: 0, daily: nil, dailyWithinDay: true,
                battleWins: 0, at: 1
            ).isEmpty)
    }
}

@Suite("Leaderboards: the signed-out queue")
struct PendingScoresTests {
    @Test("keeps only the best score for a board")
    func keepsOnlyTheBestForABoard() {
        var queue = PendingScores()
        queue.add(PendingScore(board: .soloFast, score: 100, at: 1))
        queue.add(PendingScore(board: .soloFast, score: 400, at: 2))
        queue.add(PendingScore(board: .soloFast, score: 250, at: 3))
        #expect(queue.scores.count == 1)
        #expect(queue.scores[0].score == 400)
    }

    @Test("keeps each day's daily separately")
    func keepsEachDaySeparately() {
        var queue = PendingScores()
        queue.add(PendingScore(board: .daily, score: 100, day: 10, at: 1))
        queue.add(PendingScore(board: .daily, score: 90, day: 11, at: 2))
        #expect(queue.scores.count == 2, "different occurrences don't compete")
        queue.add(PendingScore(board: .daily, score: 150, day: 10, at: 3))
        #expect(queue.scores.count == 2)
        #expect(queue.scores.first { $0.day == 10 }?.score == 150)
    }

    @Test("keeps different boards apart")
    func keepsDifferentBoardsApart() {
        var queue = PendingScores()
        queue.add(PendingScore(board: .soloFast, score: 100, at: 1))
        queue.add(PendingScore(board: .soloRegular, score: 50, at: 2))
        #expect(queue.scores.count == 2)
    }

    @Test("submits oldest first, so a partial run keeps the newest queued")
    func submitsOldestFirst() {
        var queue = PendingScores()
        queue.add(PendingScore(board: .soloFast, score: 10, at: 300))
        queue.add(PendingScore(board: .soloRegular, score: 10, at: 100))
        queue.add(PendingScore(board: .battleWins, score: 1, at: 200))
        #expect(queue.ordered.map(\.at) == [100, 200, 300])
    }

    @Test("clearing a confirmed submission leaves a better one queued")
    func clearingLeavesABetterOneQueued() {
        var queue = PendingScores()
        queue.add(PendingScore(board: .soloFast, score: 400, at: 2))
        // A stale confirmation for a worse score must not drop the good one.
        queue.clear(PendingScore(board: .soloFast, score: 100, at: 1))
        #expect(queue.scores.count == 1)
        queue.clear(PendingScore(board: .soloFast, score: 400, at: 2))
        #expect(queue.isEmpty)
    }

    @Test("prunes entries older than the age limit")
    func prunesOldEntries() {
        var queue = PendingScores()
        let now: Double = 1_000_000_000_000
        let old = now - Double(PendingScores.maxAgeDays + 1) * 86_400_000
        queue.add(PendingScore(board: .soloFast, score: 10, at: old))
        queue.add(PendingScore(board: .soloRegular, score: 10, at: now))
        queue.prune(now: now)
        #expect(queue.scores.map(\.board) == [.soloRegular])
    }

    @Test("round-trips through storage")
    func roundTripsThroughStorage() {
        let store = MemoryKeyValueStore()
        var queue = PendingScores()
        queue.add(PendingScore(board: .daily, score: 300, day: 42, at: 9))
        queue.save(to: store)
        #expect(PendingScores.load(from: store) == queue)
    }

    @Test("garbage and stale versions fall back to an empty queue")
    func garbageFallsBackToEmpty() {
        let garbage = MemoryKeyValueStore([PendingScores.key: "{not json"])
        #expect(PendingScores.load(from: garbage).isEmpty)
        let stale = MemoryKeyValueStore([PendingScores.key: #"{"version":99,"scores":[]}"#])
        #expect(PendingScores.load(from: stale).isEmpty)
    }
}
