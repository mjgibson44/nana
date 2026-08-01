import type { CellKey, Direction, TileMap } from './types';
import { keyOf, parseKey } from './types';

/** Shortest word the game will accept. Two-letter runs never count. */
export const MIN_WORD_LENGTH = 3;

/** A maximal horizontal or vertical run of 2+ adjacent letters. */
export interface WordRun {
  word: string;
  direction: Direction;
  cells: CellKey[];
  valid: boolean;
}

export interface BoardValidation {
  runs: WordRun[];
  /** Runs that aren't a legal word: too short, or not in the dictionary. */
  invalidRuns: WordRun[];
  /** Tiles that are not part of any 2+ letter run. */
  isolatedTiles: CellKey[];
  /** Tiles cut off from the main body of the board — every one of these has to
   * be joined up before the board counts as finished. */
  disconnectedTiles: CellKey[];
  /** True when every placed tile is orthogonally connected into one group
   * (vacuously true for an empty board). */
  connected: boolean;
  tileCount: number;
  /** Board is a fully legal crossword: at least one tile, every run is a
   * legal word, no isolated tiles, and everything is connected. */
  ok: boolean;
}

/** Extract every maximal 2+ letter run, reading across and down. */
export function extractRuns(tiles: TileMap): Array<Omit<WordRun, 'valid'>> {
  const runs: Array<Omit<WordRun, 'valid'>> = [];

  for (const key of Object.keys(tiles)) {
    const { row, col } = parseKey(key);

    // Only start a run at a cell with no occupied neighbor before it.
    if (!(keyOf(row, col - 1) in tiles)) {
      const cells: CellKey[] = [];
      let c = col;
      while (keyOf(row, c) in tiles) {
        cells.push(keyOf(row, c));
        c++;
      }
      if (cells.length >= 2) {
        runs.push({
          word: cells.map((k) => tiles[k]).join(''),
          direction: 'across',
          cells,
        });
      }
    }

    if (!(keyOf(row - 1, col) in tiles)) {
      const cells: CellKey[] = [];
      let r = row;
      while (keyOf(r, col) in tiles) {
        cells.push(keyOf(r, col));
        r++;
      }
      if (cells.length >= 2) {
        runs.push({
          word: cells.map((k) => tiles[k]).join(''),
          direction: 'down',
          cells,
        });
      }
    }
  }

  return runs;
}

/**
 * Split the board into orthogonally-connected groups of tiles, largest first.
 * A finished board is a single group; anything else is islands to be joined up.
 */
export function components(tiles: TileMap): CellKey[][] {
  const seen = new Set<CellKey>();
  const groups: CellKey[][] = [];

  for (const start of Object.keys(tiles)) {
    if (seen.has(start)) continue;
    const group: CellKey[] = [];
    const queue: CellKey[] = [start];
    seen.add(start);
    while (queue.length > 0) {
      const key = queue.pop()!;
      group.push(key);
      const { row, col } = parseKey(key);
      for (const nk of [
        keyOf(row - 1, col),
        keyOf(row + 1, col),
        keyOf(row, col - 1),
        keyOf(row, col + 1),
      ]) {
        if (nk in tiles && !seen.has(nk)) {
          seen.add(nk);
          queue.push(nk);
        }
      }
    }
    groups.push(group);
  }

  return groups.sort((a, b) => b.length - a.length);
}

/** True when all tiles form a single orthogonally-connected component. */
export function isConnected(tiles: TileMap): boolean {
  return components(tiles).length <= 1;
}

export function validateBoard(tiles: TileMap, dictionary: Set<string>): BoardValidation {
  const bareRuns = extractRuns(tiles);
  const runs: WordRun[] = bareRuns.map((r) => ({
    ...r,
    // Two-letter runs are out regardless of the dictionary.
    valid: r.word.length >= MIN_WORD_LENGTH && dictionary.has(r.word),
  }));
  const invalidRuns = runs.filter((r) => !r.valid);

  const covered = new Set<CellKey>();
  for (const run of runs) {
    for (const cell of run.cells) covered.add(cell);
  }
  const isolatedTiles = Object.keys(tiles).filter((k) => !covered.has(k));

  // Everything outside the biggest group is adrift from the main board.
  const groups = components(tiles);
  const disconnectedTiles = groups.slice(1).flat();

  const tileCount = Object.keys(tiles).length;

  return {
    runs,
    invalidRuns,
    isolatedTiles,
    disconnectedTiles,
    connected: groups.length <= 1,
    tileCount,
    ok:
      tileCount > 0 &&
      invalidRuns.length === 0 &&
      isolatedTiles.length === 0 &&
      disconnectedTiles.length === 0,
  };
}
