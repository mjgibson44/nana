interface RackProps {
  letters: string[];
  hiddenIndex: number | null;
  /** Rack indices claimed by the word being built, in typed order. */
  picks: number[];
  /** How many tiles at the end of the pile just arrived (Endless drops) —
   * they get a little landing animation. 0 when nothing is fresh. */
  justAdded: number;
  onTilePointerDown: (index: number, letter: string, e: React.PointerEvent) => void;
}

export function Rack({ letters, hiddenIndex, picks, justAdded, onTilePointerDown }: RackProps) {
  // New tiles are always appended, so the fresh ones are the last `justAdded`.
  const firstNew = justAdded > 0 ? letters.length - justAdded : Number.POSITIVE_INFINITY;

  return (
    <div className="rack" data-rack>
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
  );
}
