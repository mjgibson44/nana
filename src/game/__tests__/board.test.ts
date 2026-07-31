import { describe, expect, it } from 'vitest';
import { extractRuns, isConnected, validateBoard } from '../board';
import type { TileMap } from '../types';
import { keyOf } from '../types';

/** Build a board from ascii rows; '.' means empty. */
function boardFrom(rows: string[]): TileMap {
  const tiles: TileMap = {};
  rows.forEach((row, r) => {
    [...row].forEach((ch, c) => {
      if (ch !== '.') tiles[keyOf(r, c)] = ch;
    });
  });
  return tiles;
}

describe('extractRuns', () => {
  it('finds across and down words', () => {
    // c a t
    // . t .
    // . e .
    const tiles = boardFrom(['cat', '.t.', '.e.']);
    const runs = extractRuns(tiles);
    const words = runs.map((r) => r.word).sort();
    expect(words).toEqual(['ate', 'cat']);
    expect(runs.find((r) => r.word === 'cat')?.direction).toBe('across');
    expect(runs.find((r) => r.word === 'ate')?.direction).toBe('down');
  });

  it('ignores single letters', () => {
    const tiles = boardFrom(['c.t']);
    expect(extractRuns(tiles)).toEqual([]);
  });

  it('splits runs across gaps', () => {
    const tiles = boardFrom(['at.at']);
    const runs = extractRuns(tiles);
    expect(runs.map((r) => r.word)).toEqual(['at', 'at']);
  });
});

describe('isConnected', () => {
  it('accepts one connected group', () => {
    expect(isConnected(boardFrom(['cat', '.t.', '.e.']))).toBe(true);
  });

  it('rejects two separate groups', () => {
    expect(isConnected(boardFrom(['cat', '...', 'dog']))).toBe(false);
  });

  it('is vacuously true for empty and single-tile boards', () => {
    expect(isConnected({})).toBe(true);
    expect(isConnected(boardFrom(['a']))).toBe(true);
  });
});

describe('validateBoard', () => {
  const dict = new Set(['cat', 'ate', 'dog', 'at']);

  it('accepts a fully valid crossword', () => {
    const v = validateBoard(boardFrom(['cat', '.t.', '.e.']), dict);
    expect(v.ok).toBe(true);
    expect(v.invalidRuns).toEqual([]);
    expect(v.isolatedTiles).toEqual([]);
    expect(v.connected).toBe(true);
  });

  it('flags words missing from the dictionary', () => {
    // "ax" (down) is not in the test dictionary.
    const v = validateBoard(boardFrom(['cat', '.x.']), dict);
    expect(v.ok).toBe(false);
    expect(v.invalidRuns.map((r) => r.word)).toEqual(['ax']);
  });

  it('flags isolated tiles', () => {
    const v = validateBoard(boardFrom(['cat', '...', 'x..']), dict);
    expect(v.isolatedTiles).toEqual([keyOf(2, 0)]);
    expect(v.connected).toBe(false);
    expect(v.ok).toBe(false);
  });

  it('flags disconnected groups even when all words are valid', () => {
    const v = validateBoard(boardFrom(['cat', '...', 'dog']), dict);
    expect(v.invalidRuns).toEqual([]);
    expect(v.connected).toBe(false);
    expect(v.ok).toBe(false);
  });

  it('is not ok for an empty board', () => {
    const v = validateBoard({}, dict);
    expect(v.ok).toBe(false);
    expect(v.tileCount).toBe(0);
  });
});
