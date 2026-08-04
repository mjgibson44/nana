/**
 * Game modes.
 *
 * One board and one set of rules for building words, played three ways:
 *
 *  - Endless: no levels. New tiles keep arriving on a clock; let too many
 *    pile up loose and the game ends. Played solo — at either of two paces,
 *    see SoloPace — or as Endless Battle, the same game raced by several
 *    players on one shared deal.
 *  - Duel: head-to-head for exactly two players. Placed words are permanent,
 *    and every word you place sends tiles to your opponent. First player to
 *    overflow their pile loses.
 *  - Tutorial: a guided walk through placing words, at your own pace.
 */

export type GameMode = 'endless' | 'duel' | 'tutorial';

/**
 * How hard Endless leans on a solo player. Both paces are the same game —
 * same board, same loose limit, same clear bonus — and differ only in how
 * long the opening phase runs, how long a round is, and how many tiles a
 * round deals:
 *
 *  - `relaxed`: two minutes to open, then five-tile rounds of 45 seconds
 *    tightening to 30, and batches that grow to seven.
 *  - `blitz`: one minute to open, then a 15-second round forever, starting at
 *    three tiles and growing by one every eight rounds up to ten.
 *
 * Survival always runs at the relaxed pace: every player works one shared
 * deal, so the pacing has to be the same for everybody.
 */
export type SoloPace = 'relaxed' | 'blitz';

export interface ModeInfo {
  name: string;
  tagline: string;
  /** Short bullet lines for the mode's card on the home screen. */
  details: string[];
}

export const SOLO_RELAXED_INFO: ModeInfo = {
  name: 'Solo Relaxed',
  tagline: 'Survive the ever-growing pile.',
  details: [
    '2:00 to place your first 20 tiles',
    '+5 tiles a round — 45s rounds shrink to 30s, then batches grow to +7',
    'Over 20 loose tiles when a round ends and you’re out',
  ],
};

export const SOLO_BLITZ_INFO: ModeInfo = {
  name: 'Solo Blitz',
  tagline: 'The same pile, arriving four times as fast.',
  details: [
    '1:00 to place your first 20 tiles',
    '+3 tiles every 15s — the batch grows every 8 rounds, up to +10',
    'Over 20 loose tiles when a round ends and you’re out',
  ],
};

/** Each solo pace's card, for looking one up by pace. */
export const SOLO_INFO: Record<SoloPace, ModeInfo> = {
  relaxed: SOLO_RELAXED_INFO,
  blitz: SOLO_BLITZ_INFO,
};

/**
 * Survival's home-screen card — Endless raced by several players. Each
 * player's game runs as Endless at the relaxed pace, and the multiplayer
 * wrapping (lobby, shared deal, standings) lives in src/game/battle.ts.
 */
export const BATTLE_INFO: ModeInfo = {
  name: 'Survival',
  tagline: 'Outlive your friends (2+ players)',
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

/** Tiles in the opening Endless deal, at either pace. */
export const ENDLESS_START_TILES = 20;

/** The opening phase: this long to work the starting pile before tiles start
 * arriving — and before the loose-tile count switches on. Blitz gives you
 * half as long for the same twenty tiles. */
export const ENDLESS_INITIAL_SECONDS = 120;
export const BLITZ_INITIAL_SECONDS = 60;

/**
 * The screw turns twice after the opening phase: five rounds of 45 seconds,
 * then the clock tightens to 30-second rounds — five of those at the small
 * batch, and after that every round deals the big batch forever.
 */
export const ENDLESS_SLOW_SECONDS = 45;
export const ENDLESS_FAST_SECONDS = 30;

/** How many drip rounds run at the slower opening pace. */
export const ENDLESS_SLOW_ROUNDS = 5;

/** The batch size rounds start at, and how many rounds it lasts — the five
 * slow rounds plus the first five fast ones. */
export const ENDLESS_SMALL_BATCH = 5;
export const ENDLESS_SMALL_BATCH_ROUNDS = 10;

/** The batch size every round deals once the small rounds are spent. */
export const ENDLESS_BIG_BATCH = 7;

/** Blitz never touches its clock: every round after the opening minute is
 * fifteen seconds, and the batch is what grows instead. */
export const BLITZ_DRIP_SECONDS = 15;

/** The batch blitz opens on, and the one it tops out at. */
export const BLITZ_SMALL_BATCH = 3;
export const BLITZ_MAX_BATCH = 10;

/** How many blitz rounds a batch size lasts before growing by one — eight
 * fifteen-second rounds, so two minutes at each size. */
export const BLITZ_BATCH_ROUNDS = 8;

/** How long the opening phase runs at `pace`. */
export function endlessInitialSeconds(pace: SoloPace): number {
  return pace === 'blitz' ? BLITZ_INITIAL_SECONDS : ENDLESS_INITIAL_SECONDS;
}

/**
 * How long the wait for the next batch is, given how many drip intervals have
 * already run out. Relaxed: 45 seconds for the first five, 30 forever after.
 * Blitz: fifteen seconds, always.
 */
export function endlessDripSeconds(intervalsElapsed: number, pace: SoloPace): number {
  if (pace === 'blitz') return BLITZ_DRIP_SECONDS;
  return intervalsElapsed < ENDLESS_SLOW_ROUNDS ? ENDLESS_SLOW_SECONDS : ENDLESS_FAST_SECONDS;
}

/**
 * How many tiles the batch landing after `intervalsElapsed` drip intervals
 * brings. Relaxed: five for each of the first ten rounds, then seven forever.
 * Blitz: three to begin with, one more every eight rounds, and no more than
 * ten however long you last.
 */
export function endlessDripTiles(intervalsElapsed: number, pace: SoloPace): number {
  if (pace === 'blitz') {
    const grown = Math.floor(Math.max(0, intervalsElapsed) / BLITZ_BATCH_ROUNDS);
    return Math.min(BLITZ_MAX_BATCH, BLITZ_SMALL_BATCH + grown);
  }
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

/** The pile counter starts pleading before the limit: flashing orange at a
 * medium blink from this many tiles… */
export const DUEL_PILE_WARN = 15;

/** …and flashing red, faster, from this many. */
export const DUEL_PILE_URGENT = 20;

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
 *
 * `grewFrom` lists the lengths of the words already on the board that this
 * word absorbed — the word it extends, or the two it bridges. Only the growth
 * is paid for: the new word's base value minus what the absorbed words were
 * worth, so stretching HEART to HEARTS earns the S, not the whole word again.
 * A word built from nothing (an empty list) earns its full value.
 */
export function duelAttackTiles(
  wordLength: number,
  round: number,
  grewFrom: number[] = [],
): number {
  const base = (length: number) => Math.max(0, Math.floor(length) - 3);
  const absorbed = grewFrom.reduce((sum, length) => sum + base(length), 0);
  const growth = Math.max(0, base(wordLength) - absorbed);
  return Math.round(growth * duelAttackMultiplier(round));
}

/* --------------------------------- shared --------------------------------- */

/** Whole seconds as "m:ss" for the header clock and splashes. */
export function formatSeconds(totalSeconds: number): string {
  const clamped = Math.max(0, Math.floor(totalSeconds));
  const minutes = Math.floor(clamped / 60);
  const seconds = clamped % 60;
  return `${minutes}:${String(seconds).padStart(2, '0')}`;
}
