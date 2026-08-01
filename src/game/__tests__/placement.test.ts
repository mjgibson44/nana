import { describe, expect, it } from 'vitest';
import {
  GAP,
  cursorCell,
  findAvailable,
  impliedDirections,
  planPlacement,
  planWordCells,
  startableDirections,
} from '../placement';
import type { TileMap } from '../types';

const picksFrom = (word: string) =>
  word.split('').map((letter, rackIndex) => ({ letter, rackIndex }));

/** Picks from a pattern where '.' marks a gap tile, e.g. 'so.ar'. */
const picksWithGaps = (pattern: string) =>
  pattern
    .split('')
    .map((ch, i) =>
      ch === '.' ? { letter: null, rackIndex: GAP } : { letter: ch, rackIndex: i },
    );

describe('planPlacement with gap tiles', () => {
  it('lets a gap sit on a letter already on the board', () => {
    // SOLAR typed with a gap where the L goes, over an L already at 2,4.
    const board: TileMap = { '2,4': 'l' };
    const plan = planPlacement(board, 10, { row: 2, col: 2 }, 'across', picksWithGaps('so.ar'));
    expect(plan.complete).toBe(true);
    expect(plan.unfilledGaps).toEqual([]);
    // The gap places nothing — the L was already there.
    expect(plan.steps.map((s) => `${s.letter}@${s.key}`)).toEqual([
      's@2,2',
      'o@2,3',
      'a@2,5',
      'r@2,6',
    ]);
  });

  it('still lays out the whole word when a gap has nothing under it', () => {
    // Nothing at 2,4 for the gap to stand on, but the word must stay visible so
    // it can be lined up — it just can't be played yet.
    const plan = planPlacement({}, 10, { row: 2, col: 2 }, 'across', picksWithGaps('so.ar'));
    expect(plan.complete).toBe(false);
    expect(plan.unfilledGaps).toEqual(['2,4']);
    // Every letter is placed, and the gap holds its own square in the middle.
    expect(plan.steps.map((s) => `${s.letter}@${s.key}`)).toEqual([
      's@2,2',
      'o@2,3',
      'a@2,5',
      'r@2,6',
    ]);
  });

  it('reports every gap left uncovered', () => {
    const plan = planPlacement({}, 10, { row: 2, col: 2 }, 'across', picksWithGaps('s.a.r'));
    expect(plan.unfilledGaps).toEqual(['2,3', '2,5']);
    expect(plan.complete).toBe(false);
    expect(plan.steps.map((s) => s.key)).toEqual(['2,2', '2,4', '2,6']);
  });

  it('refuses a gap that misses the letter it was aimed at', () => {
    // The L is one cell further along than the gap reaches, so the gap comes
    // down on an empty square and the L gets flowed over instead.
    const plan = planPlacement(
      { '2,5': 'l' },
      10,
      { row: 2, col: 2 },
      'across',
      picksWithGaps('so.ar'),
    );
    expect(plan.complete).toBe(false);
    expect(plan.unfilledGaps).toEqual(['2,4']);
  });

  it('still flows letters over existing tiles without a gap', () => {
    // Typing the word minus its crossing letter works as it always has.
    const plan = planPlacement(
      { '2,4': 'l' },
      10,
      { row: 2, col: 2 },
      'across',
      picksFrom('soar'),
    );
    expect(plan.complete).toBe(true);
    expect(plan.steps.map((s) => s.key)).toEqual(['2,2', '2,3', '2,5', '2,6']);
  });
});

describe('impliedDirections', () => {
  it('reads a letter to the left as typing across', () => {
    expect(impliedDirections({ '4,3': 'a' }, { row: 4, col: 4 })).toEqual(['across']);
  });

  it('reads a letter above as typing down', () => {
    expect(impliedDirections({ '3,4': 'a' }, { row: 4, col: 4 })).toEqual(['down']);
  });

  it('has no opinion with nothing behind the cell', () => {
    // Letters to the right and below say nothing about where typing starts.
    expect(impliedDirections({ '4,5': 'a', '5,4': 'b' }, { row: 4, col: 4 })).toEqual([]);
  });

  it('offers both when hemmed in on both sides', () => {
    expect(impliedDirections({ '4,3': 'a', '3,4': 'b' }, { row: 4, col: 4 })).toEqual([
      'across',
      'down',
    ]);
  });
});

describe('cursorCell', () => {
  it('starts on the chosen cell when nothing is staged', () => {
    expect(cursorCell({}, 10, { row: 2, col: 2 }, 'across', [])).toBe('2,2');
  });

  it('walks ahead of the letters already staged', () => {
    expect(cursorCell({}, 10, { row: 2, col: 2 }, 'across', picksFrom('ca'))).toBe('2,4');
  });

  it('steps over a word already on the board', () => {
    // DOG sits at 2,3-2,5; one letter staged at 2,2 puts the focus past it.
    const board: TileMap = { '2,3': 'd', '2,4': 'o', '2,5': 'g' };
    expect(cursorCell(board, 10, { row: 2, col: 2 }, 'across', picksFrom('a'))).toBe('2,6');
  });

  it('starts past a letter when building on from it', () => {
    expect(cursorCell({ '2,2': 'a' }, 10, { row: 2, col: 2 }, 'across', [])).toBe('2,3');
  });

  it('comes back null once the word runs off the grid', () => {
    expect(cursorCell({}, 4, { row: 0, col: 0 }, 'across', picksFrom('abcd'))).toBeNull();
  });

  it('counts a gap as taking a square, covered or not', () => {
    // S, gap, R from 2,2 reaches 2,5 next whether or not 2,3 holds a letter.
    expect(cursorCell({}, 10, { row: 2, col: 2 }, 'across', picksWithGaps('s.r'))).toBe('2,5');
    expect(
      cursorCell({ '2,3': 'o' }, 10, { row: 2, col: 2 }, 'across', picksWithGaps('s.r')),
    ).toBe('2,5');
  });
});

describe('startableDirections', () => {
  it('offers both ways from an empty cell', () => {
    expect(startableDirections({}, 10, { row: 4, col: 4 })).toEqual(['across', 'down']);
  });

  it('still offers both in the far corner, where only one letter fits', () => {
    // Overflow is reported when the word is actually planned, not here.
    expect(startableDirections({}, 10, { row: 9, col: 9 })).toEqual(['across', 'down']);
  });

  it('offers only the ways a placed letter has room to grow', () => {
    // A letter with its right-hand neighbour taken can only carry on downwards.
    expect(startableDirections({ '4,4': 'a', '4,5': 'b' }, 10, { row: 4, col: 4 })).toEqual([
      'down',
    ]);
    expect(startableDirections({ '4,4': 'a', '5,4': 'b' }, 10, { row: 4, col: 4 })).toEqual([
      'across',
    ]);
  });

  it('offers nothing from a letter walled in both ways', () => {
    const board: TileMap = { '4,4': 'a', '4,5': 'b', '5,4': 'c' };
    expect(startableDirections(board, 10, { row: 4, col: 4 })).toEqual([]);
  });

  it('treats the edge of the grid as blocking for a placed letter', () => {
    const board: TileMap = { '9,9': 'a' };
    expect(startableDirections(board, 10, { row: 9, col: 9 })).toEqual([]);
  });
});

describe('planPlacement', () => {
  it('lays letters out across from the anchor', () => {
    const plan = planPlacement({}, 10, { row: 2, col: 3 }, 'across', picksFrom('cat'));
    expect(plan.complete).toBe(true);
    expect(plan.steps).toEqual([
      { key: '2,3', letter: 'c', rackIndex: 0 },
      { key: '2,4', letter: 'a', rackIndex: 1 },
      { key: '2,5', letter: 't', rackIndex: 2 },
    ]);
  });

  it('lays letters out down from the anchor', () => {
    const plan = planPlacement({}, 10, { row: 2, col: 3 }, 'down', picksFrom('cat'));
    expect(plan.steps.map((s) => s.key)).toEqual(['2,3', '3,3', '4,3']);
  });

  it('flows over tiles already on the board without spending a pick', () => {
    const board: TileMap = { '0,1': 'a' };
    const plan = planPlacement(board, 10, { row: 0, col: 0 }, 'across', picksFrom('ct'));
    expect(plan.complete).toBe(true);
    expect(plan.steps).toEqual([
      { key: '0,0', letter: 'c', rackIndex: 0 },
      { key: '0,2', letter: 't', rackIndex: 1 },
    ]);
  });

  it('reports incomplete when the word runs off the grid', () => {
    const plan = planPlacement({}, 5, { row: 0, col: 3 }, 'across', picksFrom('cat'));
    expect(plan.complete).toBe(false);
    expect(plan.steps.map((s) => s.key)).toEqual(['0,3', '0,4']);
  });

  it('returns an empty plan for no picks', () => {
    const plan = planPlacement({}, 10, { row: 0, col: 0 }, 'across', []);
    expect(plan.steps).toEqual([]);
    expect(plan.complete).toBe(true);
  });
});

describe('planWordCells', () => {
  // CAT sitting across at row 0, cols 0-2.
  const cat: TileMap = { '0,0': 'c', '0,1': 'a', '0,2': 't' };
  const own = new Set(['0,0', '0,1', '0,2']);

  it('moves a word to a clear stretch of board', () => {
    expect(planWordCells(cat, 10, 3, own, 'across', { row: 4, col: 5 })).toEqual([
      '4,5',
      '4,6',
      '4,7',
    ]);
  });

  it('rotates a word about its first letter', () => {
    expect(planWordCells(cat, 10, 3, own, 'down', { row: 0, col: 0 })).toEqual([
      '0,0',
      '1,0',
      '2,0',
    ]);
  });

  it('treats the cells the word is vacating as free', () => {
    // Shifting CAT one to the right overlaps its own A and T.
    expect(planWordCells(cat, 10, 3, own, 'across', { row: 0, col: 1 })).toEqual([
      '0,1',
      '0,2',
      '0,3',
    ]);
  });

  it('refuses to land on another word', () => {
    const board: TileMap = { ...cat, '2,0': 'x' };
    expect(planWordCells(board, 10, 3, own, 'down', { row: 0, col: 0 })).toBeNull();
  });

  it('refuses to run off the grid', () => {
    expect(planWordCells(cat, 10, 3, own, 'across', { row: 0, col: 8 })).toBeNull();
    expect(planWordCells(cat, 10, 3, own, 'down', { row: -1, col: 0 })).toBeNull();
  });
});

describe('findAvailable', () => {
  it('finds a matching pile tile', () => {
    expect(findAvailable(['a', 'b', 'c'], 'b', [])).toBe(1);
  });

  it('skips tiles already claimed by the current word', () => {
    expect(findAvailable(['a', 'b', 'a'], 'a', [0])).toBe(2);
  });

  it('is case-insensitive about the typed letter', () => {
    expect(findAvailable(['a', 'b'], 'B', [])).toBe(1);
  });

  it('returns -1 when the letter is not available', () => {
    expect(findAvailable(['a', 'b'], 'z', [])).toBe(-1);
    expect(findAvailable(['a'], 'a', [0])).toBe(-1);
  });
});
