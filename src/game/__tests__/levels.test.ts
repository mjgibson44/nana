import { describe, expect, it } from 'vitest';
import { validateBoard } from '../board';
import type { TileMap } from '../types';
import { keyOf } from '../types';
import {
  ALL_TILES_BONUS,
  BOARD_SIZE,
  GROW_MARGIN,
  boardBounds,
  scoreBoard,
  tilesAddedForLevel,
  tilesForLevel,
  wordScore,
} from '../levels';

describe('tilesForLevel', () => {
  it('counts the running total, 20 then 10 a level', () => {
    expect([1, 2, 3, 4, 5].map(tilesForLevel)).toEqual([20, 30, 40, 50, 60]);
  });

  it('deals 20 up front and 10 for each level after', () => {
    expect([1, 2, 3, 4, 5].map(tilesAddedForLevel)).toEqual([20, 10, 10, 10, 10]);
  });

  it('adds up to the running total', () => {
    let dealt = 0;
    for (let level = 1; level <= 5; level++) {
      dealt += tilesAddedForLevel(level);
      expect(dealt).toBe(tilesForLevel(level));
    }
  });
});

describe('boardBounds', () => {
  const START = {
    minRow: 0,
    minCol: 0,
    maxRow: BOARD_SIZE - 1,
    maxCol: BOARD_SIZE - 1,
  };

  it('is the starting board while it is empty', () => {
    expect(boardBounds({})).toEqual(START);
  });

  it('stays put while tiles keep their distance from every edge', () => {
    expect(boardBounds({ '16,16': 'a' })).toEqual(START);
  });

  it('grows past an edge a tile has come close to', () => {
    // A tile on the top edge pushes the board GROW_MARGIN rows above it.
    expect(boardBounds({ '0,16': 'a' })).toEqual({ ...START, minRow: -GROW_MARGIN });
  });

  it('keeps growing as tiles follow the edge outward', () => {
    // Play onto the new rows and the board recedes again.
    expect(boardBounds({ '-5,16': 'a' })).toEqual({ ...START, minRow: -5 - GROW_MARGIN });
  });

  it('grows in every direction at once', () => {
    const board = { '0,0': 'a', [`${BOARD_SIZE - 1},${BOARD_SIZE - 1}`]: 'b' };
    expect(boardBounds(board)).toEqual({
      minRow: -GROW_MARGIN,
      minCol: -GROW_MARGIN,
      maxRow: BOARD_SIZE - 1 + GROW_MARGIN,
      maxCol: BOARD_SIZE - 1 + GROW_MARGIN,
    });
  });

  it('always leaves at least the margin of open board beyond every tile', () => {
    const board = { '2,30': 'a', '31,4': 'b' };
    const bounds = boardBounds(board);
    expect(bounds.minRow).toBeLessThanOrEqual(2 - GROW_MARGIN);
    expect(bounds.maxCol).toBeGreaterThanOrEqual(30 + GROW_MARGIN);
    expect(bounds.maxRow).toBeGreaterThanOrEqual(31 + GROW_MARGIN);
    expect(bounds.minCol).toBeLessThanOrEqual(4 - GROW_MARGIN);
  });
});

describe('wordScore', () => {
  it('pays nothing for a lone tile', () => {
    expect(wordScore('a')).toBe(0);
  });

  it('rewards length faster than linearly', () => {
    expect(wordScore('cat')).toBe(3);
    expect(wordScore('cats')).toBe(6);
    expect(wordScore('elephant')).toBe(28);
  });

  it('makes one long word beat the same letters split in two', () => {
    expect(wordScore('planets')).toBeGreaterThan(wordScore('plan') + wordScore('ets'));
  });
});

describe('scoreBoard', () => {
  const DICT = new Set(['cat', 'car', 'arc', 'at', 'as', 'ta']);

  /** Lay a word across (row, col) onwards. */
  function across(tiles: TileMap, row: number, col: number, word: string): TileMap {
    word.split('').forEach((letter, i) => {
      tiles[keyOf(row, col + i)] = letter;
    });
    return tiles;
  }

  function score(tiles: TileMap, tilesLeft: number) {
    return scoreBoard(validateBoard(tiles, DICT), tilesLeft);
  }

  it('scores nothing for an empty board', () => {
    expect(score({}, 20)).toMatchObject({ words: 0, bonus: 0, total: 0, bonusEarned: false });
  });

  it('pays out only for real words', () => {
    const tiles = across({}, 0, 0, 'cat');
    expect(score(tiles, 5).words).toBe(3);
    // XYZ is not in the dictionary, so it adds nothing.
    expect(score(across(tiles, 5, 0, 'xyz'), 5).words).toBe(3);
  });

  it('counts a crossing tile towards both of its words', () => {
    // CAT across, CAR down, sharing the C.
    const tiles = across({}, 0, 0, 'cat');
    tiles[keyOf(1, 0)] = 'a';
    tiles[keyOf(2, 0)] = 'r';
    expect(score(tiles, 5).words).toBe(wordScore('cat') + wordScore('car'));
  });

  it('adds the bonus once the pile is empty and the board is valid', () => {
    const tiles = across({}, 0, 0, 'cat');
    const result = score(tiles, 0);
    expect(result.bonusEarned).toBe(true);
    expect(result.bonus).toBe(ALL_TILES_BONUS);
    expect(result.total).toBe(3 + ALL_TILES_BONUS);
  });

  it('withholds the bonus while tiles remain in the pile', () => {
    expect(score(across({}, 0, 0, 'cat'), 1).bonusEarned).toBe(false);
  });

  it('withholds the bonus when the emptied pile left an invalid board', () => {
    // Pile empty, but ZZZ isn't a word.
    const tiles = across(across({}, 0, 0, 'cat'), 5, 0, 'zzz');
    expect(score(tiles, 0)).toMatchObject({ bonusEarned: false, bonus: 0, words: 3 });
  });

  it('withholds the bonus when the words are valid but not all connected', () => {
    // Two legal words, far apart — the board isn't one group.
    const tiles = across(across({}, 0, 0, 'cat'), 8, 8, 'car');
    expect(score(tiles, 0).bonusEarned).toBe(false);
  });
});
