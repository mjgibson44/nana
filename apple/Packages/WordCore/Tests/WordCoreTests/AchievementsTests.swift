import Foundation
import Testing

@testable import WordCore

/// The launch achievement set (plan §8.3). The evaluator is pure, so every
/// rule is pinned here rather than discovered on a device.

private final class MemoryKVStore: KeyValueStore {
    var values: [String: String]
    init(_ values: [String: String] = [:]) { self.values = values }
    func get(_ key: String) -> String? { values[key] }
    func set(_ key: String, _ value: String) { values[key] = value }
    func remove(_ key: String) { values[key] = nil }
}

private func percent(
    _ id: AchievementID, _ result: [AchievementProgress]
) -> Double? {
    result.first { $0.id == id }?.percentComplete
}

/// Partial progress is a division, so compare it as one — the evaluator
/// computes `value / target * 100`, which is a ULP away from `value * 100 /
/// target` however the expectation is written.
private func isNear(_ value: Double?, _ expected: Double) -> Bool {
    guard let value else { return false }
    return abs(value - expected) < 1e-9
}

@Suite("Achievements: the set")
struct AchievementSetTests {
    @Test("is the fifteen the plan lists, with unique ids")
    func isTheFifteenThePlanLists() {
        #expect(AchievementID.allCases.count == 15)
        #expect(Set(AchievementID.allCases.map(\.rawValue)).count == 15)
    }

    @Test("every one has a title and a detail")
    func everyOneHasCopy() {
        for id in AchievementID.allCases {
            #expect(!id.title.isEmpty)
            #expect(!id.detail.isEmpty)
        }
    }

    @Test("six wait on battle, and nine can be earned today")
    func sixWaitOnBattle() {
        let battle = AchievementID.allCases.filter(\.needsBattle)
        #expect(battle.count == 6)
        #expect(AchievementID.allCases.count - battle.count == 9)
    }
}

@Suite("Achievements: Solo")
struct AchievementSoloTests {
    @Test("finishing a Solo game earns the first one and moves the counter")
    func finishingSoloEarnsTheFirst() {
        let result = achievementProgress(
            for: GameReport(mode: .endless, score: 100),
            progress: MergedProgress(gamesPlayed: 1))
        #expect(percent(.firstSoloGame, result) == 100)
        #expect(percent(.hundredGames, result) == 1)
    }

    @Test("Solo Fast scores toward the 500 badge, regular doesn't")
    func fastScoresTowardTheBadge() {
        let fast = achievementProgress(
            for: GameReport(mode: .endless, pace: .fast, score: 250),
            progress: MergedProgress(gamesPlayed: 1))
        #expect(percent(.fastFiveHundred, fast) == 50)

        let regular = achievementProgress(
            for: GameReport(mode: .endless, pace: .regular, score: 250),
            progress: MergedProgress(gamesPlayed: 1))
        #expect(percent(.fastFiveHundred, regular) == nil)
    }

    @Test("a score past the target caps at 100 rather than overflowing")
    func scorePastTheTargetCaps() {
        let result = achievementProgress(
            for: GameReport(mode: .endless, pace: .fast, score: 5_000),
            progress: MergedProgress(gamesPlayed: 1))
        #expect(percent(.fastFiveHundred, result) == 100)
    }

    @Test("board clears count toward the sweep")
    func boardClearsCount() {
        let result = achievementProgress(
            for: GameReport(mode: .endless, boardClears: 2),
            progress: MergedProgress(gamesPlayed: 1))
        #expect(isNear(percent(.pileClearer, result), 200.0 / 3))
    }

    @Test("digging back under the limit earns the comeback")
    func diggingBackUnderEarnsTheComeback() {
        let dug = achievementProgress(
            for: GameReport(mode: .endless, recoveredFromOverLimit: true),
            progress: MergedProgress(gamesPlayed: 1))
        #expect(percent(.comeback, dug) == 100)
        let never = achievementProgress(
            for: GameReport(mode: .endless), progress: MergedProgress(gamesPlayed: 1))
        #expect(percent(.comeback, never) == nil)
    }
}

@Suite("Achievements: board play")
struct AchievementBoardTests {
    @Test("an eight-letter word counts in any mode")
    func eightLetterWordCountsAnywhere() {
        for mode in [GameMode.endless, .daily] {
            let result = achievementProgress(
                for: GameReport(mode: mode, longestWord: 8),
                progress: MergedProgress(gamesPlayed: 1), today: 10)
            #expect(percent(.eightLetterWord, result) == 100, "\(mode)")
        }
    }

    @Test("seven letters is not eight")
    func sevenIsNotEight() {
        let result = achievementProgress(
            for: GameReport(mode: .endless, longestWord: 7),
            progress: MergedProgress(gamesPlayed: 1))
        #expect(percent(.eightLetterWord, result) == nil)
    }

    @Test("a gap tile earns its badge")
    func gapTileEarnsItsBadge() {
        let result = achievementProgress(
            for: GameReport(mode: .endless, usedGapTile: true),
            progress: MergedProgress(gamesPlayed: 1))
        #expect(percent(.gapTile, result) == 100)
    }
}

@Suite("Achievements: the Daily Deal and the tutorial")
struct AchievementDailyTests {
    @Test("the weekly streak reads from the merged picture, not one device")
    func weeklyStreakReadsTheMergedPicture() {
        let progress = MergedProgress(gamesPlayed: 4, dailyDays: [10, 9, 8, 7])
        let result = achievementProgress(
            for: GameReport(mode: .daily), progress: progress, today: 10)
        #expect(isNear(percent(.dailyWeek, result), 400.0 / 7))
    }

    @Test("seven in a row completes it")
    func sevenInARowCompletesIt() {
        let progress = MergedProgress(
            gamesPlayed: 7, dailyDays: Set((4...10)))
        let result = achievementProgress(
            for: GameReport(mode: .daily), progress: progress, today: 10)
        #expect(percent(.dailyWeek, result) == 100)
    }

    @Test("the tutorial earns only its own badge and no game counter")
    func tutorialEarnsOnlyItsOwn() {
        let result = achievementProgress(
            for: GameReport(mode: .tutorial, tutorialFinished: true),
            progress: MergedProgress(gamesPlayed: 0))
        #expect(percent(.tutorialDone, result) == 100)
        #expect(percent(.hundredGames, result) == nil, "a lesson isn't a game")
        #expect(result.count == 1)
    }

    @Test("an abandoned tutorial earns nothing")
    func abandonedTutorialEarnsNothing() {
        let result = achievementProgress(
            for: GameReport(mode: .tutorial, tutorialFinished: false),
            progress: MergedProgress())
        #expect(result.isEmpty)
    }
}

@Suite("Achievements: battle (dark until phase 4)")
struct AchievementBattleTests {
    private func won(_ report: GameReport, wins: Int = 1) -> [AchievementProgress] {
        achievementProgress(
            for: report, progress: MergedProgress(gamesPlayed: 1, battleWins: wins),
            consecutiveBattleWins: wins)
    }

    @Test("a win earns the first-win badge")
    func aWinEarnsTheFirstWinBadge() {
        let result = won(GameReport(mode: .battle, battleWon: true, battlePlayers: 4))
        #expect(percent(.firstBattleWon, result) == 100)
    }

    @Test("a loss earns neither the win nor the win-only badges")
    func aLossEarnsNoWinBadges() {
        let result = won(
            GameReport(mode: .battle, battleWon: false, battlePlayers: 8, battlePeakPile: 2))
        #expect(percent(.firstBattleWon, result) == nil)
        #expect(percent(.eightPlayerBattle, result) == nil)
        #expect(percent(.cleanBattleWin, result) == nil)
    }

    @Test("a full field has to be won, not merely joined")
    func aFullFieldHasToBeWon() {
        let full = won(GameReport(mode: .battle, battleWon: true, battlePlayers: 8))
        #expect(percent(.eightPlayerBattle, full) == 100)
        let small = won(GameReport(mode: .battle, battleWon: true, battlePlayers: 7))
        #expect(percent(.eightPlayerBattle, small) == nil)
    }

    @Test("a clean win means the pile never passed the limit")
    func aCleanWinMeansTheLimitHeld() {
        let clean = won(
            GameReport(mode: .battle, battleWon: true, battlePeakPile: ACHIEVEMENT_CLEAN_PILE))
        #expect(percent(.cleanBattleWin, clean) == 100)
        let messy = won(
            GameReport(mode: .battle, battleWon: true, battlePeakPile: ACHIEVEMENT_CLEAN_PILE + 1))
        #expect(percent(.cleanBattleWin, messy) == nil)
    }

    @Test("back to back needs two in a row")
    func backToBackNeedsTwo() {
        #expect(percent(.backToBack, won(GameReport(mode: .battle, battleWon: true), wins: 1)) == 50)
        #expect(percent(.backToBack, won(GameReport(mode: .battle, battleWon: true), wins: 2)) == 100)
    }

    @Test("reaching the final round counts even in a loss")
    func finalRoundCountsEvenInALoss() {
        let result = won(
            GameReport(mode: .battle, battleWon: false, battleReachedFinalRound: true))
        #expect(percent(.battleFinalRound, result) == 100)
    }

    @Test("attack tiles accumulate toward their badge")
    func attackTilesAccumulate() {
        let result = won(GameReport(mode: .battle, attackTilesSent: 5))
        #expect(percent(.bigAttack, result) == 20)
    }

    @Test("a Solo game never earns a battle badge")
    func soloNeverEarnsABattleBadge() {
        let result = achievementProgress(
            for: GameReport(mode: .endless, score: 900, longestWord: 8, usedGapTile: true),
            progress: MergedProgress(gamesPlayed: 50, battleWins: 9))
        #expect(result.allSatisfy { !$0.id.needsBattle })
    }
}

@Suite("Achievements: the signed-out queue")
struct PendingAchievementsTests {
    @Test("keeps the highest percent seen")
    func keepsTheHighestPercent() {
        var queue = PendingAchievements()
        queue.add([AchievementProgress(id: .hundredGames, percentComplete: 40)])
        queue.add([AchievementProgress(id: .hundredGames, percentComplete: 70)])
        queue.add([AchievementProgress(id: .hundredGames, percentComplete: 55)])
        #expect(queue.best[AchievementID.hundredGames.rawValue] == 70)
        #expect(queue.ordered.count == 1)
    }

    @Test("clamps a nonsense percent into range")
    func clampsNonsensePercent() {
        #expect(AchievementProgress(id: .gapTile, percentComplete: 900).percentComplete == 100)
        #expect(AchievementProgress(id: .gapTile, percentComplete: -5).percentComplete == 0)
    }

    @Test("clearing a reported achievement drops it")
    func clearingDropsIt() {
        var queue = PendingAchievements()
        queue.add([
            AchievementProgress(id: .gapTile, percentComplete: 100),
            AchievementProgress(id: .comeback, percentComplete: 100),
        ])
        queue.clear(.gapTile)
        #expect(queue.ordered.map(\.id) == [.comeback])
    }

    @Test("round-trips through storage, and garbage falls back to empty")
    func roundTripsThroughStorage() {
        let store = MemoryKVStore()
        var queue = PendingAchievements()
        queue.add([AchievementProgress(id: .dailyWeek, percentComplete: 42)])
        queue.save(to: store)
        #expect(PendingAchievements.load(from: store) == queue)

        let garbage = MemoryKVStore([PendingAchievements.key: "nope"])
        #expect(PendingAchievements.load(from: garbage).isEmpty)
    }

    @Test("an unknown id in storage is dropped rather than crashing")
    func unknownIdIsDropped() {
        var queue = PendingAchievements()
        queue.best["not.a.real.achievement"] = 100
        #expect(queue.ordered.isEmpty)
    }
}
