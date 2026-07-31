import { memo } from 'react';
import type { CellKey, Direction, TileMap } from '../game/types';
import { keyOf } from '../game/types';
import type { BoardWord, CellStatus } from '../App';
import { WordControls } from './WordControls';

interface GridProps {
  size: number;
  board: TileMap;
  cellStatus: Map<CellKey, CellStatus>;
  /** Tiles being dragged, hidden in place while the ghost follows the pointer. */
  hiddenKeys: Set<CellKey>;
  /** Letters that would land if the current word were committed. */
  preview: Map<CellKey, string>;
  /** The cell a word is being built from, if any. */
  anchorKey: CellKey | null;
  /** Reveal direction arrows on whichever cell the pointer is over. */
  hoverArrows: boolean;
  /** Keep direction arrows pinned to the anchor cell (it was clicked). */
  anchorArrows: boolean;
  /** Words on the board, keyed by every cell they occupy. */
  wordsByCell: Map<CellKey, BoardWord[]>;
  /** The cell whose word controls are open. */
  openWordCell: CellKey | null;
  /** Cells of the word currently called out by the controls. */
  highlighted: Set<CellKey>;
  canRotate: (word: BoardWord) => boolean;
  onTilePointerDown: (key: CellKey, letter: string, e: React.PointerEvent) => void;
  onCellClick: (key: CellKey) => void;
  onArrow: (key: CellKey, dir: Direction) => void;
  onArrowHover: (key: CellKey, dir: Direction, entering: boolean) => void;
  onWordHover: (key: CellKey, entering: boolean) => void;
  onWordHighlight: (word: BoardWord | null) => void;
  onWordGrab: (word: BoardWord, e: React.PointerEvent) => void;
  onWordRotate: (word: BoardWord) => void;
  onWordRemove: (word: BoardWord) => void;
}

const ARROWS: Array<{ dir: Direction; glyph: string; label: string }> = [
  { dir: 'across', glyph: '➜', label: 'Place across' },
  { dir: 'down', glyph: '➜', label: 'Place down' },
];

export const Grid = memo(function Grid({
  size,
  board,
  cellStatus,
  hiddenKeys,
  preview,
  anchorKey,
  hoverArrows,
  anchorArrows,
  wordsByCell,
  openWordCell,
  highlighted,
  canRotate,
  onTilePointerDown,
  onCellClick,
  onArrow,
  onArrowHover,
  onWordHover,
  onWordHighlight,
  onWordGrab,
  onWordRotate,
  onWordRemove,
}: GridProps) {
  const cells = [];
  for (let row = 0; row < size; row++) {
    for (let col = 0; col < size; col++) {
      const key = keyOf(row, col);
      const letter = board[key];
      const status = cellStatus.get(key);
      const ghost = preview.get(key);
      const isAnchor = key === anchorKey;
      const empty = letter === undefined;
      const inWords = wordsByCell.get(key);

      // Which directions this cell can start a word in.
      //
      // An empty cell offers both: the first letter lands right here, and
      // anything already further along is simply flowed over.
      //
      // A cell that already holds a letter offers a direction only when the
      // very next cell is free. That existing letter becomes the word's first
      // letter — but if its neighbour is occupied too, the first letter you
      // typed would leapfrog past it and land somewhere unexpected.
      const dirs: Direction[] = [];
      if (hoverArrows || (anchorArrows && isAnchor)) {
        if (empty) {
          dirs.push('across', 'down');
        } else {
          if (col + 1 < size && board[keyOf(row, col + 1)] === undefined) dirs.push('across');
          if (row + 1 < size && board[keyOf(row + 1, col)] === undefined) dirs.push('down');
        }
      }

      cells.push(
        <div
          key={key}
          className={`cell${isAnchor ? ' is-anchor' : ''}${
            dirs.length > 0 ? ' has-arrows' : ''
          }`}
          data-cell
          data-row={row}
          data-col={col}
          onClick={() => onCellClick(key)}
        >
          {letter !== undefined && (
            <div
              className={`tile board-tile${status ? ` t-${status}` : ''}${
                hiddenKeys.has(key) ? ' tile-hidden' : ''
              }${inWords ? ' is-word-tile' : ''}${
                highlighted.has(key) ? ' is-in-word' : ''
              }`}
              onPointerDown={(e) => onTilePointerDown(key, letter, e)}
              onPointerEnter={inWords ? () => onWordHover(key, true) : undefined}
              onPointerLeave={inWords ? () => onWordHover(key, false) : undefined}
            >
              {letter}
            </div>
          )}

          {letter === undefined && ghost !== undefined && (
            <div className="tile board-tile tile-preview">{ghost}</div>
          )}

          {inWords && key === openWordCell && (
            <WordControls
              words={inWords}
              canRotate={canRotate}
              onGrab={onWordGrab}
              onRotate={onWordRotate}
              onRemove={onWordRemove}
              onHighlight={onWordHighlight}
              onPointerEnter={() => onWordHover(key, true)}
              onPointerLeave={() => onWordHover(key, false)}
            />
          )}

          {ARROWS.filter(({ dir }) => dirs.includes(dir)).map(({ dir, glyph, label }) => (
            <button
              key={dir}
              type="button"
              className={`cell-arrow cell-arrow-${dir}`}
              title={label}
              aria-label={label}
              onPointerDown={(e) => e.stopPropagation()}
              onPointerEnter={() => onArrowHover(key, dir, true)}
              onPointerLeave={() => onArrowHover(key, dir, false)}
              onClick={(e) => {
                e.stopPropagation();
                onArrow(key, dir);
              }}
            >
              {glyph}
            </button>
          ))}
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
