import { describe, expect, it } from 'vitest';
import { findAvailable, planPlacement, planWordCells } from '../placement';
import type { TileMap } from '../types';

const picksFrom = (word: string) =>
  word.split('').map((letter, rackIndex) => ({ letter, rackIndex }));

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
