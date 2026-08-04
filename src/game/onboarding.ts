/**
 * What a player has already been shown, remembered between visits.
 *
 * Two things front a first game: the tutorial, once ever, and a short
 * explainer for each mode, once per mode. Both are one-way notes — nothing
 * here is ever unset, so neither can come back a second time.
 *
 * Every read and write is wrapped: private browsing and blocked storage throw
 * on plain access. A failed read reports "not seen yet", which shows the note
 * again rather than swallowing it; a failed write simply doesn't stick.
 */

import type { GameDoor } from './modes';

/** Set once the tutorial has been offered — it fronts the first game only. */
const TUTORIAL_KEY = 'nana.tutorial.v1';

/** Holds the doors whose explainer has been read, comma separated. */
const DOORS_KEY = 'nana.doors.v1';

export function tutorialSeen(): boolean {
  try {
    return window.localStorage.getItem(TUTORIAL_KEY) !== null;
  } catch {
    return false;
  }
}

export function markTutorialSeen(): void {
  try {
    window.localStorage.setItem(TUTORIAL_KEY, String(Date.now()));
  } catch {
    // Storage blocked or full — the tutorial will simply be offered again.
  }
}

function doorsSeen(): string[] {
  try {
    return (window.localStorage.getItem(DOORS_KEY) ?? '').split(',').filter(Boolean);
  } catch {
    return [];
  }
}

export function doorSeen(door: GameDoor): boolean {
  return doorsSeen().includes(door);
}

export function markDoorSeen(door: GameDoor): void {
  const seen = doorsSeen();
  if (seen.includes(door)) return;
  try {
    window.localStorage.setItem(DOORS_KEY, [...seen, door].join(','));
  } catch {
    // As above: the explainer will just introduce this mode once more.
  }
}
