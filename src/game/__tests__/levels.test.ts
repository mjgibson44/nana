import { describe, expect, it } from 'vitest';
import { validateBoard } from '../board';
import type { TileMap } from '../types';
import { keyOf } from '../types';
import {
  ALL_TILES_BONUS,
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
