import Foundation

/// Leaderboards, and what to do with a score when nobody is signed in.
///
/// Plan §7.1 is blunt about this: **signed-out is a designed state, not an
/// error.** The web game needs no account, and the port must not regress that
/// when Game Center auth fails, is declined, or is restricted. Solo, the
/// tutorial and the Daily Deal all play signed out — so a score earned then
/// has to go somewhere until auth succeeds, which is what this queue is.
///
/// Nothing here imports GameKit. These are the IDs, the rules for which score
/// wins, and the holding pen; the submission itself is a dozen lines of
/// `GKLeaderboard.submitScore` that needs an account to run.

// MARK: - The boards (plan §8.1)

/// Identifiers, which **must match the GameKit bundle** synced to App Store
/// Connect. They are declared here rather than at the call site so the app and
/// the bundle have exactly one list to agree on.
public enum LeaderboardID: String, CaseIterable, Codable, Sendable {
    /// Classic, all-time, best score.
    case soloRegular = "solo.regular"
    case soloFast = "solo.fast"
    /// **Recurring**: 24h duration, 24h restart — Apple's documented
    /// daily-puzzle shape. The occurrence a score belongs to is decided by
    /// when the game *started*, not when it finished (see `DailyResult`).
    case daily = "daily.deal"
    /// Classic, all-time. Game Center never sums anything for you, so this is
    /// submitted as the running total from `MergedProgress.battleWins`.
    case battleWins = "battle.wins"

    /// Which board a finished Solo game belongs to.
    public static func solo(_ pace: SoloPace) -> LeaderboardID {
        switch pace {
        case .regular: .soloRegular
        case .fast: .soloFast
        }
    }

    /// Recurring boards need the occurrence pinned; classic ones don't.
    public var isRecurring: Bool { self == .daily }
}

// MARK: - A score waiting to be submitted

public struct PendingScore: Codable, Equatable, Sendable {
    public var board: LeaderboardID
    public var score: Int
    /// For a recurring board, the day the score belongs to. Nil for classic
    /// boards, which have exactly one occurrence.
    public var day: Int?
    /// Unix ms, for ordering and for aging the queue out.
    public var at: Double

    public init(board: LeaderboardID, score: Int, day: Int? = nil, at: Double) {
        self.board = board
        self.score = score
        self.day = day
        self.at = at
    }

    /// Two entries compete for the same slot when they'd land on the same
    /// board *and* the same occurrence.
    var slot: String { "\(board.rawValue)/\(day.map(String.init) ?? "-")" }
}

/// Scores earned while signed out, held until auth succeeds.
///
/// Deliberately small and lossy: only the best score per board-occurrence is
/// kept, because that is all a leaderboard would end up showing anyway.
/// Submitting a worse score first and a better one later is wasted network
/// and a worse story if the app is killed in between.
public struct PendingScores: Codable, Equatable, Sendable {
    /// Bumped if the shape changes; a stale queue is dropped, never migrated.
    public static let version = 1
    public static let key = "nana.pending.scores.v1"
    /// A signed-out player who never signs in shouldn't accumulate forever.
    /// Comfortably longer than any plausible "I'll sign in later".
    public static let maxAgeDays = 90

    public var version: Int = Self.version
    public var scores: [PendingScore] = []

    public init(version: Int = PendingScores.version, scores: [PendingScore] = []) {
        self.version = version
        self.scores = scores
    }

    public var isEmpty: Bool { scores.isEmpty }

    /// Queue a score, keeping only the best for its board and occurrence.
    public mutating func add(_ score: PendingScore) {
        if let index = scores.firstIndex(where: { $0.slot == score.slot }) {
            guard score.score > scores[index].score else { return }
            scores[index] = score
        } else {
            scores.append(score)
        }
    }

    /// Drop entries older than `maxAgeDays`. A stale Solo best is still worth
    /// submitting in principle, but a queue that never empties is a bug in
    /// waiting — and the score is still in the player's local stats either way.
    public mutating func prune(now: Double) {
        let cutoff = now - Double(Self.maxAgeDays) * 86_400_000
        scores.removeAll { $0.at < cutoff }
    }

    /// Everything to submit, oldest first, so a partial run leaves the most
    /// recent scores queued rather than the oldest.
    public var ordered: [PendingScore] {
        scores.sorted { $0.at < $1.at }
    }

    /// Called once a submission is confirmed.
    public mutating func clear(_ score: PendingScore) {
        scores.removeAll { $0.slot == score.slot && $0.score <= score.score }
    }

    // MARK: Storage

    public static func load(from store: KeyValueStore) -> PendingScores {
        guard let raw = store.get(key), let data = raw.data(using: .utf8) else {
            return PendingScores()
        }
        guard let queue = try? JSONDecoder().decode(PendingScores.self, from: data),
            queue.version == version
        else {
            store.remove(key)
            return PendingScores()
        }
        return queue
    }

    public func save(to store: KeyValueStore) {
        guard let data = try? JSONEncoder().encode(self),
            let text = String(data: data, encoding: .utf8)
        else { return }
        store.set(Self.key, text)
    }
}

// MARK: - What a finished game is worth submitting

/// The scores a finished game should post, given the whole merged picture.
///
/// One place decides this so the signed-in path and the queued-then-flushed
/// path can never disagree about what a game was worth.
public func submissions(
    mode: GameMode,
    pace: SoloPace,
    score: Int,
    daily: DailyDeal?,
    dailyWithinDay: Bool,
    battleWins: Int,
    at: Double
) -> [PendingScore] {
    switch mode {
    case .endless:
        return [PendingScore(board: .solo(pace), score: score, at: at)]

    case .daily:
        // A game that outlived its own puzzle is recorded but never
        // submitted: a recurring leaderboard would happily file it against
        // the *new* day's board (plan §8.2).
        guard let daily, dailyWithinDay else { return [] }
        return [PendingScore(board: .daily, score: score, day: daily.day, at: at)]

    case .battle:
        return [PendingScore(board: .battleWins, score: battleWins, at: at)]

    case .tutorial:
        // A lesson isn't a game and has no score.
        return []

    case .occupy:
        // No board is configured for it yet; the win is counted locally
        // (`Progression`) and nothing is posted.
        return []
    }
}
