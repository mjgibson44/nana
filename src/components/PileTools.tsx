import { GapIcon, ShuffleIcon, UndoIcon } from './icons';

interface PileToolsProps {
  onUndo: () => void;
  /** False when there's nothing left to undo. */
  canUndo: boolean;
  onShuffle: () => void;
  onAddGap: () => void;
}

/**
 * The tools that act on the pile. They share the word bar's row with confirm and
 * cancel, since all five are used in the same breath while building a word.
 */
export function PileTools({ onUndo, canUndo, onShuffle, onAddGap }: PileToolsProps) {
  return (
    <div className="pile-tools">
      <button
        type="button"
        className="icon-btn"
        title="Undo the last move"
        aria-label="Undo the last move"
        disabled={!canUndo}
        // A click leaves the button focused, which would steal Space and Enter
        // from the word being built.
        onClick={(e) => {
          e.currentTarget.blur();
          onUndo();
        }}
      >
        <UndoIcon />
      </button>

      <button
        type="button"
        className="icon-btn"
        title="Shuffle the pile"
        aria-label="Shuffle the pile"
        onClick={(e) => {
          e.currentTarget.blur();
          onShuffle();
        }}
      >
        <ShuffleIcon />
      </button>

      <button
        type="button"
        className="icon-btn"
        title="Add a gap tile (or press space) — it sits on a letter already on the board"
        aria-label="Add a gap tile"
        onClick={(e) => {
          e.currentTarget.blur();
          onAddGap();
        }}
      >
        <GapIcon />
      </button>
    </div>
  );
}
