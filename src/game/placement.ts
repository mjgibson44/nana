import type { Cell, CellKey, Direction, TileMap } from './types';
import { keyOf } from './types';

/** A letter taken from the pile, remembered by its index there. */
export interface Pick {
  letter: string;
  rackIndex: number;
}

export interface PlacementStep {
  key: CellKey;
  letter: string;
  rackIndex: number;
}

export interface PlacementPlan {
  steps: PlacementStep[];
  /** True when every pick found an empty cell before running off the grid. */
  complete: boolean;
}

/**
 * Lay `picks` out from `anchor` heading in `dir`.
 *
 * Tiles already on the board are flowed over rather than displaced: an occupied
 * cell contributes its own letter to the run and does not consume a pick. That
 * makes typing a word straight through an existing crossing work the way it does
 * on a real board. Stops at the edge of the grid, so a plan can come back
 * `complete: false` with only some picks placed.
 */
export function planPlacement(
  board: TileMap,
  size: number,
  anchor: Cell,
  dir: Direction,
  picks: Pick[],
): PlacementPlan {
  const steps: PlacementStep[] = [];
  let { row, col } = anchor;
  let i = 0;

  while (i < picks.length && row >= 0 && col >= 0 && row < size && col < size) {
    const key = keyOf(row, col);
    if (board[key] === undefined) {
      steps.push({ key, letter: picks[i].letter, rackIndex: picks[i].rackIndex });
      i++;
    }
    if (dir === 'across') col++;
    else row++;
  }

  return { steps, complete: i === picks.length };
}

/**
 * Work out where a whole word's tiles would sit if its first letter moved to
 * `start` and it read in `dir`.
 *
 * `own` is the set of cells the word currently occupies; those are treated as
 * free, since the word vacates them as it moves. Returns null when the run
 * would leave the grid or land on a tile belonging to some other word — the
 * caller uses that to refuse the move (or grey out the control).
 */
export function planWordCells(
  board: TileMap,
  size: number,
  length: number,
  own: ReadonlySet<CellKey>,
  dir: Direction,
  start: Cell,
): CellKey[] | null {
  const cells: CellKey[] = [];
  for (let i = 0; i < length; i++) {
    const row = dir === 'down' ? start.row + i : start.row;
    const col = dir === 'across' ? start.col + i : start.col;
    if (row < 0 || col < 0 || row >= size || col >= size) return null;
    const key = keyOf(row, col);
    if (board[key] !== undefined && !own.has(key)) return null;
    cells.push(key);
  }
  return cells;
}

/**
 * Find the pile tile to consume for a typed letter: the first one that matches
 * and is not already spoken for by the word being built.
 */
export function findAvailable(
  rack: string[],
  letter: string,
  taken: readonly number[],
): number {
  const wanted = letter.toLowerCase();
  for (let i = 0; i < rack.length; i++) {
    if (rack[i].toLowerCase() === wanted && !taken.includes(i)) return i;
  }
  return -1;
}
