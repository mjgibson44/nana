/**
 * Game modes.
 *
 * One board and one set of rules for building words, three ways to play them:
 *
 *  - Solo Puzzle: the classic five-level climb, no clock.
 *  - Solo Timed: the same climb, but each level must be finished before its
 *    clock runs out — 3:00 for the first, 2:00 for the second, and 15 seconds
 *    less for every level after that.
 *  - Endless: no levels. New tiles keep arriving on a clock that speeds up as
 *    you last (and as a reward for clearing the pile); let too many pile up
 *    loose and the game ends.
 */

export type GameMode = 'puzzle' | 'timed' | 'endless';

export interface ModeInfo {
  id: GameMode;
  name: string;
  tagline: string;
  /** Short bullet lines for the mode's card on the home screen. */
  details: string[];
}

export const MODES: ModeInfo[] = [
  {
    id: 'puzzle',
    name: 'Solo Puzzle',
    tagline: 'The classic climb, at your own pace.',
    details: ['5 levels, 20 tiles to start', '+10 tiles each level', 'No clock — take your time'],
  },
  {
    id: 'timed',
    name: 'Solo Timed',
    tagline: 'The same climb, against the clock.',
    details: [
      '3:00 for level 1, 2:00 for level 2',
      '15 seconds less each level after',
      'Out of time means game over',
    ],
  },
  {
    id: 'endless',
    name: 'Endless',
    tagline: 'Survive the ever-growing pile.',
    details: [
      '2:00 to place your first 20 tiles',
      '+5 tiles a minute, and it speeds up',
      '20 loose tiles and you’re buried',
    ],
  },
];

export function modeName(mode: GameMode): string {
  return MODES.find((m) => m.id === mode)?.name ?? mode;
}

/* ------------------------------- Solo Timed ------------------------------- */

const TIMED_FIRST_LEVEL_SECONDS = 180;
const TIMED_SECOND_LEVEL_SECONDS = 120;
const TIMED_STEP_SECONDS = 15;

/** The clock a Solo Timed level starts with: 3:00, then 2:00, then 15s less
 * per level (1:45, 1:30, 1:15…). */
export function timedLevelSeconds(level: number): number {
  if (level <= 1) return TIMED_FIRST_LEVEL_SECONDS;
  return TIMED_SECOND_LEVEL_SECONDS - (level - 2) * TIMED_STEP_SECONDS;
}

/* -------------------------------- Endless --------------------------------- */

/** The opening phase: this long to work the starting pile before tiles start
 * arriving — and before the health bar switches on. */
export const ENDLESS_INITIAL_SECONDS = 120;

/**
 * After the opening phase, batches land on a clock that keeps tightening: the
 * first few arrive a minute apart, then every 45 seconds, then every 30 —
 * where it stays until the pile buries the player.
 */
export const ENDLESS_DRIP_STAGES = [60, 45, 30];

/** How many drip intervals each stage lasts before the next one takes over. */
export const ENDLESS_INTERVALS_PER_STAGE = 3;

/**
 * How long the wait for the next batch is, given how many drip intervals have
 * already run out. The opening phase isn't one of them, so the first three
 * waits after it are all the opening stage's length.
 */
export function endlessDripSeconds(intervalsElapsed: number): number {
  const stage = Math.floor(intervalsElapsed / ENDLESS_INTERVALS_PER_STAGE);
  return ENDLESS_DRIP_STAGES[Math.min(stage, ENDLESS_DRIP_STAGES.length - 1)];
}

/** How many tiles each timed batch brings. */
export const ENDLESS_DRIP_TILES = 5;

/** Clearing the pile — every tile placed and connected — feeds the board the
 * same size batch as a timed drop. */
export const ENDLESS_CLEAR_TILES = 5;

/** Points for having every tile placed on a fully connected, valid board. */
export const ENDLESS_CONNECT_BONUS = 25;

/** Loose tiles — in the pile, or on the board but not validly connected —
 * are the health bar. Reach this many and the game is over. */
export const ENDLESS_LOOSE_LIMIT = 20;

/* --------------------------------- shared --------------------------------- */

/** Whole seconds as "m:ss" for the header clock and splashes. */
export function formatSeconds(totalSeconds: number): string {
  const clamped = Math.max(0, Math.floor(totalSeconds));
  const minutes = Math.floor(clamped / 60);
  const seconds = clamped % 60;
  return `${minutes}:${String(seconds).padStart(2, '0')}`;
}
