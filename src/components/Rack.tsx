import { ShuffleIcon } from './icons';

interface RackProps {
  letters: string[];
  hiddenIndex: number | null;
  /** Rack indices claimed by the word being built, in typed order. */
  picks: number[];
  /** How many tiles at the end of the pile just arrived (Endless drops) —
   * they get a little landing animation. 0 when nothing is fresh. */
  justAdded: number;
  onTilePointerDown: (index: number, letter: string, e: React.PointerEvent) => void;
  onShuffle: () => void;
}

export function Rack({
  letters,
  hiddenIndex,
  picks,
  justAdded,
  onTilePointerDown,
  onShuffle,
}: RackProps) {
  // New tiles are always appended, so the fresh ones are the last `justAdded`.
  const firstNew = justAdded > 0 ? letters.length - justAdded : Number.POSITIVE_INFINITY;

  return (
    // data-rack rides the wrapper so a tile dropped anywhere on the pile —
    // even over the shuffle button — still counts as returning to it.
    <div className="rack-wrap" data-rack>
      <div className="rack">
        {letters.length === 0 ? (
          <span className="rack-empty">Pile empty &mdash; every tile is on the board</span>
        ) : (
          letters.map((letter, index) => {
            const position = picks.indexOf(index);
            return (
              <div
                // eslint-disable-next-line react/no-array-index-key
                key={index}
                className={`tile rack-tile${index === hiddenIndex ? ' tile-hidden' : ''}${
                  position === -1 ? '' : ' is-picked'
                }${index >= firstNew ? ' rack-tile-new' : ''}`}
                style={
                  index >= firstNew
                    ? { animationDelay: `${(index - firstNew) * 90}ms` }
                    : undefined
                }
                onPointerDown={(e) => onTilePointerDown(index, letter, e)}
              >
                {letter}
                {position !== -1 && <span className="pick-order">{position + 1}</span>}
              </div>
            );
          })
        )}
      </div>

      {/* Pinned to the pile's corner rather than scrolling with its tiles. */}
      <button
        type="button"
        className="icon-btn rack-shuffle"
        title="Shuffle the pile"
        aria-label="Shuffle the pile"
        onClick={(e) => {
          e.currentTarget.blur();
          onShuffle();
        }}
      >
        <ShuffleIcon />
      </button>
    </div>
  );
}
