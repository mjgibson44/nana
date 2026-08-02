import { MIN_WORD_LENGTH, type BoardValidation } from './board';
import type { Bounds, TileMap } from './types';
import { parseKey } from './types';

/**
 * Board sizing and scoring.
 *
 * The letters always come from the generator, which grows real crossing words —
 * off the tiles already down, for a batch that adds to a board — so every batch
 * is known to have at least one arrangement that plays all of it, and because
 * the letters come from several ordinary words there are normally many others.
 */

/**
 * The board a game starts on. It never shrinks below this, but it isn't a
 * hard limit either — see `boardBounds`.
 */
export const BOARD_SIZE = 33;

/**
 * How much open board is kept beyond the outermost tile. Matches the longest
 * word the generator deals, so a word laid from the very edge outward still
 * has room to land.
 */
export const GROW_MARGIN = 8;

/**
 * The rectangle of cells in play: the starting board, grown wherever tiles
 * have come within `GROW_MARGIN` of its edge. Play toward any side and the
 * board quietly gets bigger there — running out of room stops being possible.
 * Rows and columns can go negative; cell keys don't mind.
 */
export function boardBounds(board: TileMap): Bounds {
  let minRow = 0;
  let minCol = 0;
  let maxRow = BOARD_SIZE - 1;
  let maxCol = BOARD_SIZE - 1;
  for (const key of Object.keys(board)) {
    const { row, col } = parseKey(key);
    if (row - GROW_MARGIN < minRow) minRow = row - GROW_MARGIN;
    if (col - GROW_MARGIN < minCol) minCol = col - GROW_MARGIN;
    if (row + GROW_MARGIN > maxRow) maxRow = row + GROW_MARGIN;
    if (col + GROW_MARGIN > maxCol) maxCol = col + GROW_MARGIN;
  }
  return { minRow, minCol, maxRow, maxCol };
}

/**
 * Points for one word, triangular in its length so longer words are worth
 * disproportionately more than the same letters split up:
 * 3→3, 4→6, 5→10, 6→15, 7→21, 8→28. Anything too short to be a legal word
 * scores nothing.
 */
export function wordScore(word: string): number {
  const n = word.length;
  return n < MIN_WORD_LENGTH ? 0 : (n * (n - 1)) / 2;
}

/** Awarded for every tile placed on a fully valid, connected board. */
export const ALL_TILES_BONUS = 50;

export interface BoardScore {
  /** Points from the words currently on the board. */
  words: number;
  /** The all-tiles bonus, or 0 if it isn't currently earned. */
  bonus: number;
  total: number;
  bonusEarned: boolean;
}

/**
 * What the board is worth, recomputed live from what's on it.
 *
 * The board outlives each deal, so its words are scored continuously rather
 * than banked batch by batch — a word that comes back off the board takes its
 * points with it. (Bonuses are the exception: once earned they're banked,
 * since the next batch of tiles immediately makes the "every tile placed"
 * test false again.)
 *
 * Only runs that are real words pay out, and a tile at a crossing counts
 * towards both of its words — interlocking boards are worth more than the same
 * tiles laid out in a line.
 */
export function scoreBoard(validation: BoardValidation | null, tilesLeft: number): BoardScore {
  let words = 0;
  if (validation) {
    for (const run of validation.runs) {
      if (run.valid) words += wordScore(run.word);
    }
  }
  const bonusEarned = tilesLeft === 0 && validation !== null && validation.ok;
  const bonus = bonusEarned ? ALL_TILES_BONUS : 0;
  return { words, bonus, total: words + bonus, bonusEarned };
}
