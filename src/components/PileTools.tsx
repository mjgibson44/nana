import type { Direction } from '../game/types';
import { BackspaceIcon, GapIcon, RotateIcon, ShuffleIcon } from './icons';

interface PileToolsProps {
  /** Backspace: takes back the last staged letter, or eats into a selected
   * word on the board — same as the Backspace key. */
  onBackspace: () => void;
  /** False when there is nothing staged and nothing selected to take back. */
  canBackspace: boolean;
  /** Flip the chosen cell between across and down. */
  onRotate: () => void;
  /** False when no cell is chosen, or it can only go one way. */
  canRotate: boolean;
  /** The direction rotating would switch to — drawn on the button. */
  rotateTo: Direction;
  onShuffle: () => void;
  onAddGap: () => void;
}

/**
 * The tools that act on the pile and the word being built. They share the word
 * bar's row with confirm and cancel, since all of them are used in the same
 * breath while building a word.
 */
export function PileTools({
  onBackspace,
  canBackspace,
  onRotate,
  canRotate,
  rotateTo,
  onShuffle,
  onAddGap,
}: PileToolsProps) {
  return (
    <div className="pile-tools">
      <button
        type="button"
        className="icon-btn"
        title="Remove the last letter (or press Backspace)"
        aria-label="Remove the last letter"
        disabled={!canBackspace}
        // A click leaves the button focused, which would steal Space and Enter
        // from the word being built.
        onClick={(e) => {
          e.currentTarget.blur();
          onBackspace();
        }}
      >
        <BackspaceIcon />
      </button>

      <button
        type="button"
        className="icon-btn"
        title={`Turn the word to read ${rotateTo}`}
        aria-label={`Turn the word to read ${rotateTo}`}
        disabled={!canRotate}
        onClick={(e) => {
          e.currentTarget.blur();
          onRotate();
        }}
      >
        <RotateIcon to={rotateTo} />
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
