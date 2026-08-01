import type { WordVerdict } from '../App';
import { CheckIcon, CloseIcon } from './icons';

interface WordBarProps {
  /** Staged letters in the order they were typed; null for a gap tile. */
  letters: Array<string | null>;
  /** 'spell' = letters chosen first, still looking for a spot on the board.
   *  'place' = a cell is chosen and letters are landing on the board live.
   *  'idle' = nothing in progress; the bar stays put so the board never shifts
   *  under the pointer mid-interaction. */
  mode: 'idle' | 'spell' | 'place';
  /** True when the word ran off the edge of the grid. */
  overflowed: boolean;
  /** Dictionary check on the word so far; null when there's nothing to judge.
   * Read for colour only — it tints the bar and the staged letters rather than
   * spelling the verdict out. */
  verdict: WordVerdict | null;
  /** True when confirming would really place the word: a cell is chosen and
   * every letter and gap has found its square. */
  canConfirm: boolean;
  /** True while there is anything to walk away from: staged letters, an
   * anchored cell, or a selected tile on the board. */
  canCancel: boolean;
  onRemove: (position: number) => void;
  onConfirm: () => void;
  /** Drop everything in progress — staged word, cell focus and selection. */
  onCancel: () => void;
  /** The pile's own tools, sharing this row rather than having one of their own. */
  tools?: React.ReactNode;
}

export function WordBar({
  letters,
  mode,
  overflowed,
  verdict,
  canConfirm,
  canCancel,
  onRemove,
  onConfirm,
  onCancel,
  tools,
}: WordBarProps) {
  // Overflow is the more urgent problem, so it owns the bar's colour.
  const tone = overflowed ? 'bad' : verdict === null ? '' : verdict.ok ? 'good' : 'bad';

  return (
    <div className={`word-bar${tone ? ` word-bar-${tone}` : ''}`}>
      <div className="word-bar-letters">
        {letters.length === 0 && (
          <span className="word-bar-placeholder">
            {mode === 'place' ? 'Type your word…' : 'No letters selected'}
          </span>
        )}
        {letters.map((letter, position) => (
          <button
            // eslint-disable-next-line react/no-array-index-key
            key={position}
            type="button"
            className={`tile word-tile${letter === null ? ' word-tile-gap' : ''}${
              verdict === null ? '' : verdict.ok ? ' t-valid' : ' t-invalid'
            }`}
            title={
              letter === null
                ? 'Gap — sits on a letter already on the board. Click to remove.'
                : 'Remove this letter'
            }
            onClick={() => onRemove(position)}
          >
            {letter}
          </button>
        ))}
      </div>

      <div className="word-bar-actions">
        {tools}
        <span className="word-bar-divider" aria-hidden="true" />
        <button
          type="button"
          className="icon-btn icon-btn-cancel"
          disabled={!canCancel}
          onClick={onCancel}
          title="Cancel — clear the word and selection (or press Escape)"
          aria-label="Cancel the word and selection"
        >
          <CloseIcon />
        </button>
        <button
          type="button"
          className="icon-btn icon-btn-confirm"
          disabled={!canConfirm}
          onClick={onConfirm}
          title="Place this word (or press Enter)"
          aria-label="Place this word"
        >
          <CheckIcon />
        </button>
      </div>
    </div>
  );
}
