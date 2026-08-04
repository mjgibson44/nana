/**
 * The tutorial's script.
 *
 * Every step deals exactly the tiles its word needs and waits for that word to
 * appear on the board before moving on, so each step's instructions can name
 * real letters the player is looking at. The deals get shorter as they go: step
 * two is one tile short because its word crosses a letter already down, and step
 * three is two short because its word has to be played through a gap tile.
 */

import { GAP, findAvailable, type Pick } from './placement';
import type { Bounds, Cell, Direction, TileMap } from './types';
import { inBounds, keyOf } from './types';

export interface TutorialStep {
  /** Tiles dealt into the pile as the step opens, in the order they're read. */
  tiles: string[];
  /** The word the step is asking for, lowercase like the board. */
  word: string;
  /**
   * Whether the word has to be played through a gap tile rather than simply
   * typed over the letter already sitting there. The step teaching the gap
   * refuses the word without one — otherwise the lesson can be walked past.
   */
  needsGap: boolean;
  /**
   * Called out over the board the moment the word lands. The banner can't say
   * this: by the time it's read it has already moved on to asking for the next
   * word, so nothing else marks the step as done.
   */
  done: string;
}

export const TUTORIAL_SCRIPT: readonly TutorialStep[] = [
  // Spelled out in a row in the pile: the first word is there to be read off.
  { tiles: ['s', 'o', 'l', 'a', 'r'], word: 'solar', needsGap: false, done: 'SOLAR is down!' },
  // No R — ORBIT crosses the one SOLAR just left on the board.
  {
    tiles: ['o', 'b', 'i', 't'],
    word: 'orbit',
    needsGap: false,
    done: 'ORBIT crossed on the R!',
  },
  // No O either, and this time the board's O has to be claimed with a gap.
  {
    tiles: ['p', 'l', 'e'],
    word: 'pole',
    needsGap: true,
    done: 'POLE played through the gap — that’s the whole game!',
  },
];

/** How many steps the player is walked through. */
export const TUTORIAL_STEPS = TUTORIAL_SCRIPT.length;

/**
 * Lay `step`'s word out from `anchor` and report the picks that would play it,
 * or null when it doesn't fit there.
 *
 * Follows exactly the rules `planPlacement` places by, so a fit found here
 * plays: each letter either comes out of the pile or is already on the board
 * with the right letter under it. A step that wants a gap tile claims those
 * board letters with gaps instead of flowing over them, which is the whole
 * difference between the two — and the reason the word it plays is the one the
 * step was teaching.
 *
 * The squares just before and just after the word have to be empty, or what
 * lands isn't the word at all but the middle of some longer run.
 */
function fitWord(
  board: TileMap,
  bounds: Bounds,
  anchor: Cell,
  dir: Direction,
  step: TutorialStep,
  rack: readonly string[],
): Pick[] | null {
  const before =
    dir === 'across' ? keyOf(anchor.row, anchor.col - 1) : keyOf(anchor.row - 1, anchor.col);
  if (board[before] !== undefined) return null;

  const picks: Pick[] = [];
  const taken: number[] = [];
  let { row, col } = anchor;

  for (const letter of step.word) {
    if (!inBounds(bounds, row, col)) return null;
    const sitting = board[keyOf(row, col)];
    if (sitting !== undefined) {
      if (sitting !== letter) return null;
      if (step.needsGap) picks.push({ letter: null, rackIndex: GAP });
    } else {
      const index = findAvailable(rack, letter, taken);
      if (index === -1) return null;
      taken.push(index);
      picks.push({ letter: rack[index], rackIndex: index });
    }
    if (dir === 'across') col++;
    else row++;
  }

  if (board[keyOf(row, col)] !== undefined) return null;
  // Nothing to play — the word is already on the board here.
  if (!picks.some((pick) => pick.letter !== null)) return null;
  return picks;
}

/**
 * Where the tutorial would play `step`'s word itself — what Skip uses, so the
 * board still matches what the next step's instructions describe.
 *
 * Sweeps the board for the first spot the word fits. Since a step's pile is
 * deliberately short of the letters its word crosses, the only spots that can
 * fit are the ones that cross them, which is what makes a blind sweep enough.
 * Returns null when there is no such spot — a board the player has rearranged
 * past recognising, say — leaving the caller to move the step along without
 * playing anything.
 */
export function scriptedPlacement(
  board: TileMap,
  bounds: Bounds,
  step: TutorialStep,
  rack: readonly string[],
): { anchor: Cell; dir: Direction; picks: Pick[] } | null {
  // The opening word has the whole board to itself, so it goes in the middle
  // rather than wherever a sweep of an empty board happens to start.
  if (Object.keys(board).length === 0) {
    const row = Math.floor((bounds.minRow + bounds.maxRow) / 2);
    const col =
      Math.floor((bounds.minCol + bounds.maxCol) / 2) - Math.floor(step.word.length / 2);
    const picks = fitWord(board, bounds, { row, col }, 'across', step, rack);
    if (picks) return { anchor: { row, col }, dir: 'across', picks };
  }

  for (let row = bounds.minRow; row <= bounds.maxRow; row++) {
    for (let col = bounds.minCol; col <= bounds.maxCol; col++) {
      for (const dir of ['across', 'down'] as const) {
        const picks = fitWord(board, bounds, { row, col }, dir, step, rack);
        if (picks) return { anchor: { row, col }, dir, picks };
      }
    }
  }
  return null;
}
