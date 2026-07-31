import type { Direction } from '../game/types';
import type { WordVerdict } from '../App';

interface WordBarProps {
  /** Staged letters, in the order they were typed. */
  letters: string[];
  /** 'spell' = letters chosen first, still looking for a spot on the board.
   *  'place' = a cell is chosen and letters are landing on the board live.
   *  'idle' = nothing in progress; the bar stays put so the board never shifts
   *  under the pointer mid-interaction. */
  mode: 'idle' | 'spell' | 'place';
  /** In 'place' mode, the locked direction — null while still picking one. */
  direction: Direction | null;
  /** True when the word ran off the edge of the grid. */
  overflowed: boolean;
  /** Dictionary check on the word so far; null when there's nothing to judge. */
  verdict: WordVerdict | null;
  onRemove: (position: number) => void;
  onClear: () => void;
  onConfirm: () => void;
  onCancel: () => void;
}

function list(words: string[]): string {
  const upper = [...new Set(words)].map((w) => w.toUpperCase());
  if (upper.length <= 1) return upper.join('');
  return `${upper.slice(0, -1).join(', ')} and ${upper[upper.length - 1]}`;
}

function verdictText(verdict: WordVerdict): string {
  const words = list(verdict.words);
  const plural = new Set(verdict.words).size > 1;
  if (verdict.ok) {
    // On the board the placement may build on tiles already there, so name what
    // it actually spells rather than just saying "yes".
    return verdict.onBoard
      ? `Spells ${words} — ${plural ? 'all real words' : 'a real word'}`
      : `${words} is a real word`;
  }
  return verdict.onBoard
    ? `Would spell ${words} — not ${plural ? 'real words' : 'a real word'}`
    : `${words} is not a real word`;
}

function hintFor(
  mode: 'idle' | 'spell' | 'place',
  direction: Direction | null,
  overflowed: boolean,
  word: string,
  count: number,
): string {
  if (mode === 'idle') {
    return 'Type letters to spell a word, or hover a cell and pick ➜ / ⬇ to build one there.';
  }
  if (overflowed) {
    return `${word} doesn't fit there — it runs off the edge of the board.`;
  }
  if (mode === 'place') {
    return direction === null
      ? 'Pick a direction: ➜ across or ⬇ down (or press → / ↓).'
      : 'Type or tap pile letters to keep going, then ✓ (or Enter) to confirm.';
  }
  return count === 0
    ? 'Type letters to pull them from your pile.'
    : `Hover a cell and click ➜ to place ${word} across, or ⬇ for down.`;
}

export function WordBar({
  letters,
  mode,
  direction,
  overflowed,
  verdict,
  onRemove,
  onClear,
  onConfirm,
  onCancel,
}: WordBarProps) {
  const word = letters.join('').toUpperCase();
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
            className={`tile word-tile${
              verdict === null ? '' : verdict.ok ? ' t-valid' : ' t-invalid'
            }`}
            title="Remove this letter"
            onClick={() => onRemove(position)}
          >
            {letter}
          </button>
        ))}
      </div>

      {verdict !== null && !overflowed && (
        <span className={`word-verdict word-verdict-${verdict.ok ? 'good' : 'bad'}`}>
          {verdict.ok ? '✓' : '✕'} {verdictText(verdict)}
        </span>
      )}

      <span className="word-bar-hint">
        {hintFor(mode, direction, overflowed, word, letters.length)}
      </span>

      <div className="word-bar-actions">
        {mode === 'place' ? (
          <>
            <button
              type="button"
              className="btn btn-confirm"
              disabled={letters.length === 0 || overflowed}
              onClick={onConfirm}
            >
              ✓ Confirm
            </button>
            <button type="button" className="btn btn-cancel" onClick={onCancel}>
              ✕ Cancel
            </button>
          </>
        ) : (
          <button
            type="button"
            className="btn btn-cancel"
            disabled={letters.length === 0}
            onClick={onClear}
          >
            ✕ Clear
          </button>
        )}
      </div>
    </div>
  );
}
