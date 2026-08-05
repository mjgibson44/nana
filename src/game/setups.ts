/**
 * What each solo door was last set up as, remembered between visits.
 *
 * The setup sheet opens on the last game's settings, which are nearly always
 * the ones wanted again — so playing the same thing twice is one tap on Play.
 * Keeping them here carries that across a reload too: the sheet a player sees
 * on Monday is the one they left on Sunday.
 *
 * Only a deliberate choice is written — the Play button on a setup sheet.
 * A Survival game runs at the regular pace whatever the player prefers for
 * Blitz, and mustn't quietly rewrite that preference.
 *
 * Every read and write is wrapped: private browsing and blocked storage throw
 * on plain access. Anything missing, stale or hand-edited reads as the
 * defaults below, one field at a time — a bad grid size doesn't cost the
 * player their game style.
 */

import {
  PUZZLE_LOCK_OPTIONS,
  PUZZLE_SIZE_OPTIONS,
  PUZZLE_VARIANT_OPTIONS,
  PACE_OPTIONS,
  type PuzzleLock,
  type PuzzleSize,
  type PuzzleVariant,
  type SoloPace,
} from './modes';

/** Blitz's settings: its pace, and nothing else so far. */
export interface BlitzSetup {
  pace: SoloPace;
}

/** Puzzle's settings: the two rule dials and the board. */
export interface PuzzleSetup {
  variant: PuzzleVariant;
  lock: PuzzleLock;
  size: PuzzleSize;
}

/** What a player who has never set Blitz up gets. */
export const DEFAULT_BLITZ: BlitzSetup = { pace: 'regular' };

/**
 * What a player who has never set Puzzle up gets: Flow on the middle board,
 * with tiles that still move. It's the most forgiving corner of the mode —
 * the pile never runs dry, nothing a player places is held against them, and
 * the 13×13 board is big enough to build on without being a field to cross.
 */
export const DEFAULT_PUZZLE: PuzzleSetup = { variant: 'flow', lock: 'flexible', size: 13 };

const BLITZ_KEY = 'nana.setup.blitz.v1';
const PUZZLE_KEY = 'nana.setup.puzzle.v1';

/** Whatever is under `key`, as an object — or an empty one for anything that
 * isn't readable, isn't JSON, or isn't a plain object to begin with. */
function readSetup(key: string): Record<string, unknown> {
  try {
    const raw = window.localStorage.getItem(key);
    if (raw === null) return {};
    const parsed: unknown = JSON.parse(raw);
    return typeof parsed === 'object' && parsed !== null && !Array.isArray(parsed)
      ? (parsed as Record<string, unknown>)
      : {};
  } catch {
    return {};
  }
}

function writeSetup(key: string, setup: object): void {
  try {
    window.localStorage.setItem(key, JSON.stringify(setup));
  } catch {
    // Storage full or blocked — the sheet just opens on the defaults next time.
  }
}

/** `value` if it's one of `allowed`, and `fallback` otherwise. */
function oneOf<T>(value: unknown, allowed: readonly T[], fallback: T): T {
  return allowed.includes(value as T) ? (value as T) : fallback;
}

export function loadBlitzSetup(): BlitzSetup {
  const stored = readSetup(BLITZ_KEY);
  return {
    pace: oneOf(
      stored.pace,
      PACE_OPTIONS.map((option) => option.pace),
      DEFAULT_BLITZ.pace,
    ),
  };
}

export function saveBlitzSetup(setup: BlitzSetup): void {
  writeSetup(BLITZ_KEY, setup);
}

export function loadPuzzleSetup(): PuzzleSetup {
  const stored = readSetup(PUZZLE_KEY);
  return {
    variant: oneOf(
      stored.variant,
      PUZZLE_VARIANT_OPTIONS.map((option) => option.variant),
      DEFAULT_PUZZLE.variant,
    ),
    lock: oneOf(
      stored.lock,
      PUZZLE_LOCK_OPTIONS.map((option) => option.lock),
      DEFAULT_PUZZLE.lock,
    ),
    size: oneOf(
      stored.size,
      PUZZLE_SIZE_OPTIONS.map((option) => option.size),
      DEFAULT_PUZZLE.size,
    ),
  };
}

export function savePuzzleSetup(setup: PuzzleSetup): void {
  writeSetup(PUZZLE_KEY, setup);
}
