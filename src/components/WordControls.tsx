import type { Direction } from '../game/types';
import type { BoardWord } from '../App';

interface WordControlsProps {
  /** Every word whose first letter sits in this cell (across and/or down). */
  words: BoardWord[];
  /** False when rotating that word would leave the grid or hit another word. */
  canRotate: (word: BoardWord) => boolean;
  onGrab: (word: BoardWord, e: React.PointerEvent) => void;
  onRotate: (word: BoardWord) => void;
  onRemove: (word: BoardWord) => void;
  onHighlight: (word: BoardWord | null) => void;
  onPointerEnter: () => void;
  onPointerLeave: () => void;
}

const GLYPH = { across: '➜', down: '⬇' } as const;

const flipped = (dir: Direction): Direction => (dir === 'across' ? 'down' : 'across');

export function WordControls({
  words,
  canRotate,
  onGrab,
  onRotate,
  onRemove,
  onHighlight,
  onPointerEnter,
  onPointerLeave,
}: WordControlsProps) {
  return (
    <div
      className="word-controls"
      onPointerEnter={onPointerEnter}
      onPointerLeave={onPointerLeave}
      // The popover sits over its own tile; don't let clicks start a tile drag.
      onPointerDown={(e) => e.stopPropagation()}
    >
      {words.map((word) => (
        <div
          key={word.direction}
          className="word-controls-row"
          onPointerEnter={() => onHighlight(word)}
          onPointerLeave={() => onHighlight(null)}
        >
          <span className="word-controls-name">
            <span className="word-controls-dir">{GLYPH[word.direction]}</span>
            {word.word.toUpperCase()}
          </span>

          <button
            type="button"
            className="word-btn word-btn-grab"
            title={`Drag ${word.word.toUpperCase()}`}
            aria-label={`Drag ${word.word.toUpperCase()}`}
            onPointerDown={(e) => {
              e.stopPropagation();
              onGrab(word, e);
            }}
          >
            ⠿
          </button>

          {/* Shows the direction the word will read after turning, which is
              clearer at this size than a rotate glyph. */}
          <button
            type="button"
            className="word-btn word-btn-turn"
            title={
              canRotate(word)
                ? `Turn ${word.word.toUpperCase()} ${flipped(word.direction)}`
                : `No room to turn ${word.word.toUpperCase()} ${flipped(word.direction)}`
            }
            aria-label={`Turn ${word.word.toUpperCase()} ${flipped(word.direction)}`}
            disabled={!canRotate(word)}
            onClick={(e) => {
              e.stopPropagation();
              onRotate(word);
            }}
          >
            {GLYPH[flipped(word.direction)]}
          </button>

          <button
            type="button"
            className="word-btn word-btn-remove"
            title={`Return ${word.word.toUpperCase()} to the pile`}
            aria-label={`Return ${word.word.toUpperCase()} to the pile`}
            onClick={(e) => {
              e.stopPropagation();
              onRemove(word);
            }}
          >
            ✕
          </button>
        </div>
      ))}
    </div>
  );
}
