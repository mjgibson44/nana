import { MIN_WORD_LENGTH, type BoardValidation } from './board';

/**
 * Levels and scoring.
 *
 * One board runs the whole game. Level one deals 20 tiles onto an empty board;
 * each level after that keeps everything already played and adds 10 more tiles,
 * up to 60 by level five.
 *
 * The letters always come from the generator, which grows real crossing words —
 * off the tiles already down, for a level that adds to a board — so every batch
 * is known to have at least one arrangement that plays all of it, and because
 * the letters come from several ordinary words there are normally many others.
 */

export const LEVEL_COUNT = 5;

/** Names for the splash that announces each level, in order. */
const LEVEL_NAMES = ['First Bunch', 'Branching Out', 'Full Hands', 'Overflowing', 'Whole Tree'];

export function levelName(level: number): string {
  return LEVEL_NAMES[level - 1] ?? `Level ${level}`;
}

const FIRST_LEVEL_TILES = 20;
const TILES_PER_LEVEL = 10;

/** Total tiles dealt by the end of `level`, counting everything before it. */
export function tilesForLevel(level: number): number {
  return FIRST_LEVEL_TILES + (level - 1) * TILES_PER_LEVEL;
}

/** How many new tiles arrive when moving up to `level`. */
export function tilesAddedForLevel(level: number): number {
  return level <= 1 ? FIRST_LEVEL_TILES : TILES_PER_LEVEL;
}

/**
 * One board, one size, for the whole game.
 *
 * It can't be sized per level any more: the board is never cleared, so it must
 * never shrink under tiles already played, and by level five it has to hold all
 * 60 of them. Generated 60-tile crosswords span up to 28 squares, so this
 * leaves room to spread wider than the tightest arrangement would.
 */
export const BOARD_SIZE = 33;

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

/** Awarded when a level ends with every tile placed on a fully valid board. */
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
 * The board outlives each level, so its words are scored continuously rather
 * than banked level by level — a word that comes back off the board takes its
 * points with it. (Bonuses are the exception: once a level is left behind its
 * bonus is locked in, since the next level's new tiles immediately make the
 * "every tile placed" test false again.)
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
