/**
 * Game modes.
 *
 * One board and one set of rules for building words, played three ways:
 *
 *  - Endless: no levels. New tiles keep arriving on a clock; let too many
 *    pile up loose and the game ends. Played solo, or as Endless Battle —
 *    the same game raced by several players on one shared deal.
 *  - Duel: head-to-head for exactly two players. Placed words are permanent,
 *    and every word you place sends tiles to your opponent. First player to
 *    overflow their pile loses.
 *  - Tutorial: a guided walk through placing words, at your own pace.
 */

export type GameMode = 'endless' | 'duel' | 'tutorial';

export interface ModeInfo {
  name: string;
  tagline: string;
  /** Short bullet lines for the mode's card on the home screen. */
  details: string[];
}

export const ENDLESS_INFO: ModeInfo = {
  name: 'Endless',
  tagline: 'Survive the ever-growing pile.',
  details: [
    '2:00 to place your first 20 tiles',
    '+5 tiles every 30 seconds, growing to +7',
    'Over 20 loose tiles when a round ends and you’re out',
  ],
};

/**
 * Endless Battle's home-screen card. Each player's game runs as Endless, and
 * the multiplayer wrapping (lobby, shared deal, standings) lives in
 * src/game/battle.ts.
 */
export const BATTLE_INFO: ModeInfo = {
  name: 'Endless Battle',
  tagline: 'Endless, against your friends.',
  details: [
    'Every player gets the same tiles',
    'Host a lobby, or join with a code',
    'Outlast the rest — top score wins',
  ],
};

export const DUEL_INFO: ModeInfo = {
  name: 'Duel',
  tagline: 'Head-to-head. Bury your opponent.',
  details: [
    'Two players, same tiles',
    'Placed words are permanent — and send tiles to your opponent',
    'Overflow 25 tiles in your pile and you lose',
  ],
};

export const TUTORIAL_INFO: ModeInfo = {
  name: 'Tutorial',
  tagline: 'Learn the game in two quick steps.',
  details: ['Place your first word', 'Cross words with the gap tile', 'No clock, no pressure'],
};

/* -------------------------------- Endless --------------------------------- */

/** Tiles in the opening Endless deal. */
export const ENDLESS_START_TILES = 20;

/** The opening phase: this long to work the starting pile before tiles start
 * arriving — and before the loose-tile count switches on. */
export const ENDLESS_INITIAL_SECONDS = 120;

/** After the opening phase, every round is this long. */
export const ENDLESS_DRIP_SECONDS = 30;

/** The batch size rounds start at, and how many rounds it lasts. */
export const ENDLESS_SMALL_BATCH = 5;
export const ENDLESS_SMALL_BATCH_ROUNDS = 5;

/** The batch size every round deals once the small rounds are spent. */
export const ENDLESS_BIG_BATCH = 7;

/**
 * How long the wait for the next batch is. Every drip round is the same
 * length now; the function stays so callers don't care.
 */
export function endlessDripSeconds(_intervalsElapsed: number): number {
  return ENDLESS_DRIP_SECONDS;
}

/**
 * How many tiles the batch landing after `intervalsElapsed` drip intervals
 * brings: five for each of the first five rounds, then seven forever.
 */
export function endlessDripTiles(intervalsElapsed: number): number {
  return intervalsElapsed < ENDLESS_SMALL_BATCH_ROUNDS ? ENDLESS_SMALL_BATCH : ENDLESS_BIG_BATCH;
}

/** Clearing the pile — every tile placed and connected — feeds the board a
 * small fixed batch, whatever size the timed drops have grown to. */
export const ENDLESS_CLEAR_TILES = 5;

/** Points for having every tile placed on a fully connected, valid board. */
export const ENDLESS_CONNECT_BONUS = 25;

/** Loose tiles — in the pile, or on the board but not validly connected —
 * are the pressure gauge. Going over this limit is survivable; still being
 * over it when a drip round ends is what ends the game. */
export const ENDLESS_LOOSE_LIMIT = 20;

/* ---------------------------------- Duel ----------------------------------- */

/** Tiles in each player's opening Duel deal. */
export const DUEL_START_TILES = 15;

/** A Duel pile may never exceed this many tiles — one over and you lose. */
export const DUEL_PILE_LIMIT = 25;

/** How many rounds a duel has. The last one runs until somebody loses. */
export const DUEL_ROUNDS = 3;

/** Rounds one and two are this long; the final round has no clock. */
export const DUEL_ROUND_SECONDS = 180;

/** How often the drip lands a tile (or several) in each player's pile. */
export const DUEL_DRIP_SECONDS = 20;

/** How many tiles the drip brings per round: 1, then 2, then 4. */
const DUEL_DRIP_TILES = [1, 2, 4];

/** How hard words hit per round: attacks are ×1, then ×1.5, then ×2. */
const DUEL_ATTACK_MULTIPLIERS = [1, 1.5, 2];

function clampRound(round: number): number {
  return Math.max(1, Math.min(DUEL_ROUNDS, Math.floor(round)));
}

export function duelDripTiles(round: number): number {
  return DUEL_DRIP_TILES[clampRound(round) - 1];
}

export function duelAttackMultiplier(round: number): number {
  return DUEL_ATTACK_MULTIPLIERS[clampRound(round) - 1];
}

/**
 * Which round the duel is in `seconds` into the game: rounds one and two are
 * DUEL_ROUND_SECONDS each, and the final round runs forever.
 */
export function duelRoundAt(seconds: number): number {
  return clampRound(Math.floor(seconds / DUEL_ROUND_SECONDS) + 1);
}

/**
 * How many tiles the drip numbered `dripIndex` (0-based) deals. Pure in the
 * index so both duellists — whose clocks may drift — draw identical batches
 * from the shared stream: drip k is drip k on both screens.
 */
export function duelDripTilesAt(dripIndex: number): number {
  const at = (dripIndex + 1) * DUEL_DRIP_SECONDS;
  return duelDripTiles(duelRoundAt(at));
}

/**
 * How many tiles placing a word sends to the opponent: nothing under four
 * letters, then one per letter past three — 4→1, 5→2, 6→3 — scaled up by the
 * round's multiplier and rounded to the nearest whole tile.
 */
export function duelAttackTiles(wordLength: number, round: number): number {
  const base = Math.max(0, Math.floor(wordLength) - 3);
  return Math.round(base * duelAttackMultiplier(round));
}

/* --------------------------------- shared --------------------------------- */

/** Whole seconds as "m:ss" for the header clock and splashes. */
export function formatSeconds(totalSeconds: number): string {
  const clamped = Math.max(0, Math.floor(totalSeconds));
  const minutes = Math.floor(clamped / 60);
  const seconds = clamped % 60;
  return `${minutes}:${String(seconds).padStart(2, '0')}`;
}
