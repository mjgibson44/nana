import { memo } from 'react';
import type { CellKey, TileMap } from '../game/types';
import { keyOf } from '../game/types';
import type { CellStatus } from '../App';

interface GridProps {
  size: number;
  board: TileMap;
  cellStatus: Map<CellKey, CellStatus>;
  hiddenKey: CellKey | null;
  onTilePointerDown: (key: CellKey, letter: string, e: React.PointerEvent) => void;
}

export const Grid = memo(function Grid({
  size,
  board,
  cellStatus,
  hiddenKey,
  onTilePointerDown,
}: GridProps) {
  const cells = [];
  for (let row = 0; row < size; row++) {
    for (let col = 0; col < size; col++) {
      const key = keyOf(row, col);
      const letter = board[key];
      const status = cellStatus.get(key);
      cells.push(
        <div key={key} className="cell" data-cell data-row={row} data-col={col}>
          {letter !== undefined && (
            <div
              className={`tile board-tile${status ? ` t-${status}` : ''}${
                key === hiddenKey ? ' tile-hidden' : ''
              }`}
              onPointerDown={(e) => onTilePointerDown(key, letter, e)}
            >
              {letter}
            </div>
          )}
        </div>,
      );
    }
  }

  return (
    <div
      className="board"
      style={{ gridTemplateColumns: `repeat(${size}, var(--cell))` }}
    >
      {cells}
    </div>
  );
});
