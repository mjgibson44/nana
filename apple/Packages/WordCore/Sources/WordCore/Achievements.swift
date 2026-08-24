import Foundation

/// The launch achievement set (plan §8.3), and the pure rule for deciding
/// what a finished game earned.
///
/// New on Apple platforms: the web game has no persistent progression at all.
/// Every one of these is detectable from events the game already produces —
/// the `finishGame` funnel, the `commit` funnel, and the merged cross-device
/// picture — which is what kept the set to fifteen rather than inventing
/// mechanics to hang badges off.
///
/// GameKit reports achievements as a *percent complete* and is happy to be
/// told the same thing twice, so the evaluator returns the current standing of
/// everything a game could have moved rather than trying to diff against what
/// was reported before. That makes it idempotent, which in turn makes the
/// signed-out queue (`Leaderboards.swift`) trivial: re-reporting on sign-in is
/// always safe.

// MARK: - Targets

/// Board clears in a single Solo game.
public let ACHIEVEMENT_PILE_CLEARS = 3
/// Daily Deals in a row.
public let ACHIEVEMENT_DAILY_STREAK = 7
/// Points in one Solo Fast game.
public let ACHIEVEMENT_FAST_SCORE = 500
/// Attack tiles sent in one battle.
public let ACHIEVEMENT_ATTACK_TILES = 25
/// Games finished, all modes.
public let ACHIEVEMENT_GAMES_PLAYED = 100
/// Never exceeding this pile makes a battle win a "clean" one.
public let ACHIEVEMENT_CLEAN_PILE = 15
/// A full field.
public let ACHIEVEMENT_FULL_FIELD = BATTLE_MAX_PLAYERS

public enum AchievementID: String, CaseIterable, Codable, Sendable {
    case firstSoloGame = "first.solo"
    case tutorialDone = "tutorial.done"
    case gapTile = "gap.tile"
    case eightLetterWord = "word.eight"
    case pileClearer = "pile.clearer"
    case comeback = "comeback"
    case fastFiveHundred = "fast.500"
    case hundredGames = "games.100"
    case dailyWeek = "daily.week"
    case firstBattleWon = "battle.first"
    case backToBack = "battle.backtoback"
    case eightPlayerBattle = "battle.fullfield"
    case battleFinalRound = "battle.finalround"
    case cleanBattleWin = "battle.clean"
    case bigAttack = "battle.attack"

    public var title: String {
        switch self {
        case .firstSoloGame: "First Deal"
        case .tutorialDone: "Shown the Ropes"
        case .gapTile: "Borrowed Letter"
        case .eightLetterWord: "Eight Across"
        case .pileClearer: "Clean Sweep"
        case .comeback: "Dug Out"
        case .fastFiveHundred: "Quick Study"
        case .hundredGames: "Regular"
        case .dailyWeek: "Seven Days"
        case .firstBattleWon: "Last One Standing"
        case .backToBack: "Back to Back"
        case .eightPlayerBattle: "Full House"
        case .battleFinalRound: "Down to Two"
        case .cleanBattleWin: "Never Flustered"
        case .bigAttack: "Heavy Weather"
        }
    }

    public var detail: String {
        switch self {
        case .firstSoloGame: "Finish your first Solo game."
        case .tutorialDone: "Finish the tutorial."
        case .gapTile: "Play a word through a gap tile."
        case .eightLetterWord: "Place an eight-letter word."
        case .pileClearer: "Clear the board \(ACHIEVEMENT_PILE_CLEARS) times in one Solo game."
        case .comeback: "Come back from over the limit in Solo."
        case .fastFiveHundred: "Score \(ACHIEVEMENT_FAST_SCORE) in Solo Fast."
        case .hundredGames: "Finish \(ACHIEVEMENT_GAMES_PLAYED) games."
        case .dailyWeek: "Play \(ACHIEVEMENT_DAILY_STREAK) Daily Deals in a row."
        case .firstBattleWon: "Win a battle."
        case .backToBack: "Win two battles in a row."
        case .eightPlayerBattle: "Win a battle with a full field of \(ACHIEVEMENT_FULL_FIELD)."
        case .battleFinalRound: "Survive to a battle's final round."
        case .cleanBattleWin: "Win a battle without ever passing \(ACHIEVEMENT_CLEAN_PILE) pile tiles."
        case .bigAttack: "Send \(ACHIEVEMENT_ATTACK_TILES) attack tiles in one game."
        }
    }

    /// Whether it can only be earned in a battle — everything here is dark
    /// until phase 4 wires the battle fields of `GameReport`.
    public var needsBattle: Bool {
        switch self {
        case .firstBattleWon, .backToBack, .eightPlayerBattle, .battleFinalRound,
            .cleanBattleWin, .bigAttack:
            true
        default:
            false
        }
    }
}

// MARK: - What a finished game saw

/// The facts a finished game reports. Solo and Daily fill the first block;
/// the battle block stays at its defaults until phase 4 feeds it, at which
/// point six achievements light up with no change here.
public struct GameReport: Equatable, Sendable {
    public var mode: GameMode
    public var pace: SoloPace
    public var score: Int
    /// Longest valid word this game put on the board.
    public var longestWord: Int
    public var usedGapTile: Bool
    public var boardClears: Int
    /// Whether the player was ever over the loose limit and got back under it.
    public var recoveredFromOverLimit: Bool
    public var tutorialFinished: Bool

    // Battle (phase 4)
    public var battleWon: Bool
    public var battlePlayers: Int
    public var battleReachedFinalRound: Bool
    /// The largest the pile ever got.
    public var battlePeakPile: Int
    public var attackTilesSent: Int

    public init(
        mode: GameMode,
        pace: SoloPace = .regular,
        score: Int = 0,
        longestWord: Int = 0,
        usedGapTile: Bool = false,
        boardClears: Int = 0,
        recoveredFromOverLimit: Bool = false,
        tutorialFinished: Bool = false,
        battleWon: Bool = false,
        battlePlayers: Int = 0,
        battleReachedFinalRound: Bool = false,
        battlePeakPile: Int = 0,
        attackTilesSent: Int = 0
    ) {
        self.mode = mode
        self.pace = pace
        self.score = score
        self.longestWord = longestWord
        self.usedGapTile = usedGapTile
        self.boardClears = boardClears
        self.recoveredFromOverLimit = recoveredFromOverLimit
        self.tutorialFinished = tutorialFinished
        self.battleWon = battleWon
        self.battlePlayers = battlePlayers
        self.battleReachedFinalRound = battleReachedFinalRound
        self.battlePeakPile = battlePeakPile
        self.attackTilesSent = attackTilesSent
    }
}

/// One achievement's standing, in GameKit's own unit.
public struct AchievementProgress: Equatable, Sendable {
    public var id: AchievementID
    /// 0…100. 100 means earned.
    public var percentComplete: Double

    public init(id: AchievementID, percentComplete: Double) {
        self.id = id
        self.percentComplete = min(100, max(0, percentComplete))
    }

    public var isComplete: Bool { percentComplete >= 100 }
}

/// What a finished game moved.
///
/// Returns only achievements this game actually advanced — reporting 0% for
/// the other fourteen every time would be noise on the wire and, on a fresh
/// account, would create every achievement at zero for no reason.
///
/// - Parameters:
///   - report: what the game saw.
///   - progress: the merged cross-device picture *including* this game.
///   - consecutiveBattleWins: wins in a row ending with this game.
public func achievementProgress(
    for report: GameReport,
    progress: MergedProgress,
    consecutiveBattleWins: Int = 0,
    today: Int? = nil
) -> [AchievementProgress] {
    var earned: [AchievementProgress] = []

    func note(_ id: AchievementID, _ percent: Double) {
        guard percent > 0 else { return }
        earned.append(AchievementProgress(id: id, percentComplete: percent))
    }

    func fraction(_ value: Int, of target: Int) -> Double {
        guard target > 0 else { return 0 }
        return min(100, Double(value) / Double(target) * 100)
    }

    // Any finished game moves the lifetime counter.
    if report.mode != .tutorial {
        note(.hundredGames, fraction(progress.gamesPlayed, of: ACHIEVEMENT_GAMES_PLAYED))
    }

    switch report.mode {
    case .tutorial:
        if report.tutorialFinished { note(.tutorialDone, 100) }
    case .endless:
        note(.firstSoloGame, 100)
        if report.pace == .fast {
            note(.fastFiveHundred, fraction(report.score, of: ACHIEVEMENT_FAST_SCORE))
        }
        if report.recoveredFromOverLimit { note(.comeback, 100) }
        note(.pileClearer, fraction(report.boardClears, of: ACHIEVEMENT_PILE_CLEARS))
    case .daily:
        if let today {
            note(.dailyWeek, fraction(progress.dailyStreak(today: today), of: ACHIEVEMENT_DAILY_STREAK))
        }
    case .battle:
        note(.bigAttack, fraction(report.attackTilesSent, of: ACHIEVEMENT_ATTACK_TILES))
        if report.battleReachedFinalRound { note(.battleFinalRound, 100) }
        if report.battleWon {
            note(.firstBattleWon, 100)
            note(.backToBack, fraction(consecutiveBattleWins, of: 2))
            if report.battlePlayers >= ACHIEVEMENT_FULL_FIELD { note(.eightPlayerBattle, 100) }
            if report.battlePeakPile <= ACHIEVEMENT_CLEAN_PILE { note(.cleanBattleWin, 100) }
        }
    }

    // Board achievements don't care which mode built the board.
    if report.usedGapTile { note(.gapTile, 100) }
    if report.longestWord >= 8 { note(.eightLetterWord, 100) }

    return earned
}

// MARK: - Reports waiting to be sent

/// Achievements earned while signed out (plan §7.1), held until auth succeeds.
///
/// Only the *highest* percent per achievement is kept — GameKit ignores a
/// report lower than what it already holds, so sending the rest is pure waste.
public struct PendingAchievements: Codable, Equatable, Sendable {
    public static let version = 1
    public static let key = "nana.pending.achievements.v1"

    public var version: Int = Self.version
    /// Achievement ID → best percent seen.
    public var best: [String: Double] = [:]

    public init(version: Int = PendingAchievements.version, best: [String: Double] = [:]) {
        self.version = version
        self.best = best
    }

    public var isEmpty: Bool { best.isEmpty }

    public mutating func add(_ progress: [AchievementProgress]) {
        for item in progress {
            let key = item.id.rawValue
            if let existing = best[key], existing >= item.percentComplete { continue }
            best[key] = item.percentComplete
        }
    }

    public var ordered: [AchievementProgress] {
        best.compactMap { key, percent in
            AchievementID(rawValue: key).map { AchievementProgress(id: $0, percentComplete: percent) }
        }
        .sorted { $0.id.rawValue < $1.id.rawValue }
    }

    public mutating func clear(_ id: AchievementID) {
        best[id.rawValue] = nil
    }

    // MARK: Storage

    public static func load(from store: KeyValueStore) -> PendingAchievements {
        guard let raw = store.get(key), let data = raw.data(using: .utf8) else {
            return PendingAchievements()
        }
        guard let queue = try? JSONDecoder().decode(PendingAchievements.self, from: data),
            queue.version == version
        else {
            store.remove(key)
            return PendingAchievements()
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
