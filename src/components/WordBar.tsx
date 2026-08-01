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
  onRemove: (position: number) => void;
  onClear: () => void;
  onConfirm: () => void;
  onCancel: () => void;
  /** The pile's own tools, sharing this row rather than having one of their own. */
  tools?: React.ReactNode;
}

export function WordBar({
  letters,
  mode,
  overflowed,
  verdict,
  onRemove,
  onClear,
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
        {mode === 'place' ? (
          <>
            <button
              type="button"
              className="icon-btn icon-btn-confirm"
              disabled={letters.length === 0 || overflowed}
              onClick={onConfirm}
              title="Place this word (or press Enter)"
              aria-label="Place this word"
            >
              <CheckIcon />
            </button>
            <button
              type="button"
              className="icon-btn icon-btn-cancel"
              onClick={onCancel}
              title="Cancel this word (or press Escape)"
              aria-label="Cancel this word"
            >
              <CloseIcon />
            </button>
          </>
        ) : (
          <button
            type="button"
            className="icon-btn icon-btn-cancel"
            disabled={letters.length === 0}
            onClick={onClear}
            title="Clear these letters (or press Escape)"
            aria-label="Clear these letters"
          >
            <CloseIcon />
          </button>
        )}
        {tools}
      </div>
    </div>
  );
}
