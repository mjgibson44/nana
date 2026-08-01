import { describe, expect, it } from 'vitest';
import { components, extractRuns, isConnected, validateBoard } from '../board';
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

  it('rejects two-letter runs even when the dictionary has them', () => {
    // AT is in the test dictionary, but two-letter words are banned outright.
    const v = validateBoard(boardFrom(['at']), dict);
    expect(dict.has('at')).toBe(true);
    expect(v.invalidRuns.map((r) => r.word)).toEqual(['at']);
    expect(v.ok).toBe(false);
  });

  it('names the tiles adrift from the main body of the board', () => {
    // CAT is the bigger group, so the far-off DOG is what's adrift.
    const v = validateBoard(boardFrom(['cat', '...', 'dog']), dict);
    expect(v.disconnectedTiles.sort()).toEqual([keyOf(2, 0), keyOf(2, 1), keyOf(2, 2)]);
  });

  it('leaves nothing adrift when the board is one group', () => {
    const v = validateBoard(boardFrom(['cat', '.t.', '.e.']), dict);
    expect(v.disconnectedTiles).toEqual([]);
  });
});

describe('components', () => {
  it('returns one group for a joined-up board', () => {
    expect(components(boardFrom(['cat', '.t.', '.e.']))).toHaveLength(1);
  });

  it('orders groups largest first, so the main board comes out on top', () => {
    // A four-tile word and a lone tile, far apart.
    const groups = components(boardFrom(['cats', '....', 'x...']));
    expect(groups.map((g) => g.length)).toEqual([4, 1]);
    expect(groups[1]).toEqual([keyOf(2, 0)]);
  });

  it('has no groups at all on an empty board', () => {
    expect(components({})).toEqual([]);
  });
});
