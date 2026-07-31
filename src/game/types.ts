/**
 * Core shared types for the game. Everything in src/game/ is pure TypeScript
 * with no DOM or React dependencies, so the same logic can run on a server
 * for multiplayer later.
 */

/** A cell key is "row,col". Using string keys keeps the board a plain,
 * serializable object — handy for sending over the wire later. */
export type CellKey = string;

/** Sparse board: only occupied cells are present. Values are lowercase letters. */
export type TileMap = Record<CellKey, string>;

export type Direction = 'across' | 'down';

export interface Cell {
  row: number;
  col: number;
}

export function keyOf(row: number, col: number): CellKey {
  return `${row},${col}`;
}

export function parseKey(key: CellKey): Cell {
  const comma = key.indexOf(',');
  return { row: Number(key.slice(0, comma)), col: Number(key.slice(comma + 1)) };
}
