/**
 * Game modes.
 *
 * One board and one set of rules for building words, played three ways:
 *
 *  - Endless: no levels. New tiles keep arriving on a clock; let too many
 *    pile up loose and the game ends. Played solo — the Solo door — at
 *    either of two paces, see SoloPace.
 *  - Battle: a room of two to eight players on one shared deal. Placed
 *    words are permanent, and every word you place scatters tiles across
 *    your rivals. Overflow your pile and you're out; the last player
 *    standing wins.
 *  - Tutorial: a guided walk through placing words, at your own pace.
 */

export type GameMode = 'endless' | 'battle' | 'tutorial';

/**
 * How hard Solo leans on the player. Both paces are the same game — same
 * board, same loose limit, same clear bonus — and differ only in how long
 * the opening phase runs, how long a round is, and how many tiles a round
 * deals:
 *
 *  - `regular`: two minutes to open, then five-tile rounds of 45 seconds
 *    tightening to 30, and batches that grow to seven.
 *  - `fast`: one minute to open, then a 15-second round forever, starting at
 *    three tiles and growing by one every eight rounds up to ten.
 */
export type SoloPace = 'regular' | 'fast';

export interface ModeInfo {
  name: string;
  tagline: string;
  /** Short bullet lines for the explainer that fronts the mode's first game. */
  details: string[];
}

/**
 * The doors out of the home screen — the two buttons that lead to a game.
 * Not the same list as GameMode: Solo raises a setup sheet for its pace on
 * the way in, while Battle leads to a lobby before any game starts.
 */
export type GameDoor = 'solo' | 'battle';

export const SOLO_INFO: ModeInfo = {
  name: 'Solo',
  tagline: 'Survive the ever-growing pile.',
  details: [
    'Tiles keep arriving on a clock — weave them in as they land',
    'Over 20 loose tiles when a round ends and you’re out',
    'Two speeds: Regular, or Fast for tiles arriving four times as quickly',
  ],
};

/** What the splash cards call each Solo pace. */
export const PACE_NAMES: Record<SoloPace, string> = {
  regular: 'Solo · Regular',
  fast: 'Solo · Fast',
};

/** The Speed setting's tabs, in the order they're offered. What each pace
 * actually costs you is SOLO_INFO's business, on the card that fronts the
 * mode; here it's a two-way switch. */
export const PACE_OPTIONS: ReadonlyArray<{ pace: SoloPace; name: string }> = [
  { pace: 'regular', name: 'Regular' },
  { pace: 'fast', name: 'Fast' },
];

/**
 * Battle's home-screen card. The rules in one breath: permanent words,
 * attack tiles split across the field, a hard pile limit, and the game runs
 * until one player is left. See splitAttackTiles for the split, and
 * src/game/battle.ts for the elimination bookkeeping.
 */
export const BATTLE_ROYALE_INFO: ModeInfo = {
  name: 'Battle',
  tagline: 'Free-for-all. Last one standing wins (2–8 players).',
  details: [
    'Two to eight players, same tiles',
    'Words are permanent — attack tiles are split across your rivals',
    'Overflow 25 tiles and you’re out; outlast everyone to win',
  ],
};

/**
 * The card that offers the tutorial, before it starts. It fronts a first
 * player's very first game as well as the tutorial they pick deliberately, so
 * it reads as an offer either way — and either way it can be skipped.
 */
export const TUTORIAL_INFO: ModeInfo = {
  name: 'Tutorial',
  tagline: 'New here? Learn the game in three quick steps.',
  details: [
    'Place your first word',
    'Cross it on a shared letter',
    'Borrow a letter with the gap tile',
  ],
};

/** Which explainer each door raises the first time it's opened. */
export const DOOR_INFO: Record<GameDoor, ModeInfo> = {
  solo: SOLO_INFO,
  battle: BATTLE_ROYALE_INFO,
};

/* -------------------------------- Endless --------------------------------- */

/** Tiles in the opening Endless deal, at either pace. */
export const ENDLESS_START_TILES = 20;

/** The opening phase: this long to work the starting pile before tiles start
 * arriving — and before the loose-tile count switches on. The fast pace gives
 * you half as long for the same twenty tiles. */
export const ENDLESS_INITIAL_SECONDS = 120;
export const FAST_INITIAL_SECONDS = 60;

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

/** The fast pace never touches its clock: every round after the opening
 * minute is fifteen seconds, and the batch is what grows instead. */
export const FAST_DRIP_SECONDS = 15;

/** The batch the fast pace opens on, and the one it tops out at. */
export const FAST_SMALL_BATCH = 3;
export const FAST_MAX_BATCH = 10;

/** How many fast rounds a batch size lasts before growing by one — eight
 * fifteen-second rounds, so two minutes at each size. */
export const FAST_BATCH_ROUNDS = 8;

/** How long the opening phase runs at `pace`. */
export function endlessInitialSeconds(pace: SoloPace): number {
  return pace === 'fast' ? FAST_INITIAL_SECONDS : ENDLESS_INITIAL_SECONDS;
}

/**
 * How long the wait for the next batch is, given how many drip intervals have
 * already run out. Regular: 45 seconds for the first five, 30 forever after.
 * Fast: fifteen seconds, always.
 */
export function endlessDripSeconds(intervalsElapsed: number, pace: SoloPace): number {
  if (pace === 'fast') return FAST_DRIP_SECONDS;
  return intervalsElapsed < ENDLESS_SLOW_ROUNDS ? ENDLESS_SLOW_SECONDS : ENDLESS_FAST_SECONDS;
}

/**
 * How many tiles the batch landing after `intervalsElapsed` drip intervals
 * brings. Regular: five for each of the first ten rounds, then seven forever.
 * Fast: three to begin with, one more every eight rounds, and no more than
 * ten however long you last.
 */
export function endlessDripTiles(intervalsElapsed: number, pace: SoloPace): number {
  if (pace === 'fast') {
    const grown = Math.floor(Math.max(0, intervalsElapsed) / FAST_BATCH_ROUNDS);
    return Math.min(FAST_MAX_BATCH, FAST_SMALL_BATCH + grown);
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

/* --------------------------------- Battle ---------------------------------- */

/**
 * How many players a Battle seats. Two is the head-to-head floor; eight is
 * where a phone's header, the lobby roster and the attack arithmetic all
 * still breathe.
 */
export const BATTLE_MIN_PLAYERS = 2;
export const BATTLE_MAX_PLAYERS = 8;

/** Tiles in each player's opening Battle deal. */
export const BATTLE_START_TILES = 15;

/** A Battle pile may never exceed this many tiles — one over and you're out. */
export const BATTLE_PILE_LIMIT = 25;

/** The pile counter starts pleading before the limit: flashing orange at a
 * medium blink from this many tiles… */
export const BATTLE_PILE_WARN = 15;

/** …and flashing red, faster, from this many. */
export const BATTLE_PILE_URGENT = 20;

/** How many rounds a battle has. The last one runs until it's decided. */
export const BATTLE_ROUNDS = 3;

/** Rounds one and two are this long; the final round has no clock. */
export const BATTLE_ROUND_SECONDS = 180;

/** How often the drip lands a tile (or several) in each player's pile. */
export const BATTLE_DRIP_SECONDS = 20;

/** How many tiles the drip brings per round: 1, then 2, then 4. */
const BATTLE_DRIP_TILES = [1, 2, 4];

/** How hard words hit per round: attacks are ×1, then ×1.5, then ×2. */
const BATTLE_ATTACK_MULTIPLIERS = [1, 1.5, 2];

function clampRound(round: number): number {
  return Math.max(1, Math.min(BATTLE_ROUNDS, Math.floor(round)));
}

export function battleDripTiles(round: number): number {
  return BATTLE_DRIP_TILES[clampRound(round) - 1];
}

export function battleAttackMultiplier(round: number): number {
  return BATTLE_ATTACK_MULTIPLIERS[clampRound(round) - 1];
}

/**
 * Which round a battle is in `seconds` into the game: rounds one and two are
 * BATTLE_ROUND_SECONDS each, and the final round runs forever.
 */
export function battleRoundAt(seconds: number): number {
  return clampRound(Math.floor(seconds / BATTLE_ROUND_SECONDS) + 1);
}

/**
 * How many tiles the drip numbered `dripIndex` (0-based) deals. Pure in the
 * index so every player — whose clocks may drift — draws identical batches
 * from the shared stream: drip k is drip k on every screen.
 */
export function battleDripTilesAt(dripIndex: number): number {
  const at = (dripIndex + 1) * BATTLE_DRIP_SECONDS;
  return battleDripTiles(battleRoundAt(at));
}

/**
 * How many tiles placing a word sends across the field: nothing under four
 * letters, then one per letter past three — 4→1, 5→2, 6→3 — scaled up by the
 * round's multiplier and rounded to the nearest whole tile.
 *
 * `grewFrom` lists the lengths of the words already on the board that this
 * word absorbed — the word it extends, or the two it bridges. Only the growth
 * is paid for: the new word's base value minus what the absorbed words were
 * worth, so stretching HEART to HEARTS earns the S, not the whole word again.
 * A word built from nothing (an empty list) earns its full value.
 */
export function battleAttackTiles(
  wordLength: number,
  round: number,
  grewFrom: number[] = [],
): number {
  const base = (length: number) => Math.max(0, Math.floor(length) - 3);
  const absorbed = grewFrom.reduce((sum, length) => sum + base(length), 0);
  const growth = Math.max(0, base(wordLength) - absorbed);
  return Math.round(growth * battleAttackMultiplier(round));
}

/**
 * Split one attack across the rivals still standing. A word earns its
 * battleAttackTiles total once — but with up to seven targets, sending the
 * whole attack to each of them would multiply the pressure by the size of
 * the room. So the total is divided across the field: everyone takes the
 * fair floor, and the remainder lands one tile each on the targets starting
 * at `from` (wrapping round), so the caller can rotate who takes the odd
 * tile rather than always the same seat.
 *
 * The shares always sum to the attack, so a 1-tile attack still lands
 * somewhere instead of rounding away to nothing — and as players fall, the
 * same words hit the survivors harder, which is the endgame tightening by
 * itself. With one rival left the whole attack lands on them, head-to-head.
 */
export function splitAttackTiles(count: number, targets: number, from = 0): number[] {
  if (!Number.isFinite(count) || targets <= 0) return [];
  const total = Math.max(0, Math.floor(count));
  const base = Math.floor(total / targets);
  const extra = total % targets;
  const start = ((Math.floor(from) % targets) + targets) % targets;
  const shares = new Array<number>(targets).fill(base);
  for (let i = 0; i < extra; i++) shares[(start + i) % targets] += 1;
  return shares;
}

/* --------------------------------- shared --------------------------------- */

/** Whole seconds as "m:ss" for the header clock and splashes. */
export function formatSeconds(totalSeconds: number): string {
  const clamped = Math.max(0, Math.floor(totalSeconds));
  const minutes = Math.floor(clamped / 60);
  const seconds = clamped % 60;
  return `${minutes}:${String(seconds).padStart(2, '0')}`;
}
