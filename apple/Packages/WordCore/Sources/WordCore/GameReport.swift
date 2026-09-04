import Foundation

/// What a finished game saw — the record `Progression` folds into the
/// player's totals and prices a leaderboard submission from.
///
/// New on Apple platforms: the web game has no persistent progression at all.
/// Everything here is detectable from events the game already produces (the
/// `finishGame` funnel, the `commit` funnel), so a finished game is describable
/// without the board it was played on.

/// The facts a finished game reports. Solo fills the first block; a battle
/// fills the second, and leaves it at its defaults otherwise.
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

    // Battle
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
