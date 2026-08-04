import { memo } from 'react';
import type { Bounds, CellKey, Direction, TileMap } from '../game/types';
import { keyOf } from '../game/types';
import type { BoardWord, CellStatus } from '../App';
import { WordControls } from './WordControls';

interface GridProps {
  /** The rectangle of cells in play. Grows as tiles near its edges. */
  bounds: Bounds;
  board: TileMap;
  cellStatus: Map<CellKey, CellStatus>;
  /** Tiles being dragged, hidden in place while the ghost follows the pointer. */
  hiddenKeys: Set<CellKey>;
  /** Letters that would land if the current word were committed. */
  preview: Map<CellKey, string>;
  /** Squares a gap tile is holding open, still waiting for a letter under it. */
  previewGaps: Set<CellKey>;
  /** The square the next letter will land on, if a word is being built. */
  cursorKey: CellKey | null;
  /** The direction that word is being laid in. */
  cursorDir: Direction | null;
  /** The chosen cell the word reads from — its first letter, where the
   * rotate button sits. */
  rotateKey: CellKey | null;
  /** Offer the rotate button — only when the cell could go either way. */
  showRotate: boolean;
  /** Words on the board, keyed by every cell they occupy. */
  wordsByCell: Map<CellKey, BoardWord[]>;
  /** The cell whose word controls are open. */
  openWordCell: CellKey | null;
  /** Cells of the word currently called out by the controls. */
  highlighted: Set<CellKey>;
  /** The placed tile picked out for deletion, if any. */
  selectedKey: CellKey | null;
  /** Duel: placed tiles are permanent — no grab affordance, no controls. */
  boardLocked: boolean;
  canRotate: (word: BoardWord) => boolean;
  onTilePointerDown: (key: CellKey, letter: string, e: React.PointerEvent) => void;
  onCellClick: (key: CellKey) => void;
  /** The cell under the pointer, or null once it leaves the board. */
  onCellHover: (key: CellKey | null) => void;
  onRotateDirection: () => void;
  onWordHighlight: (word: BoardWord | null) => void;
  onWordGrab: (word: BoardWord, e: React.PointerEvent) => void;
  onWordRotate: (word: BoardWord) => void;
  onWordRemove: (word: BoardWord) => void;
}

const GLYPH: Record<Direction, string> = { across: '➜', down: '⬇' };
const NAME: Record<Direction, string> = { across: 'across', down: 'down' };

export const Grid = memo(function Grid({
  bounds,
  board,
  cellStatus,
  hiddenKeys,
  preview,
  previewGaps,
  cursorKey,
  cursorDir,
  rotateKey,
  showRotate,
  wordsByCell,
  openWordCell,
  highlighted,
  selectedKey,
  boardLocked,
  canRotate,
  onTilePointerDown,
  onCellClick,
  onCellHover,
  onRotateDirection,
  onWordHighlight,
  onWordGrab,
  onWordRotate,
  onWordRemove,
}: GridProps) {
  const cells = [];
  for (let row = bounds.minRow; row <= bounds.maxRow; row++) {
    for (let col = bounds.minCol; col <= bounds.maxCol; col++) {
      const key = keyOf(row, col);
      const letter = board[key];
      const status = cellStatus.get(key);
      const ghost = preview.get(key);
      const isCursor = key === cursorKey;
      const inWords = wordsByCell.get(key);
      // The turn button sits on the word's first letter — the chosen cell —
      // and only shows up when that cell has a real choice of direction.
      const rotateDir = key === rotateKey && showRotate ? cursorDir : null;

      cells.push(
        <div
          key={key}
          className={`cell${isCursor ? ' is-cursor' : ''}`}
          data-cell
          data-row={row}
          data-col={col}
          onClick={() => onCellClick(key)}
        >
          {letter !== undefined && (
            <div
              className={`tile board-tile${status ? ` t-${status}` : ''}${
                hiddenKeys.has(key) ? ' tile-hidden' : ''
              }${inWords && !boardLocked ? ' is-word-tile' : ''}${
                boardLocked ? ' is-locked' : ''
              }${highlighted.has(key) ? ' is-in-word' : ''}${
                key === selectedKey ? ' is-selected' : ''
              }`}
              onPointerDown={(e) => onTilePointerDown(key, letter, e)}
            >
              {letter}
            </div>
          )}

          {letter === undefined && ghost !== undefined && (
            <div className="tile board-tile tile-preview">{ghost}</div>
          )}

          {/* A gap waiting on a letter: drawn as the hole it is, so the word's
              whole shape is visible while it's being lined up. */}
          {letter === undefined && ghost === undefined && previewGaps.has(key) && (
            <div className="tile board-tile tile-preview tile-preview-gap" />
          )}

          {inWords && key === openWordCell && (
            <WordControls
              words={inWords}
              canRotate={canRotate}
              onGrab={onWordGrab}
              onRotate={onWordRotate}
              onRemove={onWordRemove}
              onHighlight={onWordHighlight}
            />
          )}

          {/* Shows the way the word will read, so it doubles as the only sign
              of which direction was assumed. Tapping it turns the cell. */}
          {rotateDir !== null && (
            <button
              type="button"
              className="cell-rotate"
              title={`Placing ${NAME[rotateDir]} — click to place ${
                NAME[rotateDir === 'across' ? 'down' : 'across']
              }`}
              aria-label={`Placing ${NAME[rotateDir]}. Click to place ${
                NAME[rotateDir === 'across' ? 'down' : 'across']
              }`}
              onPointerDown={(e) => e.stopPropagation()}
              onClick={(e) => {
                e.stopPropagation();
                onRotateDirection();
              }}
            >
              {GLYPH[rotateDir]}
            </button>
          )}
        </div>,
      );
    }
  }

  return (
    <div
      className="board"
      style={{
        gridTemplateColumns: `repeat(${bounds.maxCol - bounds.minCol + 1}, var(--cell))`,
      }}
      // Delegated rather than a handler per cell: at 33 squares square that's a
      // thousand listeners saved, and the event tells us the cell anyway.
      onPointerOver={(e) => {
        const cell = (e.target as HTMLElement).closest('[data-cell]') as HTMLElement | null;
        onCellHover(
          cell ? keyOf(Number(cell.dataset.row), Number(cell.dataset.col)) : null,
        );
      }}
      onPointerLeave={() => onCellHover(null)}
    >
      {cells}
    </div>
  );
});
