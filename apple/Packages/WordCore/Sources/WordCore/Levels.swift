/// Board sizing and scoring. Ported from `src/game/levels.ts`.

/// The board a game starts on. It never shrinks below this, but it isn't a
/// hard limit either — see `boardBounds`.
public let BOARD_SIZE = 33

/// How much open board is kept beyond the outermost tile. Matches the longest
/// word the generator deals, so a word laid from the very edge outward still
/// has room to land.
public let GROW_MARGIN = 8

/// The rectangle of cells in play: the starting board, grown wherever tiles
/// have come within `GROW_MARGIN` of its edge. Play toward any side and the
/// board quietly gets bigger there — running out of room stops being possible.
/// Rows and columns can go negative; cell keys don't mind.
public func boardBounds(_ board: TileMap) -> Bounds {
    var minRow = 0
    var minCol = 0
    var maxRow = BOARD_SIZE - 1
    var maxCol = BOARD_SIZE - 1
    for key in board.keys {
        let cell = parseKey(key)
        if cell.row - GROW_MARGIN < minRow { minRow = cell.row - GROW_MARGIN }
        if cell.col - GROW_MARGIN < minCol { minCol = cell.col - GROW_MARGIN }
        if cell.row + GROW_MARGIN > maxRow { maxRow = cell.row + GROW_MARGIN }
        if cell.col + GROW_MARGIN > maxCol { maxCol = cell.col + GROW_MARGIN }
    }
    return Bounds(minRow: minRow, minCol: minCol, maxRow: maxRow, maxCol: maxCol)
}

/// Points for one word, triangular in its length so longer words are worth
/// disproportionately more than the same letters split up:
/// 3→3, 4→6, 5→10, 6→15, 7→21, 8→28. Anything too short to be a legal word
/// scores nothing.
public func wordScore(_ word: String) -> Int {
    let n = word.count
    return n < MIN_WORD_LENGTH ? 0 : (n * (n - 1)) / 2
}

/// Awarded for every tile placed on a fully valid, connected board.
public let ALL_TILES_BONUS = 50

public struct BoardScore: Equatable {
    /// Points from the words currently on the board.
    public var words: Int
    /// The all-tiles bonus, or 0 if it isn't currently earned.
    public var bonus: Int
    public var total: Int
    public var bonusEarned: Bool
}

/// What the board is worth, recomputed live from what's on it.
///
/// The board outlives each deal, so its words are scored continuously rather
/// than banked batch by batch — a word that comes back off the board takes its
/// points with it. (Bonuses are the exception: once earned they're banked,
/// since the next batch of tiles immediately makes the "every tile placed"
/// test false again.)
///
/// Only runs that are real words pay out, and a tile at a crossing counts
/// towards both of its words — interlocking boards are worth more than the
/// same tiles laid out in a line.
public func scoreBoard(_ validation: BoardValidation?, tilesLeft: Int) -> BoardScore {
    var words = 0
    if let validation {
        for run in validation.runs where run.valid {
            words += wordScore(run.word)
        }
    }
    let bonusEarned = tilesLeft == 0 && validation != nil && validation!.ok
    let bonus = bonusEarned ? ALL_TILES_BONUS : 0
    return BoardScore(words: words, bonus: bonus, total: words + bonus, bonusEarned: bonusEarned)
}
