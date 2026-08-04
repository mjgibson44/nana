import { describe, expect, it } from 'vitest';
import { boardBounds } from '../levels';
import { extractRuns } from '../board';
import { GAP, planPlacement } from '../placement';
import { TUTORIAL_SCRIPT, TUTORIAL_STEPS, scriptedPlacement } from '../tutorial';
import type { TileMap } from '../types';
import { keyOf } from '../types';

/** Play a step's scripted placement, the way commit does, and hand back the
 * board it leaves — the whole point being that the word lands. */
function playStep(board: TileMap, stepIndex: number, rack: string[]): TileMap {
  const step = TUTORIAL_SCRIPT[stepIndex];
  const bounds = boardBounds(board);
  const played = scriptedPlacement(board, bounds, step, rack);
  expect(played).not.toBeNull();
  const plan = planPlacement(board, bounds, played!.anchor, played!.dir, played!.picks);
  expect(plan.complete).toBe(true);
  expect(plan.steps.length).toBeGreaterThan(0);
  const next = { ...board };
  for (const placed of plan.steps) next[placed.key] = placed.letter;
  return next;
}

describe('TUTORIAL_SCRIPT', () => {
  it('deals each word one letter short of the last, so every word crosses', () => {
    expect(TUTORIAL_SCRIPT.map((step) => step.word)).toEqual(['solar', 'orbit', 'pole']);
    expect(TUTORIAL_SCRIPT[0].tiles.join('')).toBe('solar');
    expect(TUTORIAL_SCRIPT[1].tiles.join('')).toBe('obit');
    expect(TUTORIAL_SCRIPT[2].tiles.join('')).toBe('ple');
  });

  it('opens with the word spelled out in reading order', () => {
    expect(TUTORIAL_SCRIPT[0].tiles.join('')).toBe(TUTORIAL_SCRIPT[0].word);
  });

  it('asks for a gap tile only on the last step', () => {
    expect(TUTORIAL_SCRIPT.map((step) => step.needsGap)).toEqual([false, false, true]);
  });

  it('has something to say the moment each word lands', () => {
    for (const step of TUTORIAL_SCRIPT) {
      expect(step.done).toContain(step.word.toUpperCase());
    }
  });

  it('counts its own steps', () => {
    expect(TUTORIAL_STEPS).toBe(3);
  });
});

describe('scriptedPlacement', () => {
  it('lays the opening word out across the middle of an empty board', () => {
    const board = playStep({}, 0, [...TUTORIAL_SCRIPT[0].tiles]);
    const runs = extractRuns(board);
    expect(runs.map((run) => run.word)).toEqual(['solar']);
    expect(runs[0].direction).toBe('across');
    // Comfortably inside the starting board, not against its corner.
    const cells = runs[0].cells.map((key) => key.split(',').map(Number));
    for (const [row, col] of cells) {
      expect(row).toBeGreaterThan(4);
      expect(col).toBeGreaterThan(4);
    }
  });

  it('walks the whole script through, each word crossing the one before', () => {
    let board = playStep({}, 0, [...TUTORIAL_SCRIPT[0].tiles]);
    board = playStep(board, 1, [...TUTORIAL_SCRIPT[1].tiles]);
    board = playStep(board, 2, [...TUTORIAL_SCRIPT[2].tiles]);

    const words = extractRuns(board)
      .map((run) => run.word)
      .sort();
    expect(words).toEqual(['orbit', 'pole', 'solar']);
    // Twelve tiles for three words totalling fourteen letters: the two
    // crossings are real, not three words laid out side by side.
    expect(Object.keys(board)).toHaveLength(12);
  });

  it('claims the letter it borrows with a gap when the step wants one', () => {
    let board = playStep({}, 0, [...TUTORIAL_SCRIPT[0].tiles]);
    board = playStep(board, 1, [...TUTORIAL_SCRIPT[1].tiles]);
    const played = scriptedPlacement(board, boardBounds(board), TUTORIAL_SCRIPT[2], ['p', 'l', 'e']);
    expect(played!.picks.map((pick) => pick.rackIndex)).toContain(GAP);
    expect(played!.picks.filter((pick) => pick.letter === null)).toHaveLength(1);
  });

  it('finishes a word the player started rather than starting a second one', () => {
    // Three of SOLAR's tiles already down, two left in the pile.
    const board: TileMap = { '10,10': 's', '10,11': 'o', '10,12': 'l' };
    const played = scriptedPlacement(board, boardBounds(board), TUTORIAL_SCRIPT[0], ['a', 'r']);
    expect(played).not.toBeNull();
    expect(played!.anchor).toEqual({ row: 10, col: 10 });
    expect(played!.dir).toBe('across');
    expect(played!.picks.map((pick) => pick.letter)).toEqual(['a', 'r']);
  });

  it('gives up rather than guess when the word has nowhere left to go', () => {
    // ORBIT's R is walled in on all four sides, so nothing can cross it.
    const board: TileMap = {
      '10,10': 'r',
      '9,10': 'x',
      '11,10': 'x',
      '10,9': 'x',
      '10,11': 'x',
    };
    const played = scriptedPlacement(board, boardBounds(board), TUTORIAL_SCRIPT[1], [
      ...TUTORIAL_SCRIPT[1].tiles,
    ]);
    expect(played).toBeNull();
  });

  it('will not bury the word inside a longer run', () => {
    // SOLAR would read as SOLARS, so this R is no use for ORBIT.
    const board: TileMap = { '10,10': 'r', '10,11': 's' };
    const bounds = boardBounds(board);
    const played = scriptedPlacement(board, bounds, TUTORIAL_SCRIPT[1], [
      ...TUTORIAL_SCRIPT[1].tiles,
    ]);
    // Down through the R is still fine — it's the across reading that's spoiled.
    expect(played).not.toBeNull();
    expect(played!.dir).toBe('down');
    expect(played!.anchor).toEqual({ row: 9, col: 10 });
    expect(keyOf(played!.anchor.row, played!.anchor.col)).toBe('9,10');
  });
});
