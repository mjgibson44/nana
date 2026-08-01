import type { Cell, CellKey, Direction, TileMap } from './types';
import { keyOf } from './types';

/** Rack index standing for a gap tile, which comes from no pile letter. */
export const GAP = -1;

/**
 * A letter taken from the pile, remembered by its index there — or a gap tile,
 * a deliberate hole in the word that has to land on a letter already on the
 * board. Typing SOLAR with a gap where the L goes plays it over an existing L.
 */
export interface Pick {
  letter: string | null;
  rackIndex: number;
}

/** One letter actually landing on the board. Gaps produce no step. */
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
 * cell contributes its own letter to the run and does not consume a letter pick.
 * That makes typing a word straight through an existing crossing work the way it
 * does on a real board.
 *
 * A gap pick is the explicit version of the same thing — it claims one tile
 * that's already there. If the cell it reaches is empty there is nothing for it
 * to stand on, so the plan stops short and comes back `complete: false`, as it
 * also does when the word runs off the edge of the grid.
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
    const occupied = board[key] !== undefined;
    const pick = picks[i];

    if (pick.letter === null) {
      // A gap has to sit on a letter that's already down.
      if (!occupied) return { steps, complete: false };
      i++;
    } else if (!occupied) {
      steps.push({ key, letter: pick.letter, rackIndex: pick.rackIndex });
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
 * Which directions a word can actually start in from `cell`.
 *
 * An empty cell offers both: the first letter lands right there, and anything
 * further along is flowed over. (Even hard against the far edge it offers both —
 * a one-letter word still fits, and anything longer reports as overflowing.)
 *
 * A cell that already holds a letter offers a direction only when the very next
 * cell is free. That existing letter becomes the word's first letter, so if its
 * neighbour is occupied too the first letter typed would leapfrog past it and
 * land somewhere unexpected. Such a cell offers nothing, and can only be read
 * or emptied rather than built on.
 */
export function startableDirections(board: TileMap, size: number, cell: Cell): Direction[] {
  const { row, col } = cell;
  if (board[keyOf(row, col)] === undefined) return ['across', 'down'];

  const dirs: Direction[] = [];
  if (col + 1 < size && board[keyOf(row, col + 1)] === undefined) dirs.push('across');
  if (row + 1 < size && board[keyOf(row + 1, col)] === undefined) dirs.push('down');
  return dirs;
}

/**
 * Directions the tiles around this cell suggest the player means to type.
 *
 * A letter immediately to the left reads as a word already running across into
 * this cell, so they're carrying on rightwards; a letter directly above says the
 * same for downwards. Nothing either side means no opinion.
 */
export function impliedDirections(board: TileMap, cell: Cell): Direction[] {
  const { row, col } = cell;
  const dirs: Direction[] = [];
  if (board[keyOf(row, col - 1)] !== undefined) dirs.push('across');
  if (board[keyOf(row - 1, col)] !== undefined) dirs.push('down');
  return dirs;
}

/**
 * The cell the next letter typed would land on — where the focus square sits.
 *
 * Walks the same path `planPlacement` does, so it flows over tiles already on
 * the board: type through an existing word and the focus jumps out the far side
 * of it rather than sitting on letters that are already there.
 */
export function cursorCell(
  board: TileMap,
  size: number,
  anchor: Cell,
  dir: Direction,
  picks: Pick[],
): CellKey | null {
  let { row, col } = anchor;
  let i = 0;

  while (row >= 0 && col >= 0 && row < size && col < size) {
    const key = keyOf(row, col);
    const occupied = board[key] !== undefined;

    if (i >= picks.length) {
      // Everything staged is placed; the next letter goes in the next free cell.
      if (!occupied) return key;
    } else if (picks[i].letter === null) {
      // A gap with no letter under it: that's the problem to look at.
      if (!occupied) return key;
      i++;
    } else if (!occupied) {
      i++;
    }

    if (dir === 'across') col++;
    else row++;
  }
  return null;
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
