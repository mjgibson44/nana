/**
 * What the Solo door was last set up as, remembered between visits.
 *
 * The setup sheet opens on the last game's settings, which are nearly always
 * the ones wanted again — so playing the same thing twice is one tap on Play.
 * Keeping them here carries that across a reload too: the sheet a player sees
 * on Monday is the one they left on Sunday.
 *
 * Only a deliberate choice is written — the Play button on the setup sheet.
 *
 * Every read and write is wrapped: private browsing and blocked storage throw
 * on plain access. Anything missing, stale or hand-edited reads as the
 * defaults below.
 */

import { PACE_OPTIONS, type SoloPace } from './modes';

/** Solo's settings: its pace, and nothing else so far. */
export interface SoloSetup {
  pace: SoloPace;
}

/** What a player who has never set Solo up gets. */
export const DEFAULT_SOLO: SoloSetup = { pace: 'regular' };

const SOLO_KEY = 'nana.setup.solo.v1';

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

export function loadSoloSetup(): SoloSetup {
  const stored = readSetup(SOLO_KEY);
  return {
    pace: oneOf(
      stored.pace,
      PACE_OPTIONS.map((option) => option.pace),
      DEFAULT_SOLO.pace,
    ),
  };
}

export function saveSoloSetup(setup: SoloSetup): void {
  writeSetup(SOLO_KEY, setup);
}
