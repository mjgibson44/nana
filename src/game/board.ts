import type { CellKey, Direction, TileMap } from './types';
import { keyOf, parseKey } from './types';

/** A maximal horizontal or vertical run of 2+ adjacent letters. */
export interface WordRun {
  word: string;
  direction: Direction;
  cells: CellKey[];
  valid: boolean;
}

export interface BoardValidation {
  runs: WordRun[];
  /** Runs whose word is not in the dictionary. */
  invalidRuns: WordRun[];
  /** Tiles that are not part of any 2+ letter run. */
  isolatedTiles: CellKey[];
  /** True when every placed tile is orthogonally connected into one group
   * (vacuously true for an empty board). */
  connected: boolean;
  tileCount: number;
  /** Board is a fully legal crossword: at least one tile, every run is a
   * dictionary word, no isolated tiles, and everything is connected. */
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

/** True when all tiles form a single orthogonally-connected component. */
export function isConnected(tiles: TileMap): boolean {
  const keys = Object.keys(tiles);
  if (keys.length <= 1) return true;

  const seen = new Set<CellKey>([keys[0]]);
  const queue: CellKey[] = [keys[0]];
  while (queue.length > 0) {
    const { row, col } = parseKey(queue.pop()!);
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
  return seen.size === keys.length;
}

export function validateBoard(tiles: TileMap, dictionary: Set<string>): BoardValidation {
  const bareRuns = extractRuns(tiles);
  const runs: WordRun[] = bareRuns.map((r) => ({ ...r, valid: dictionary.has(r.word) }));
  const invalidRuns = runs.filter((r) => !r.valid);

  const covered = new Set<CellKey>();
  for (const run of runs) {
    for (const cell of run.cells) covered.add(cell);
  }
  const isolatedTiles = Object.keys(tiles).filter((k) => !covered.has(k));

  const connected = isConnected(tiles);
  const tileCount = Object.keys(tiles).length;

  return {
    runs,
    invalidRuns,
    isolatedTiles,
    connected,
    tileCount,
    ok: tileCount > 0 && invalidRuns.length === 0 && isolatedTiles.length === 0 && connected,
  };
}
