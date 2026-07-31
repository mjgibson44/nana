interface RackProps {
  letters: string[];
  hiddenIndex: number | null;
  /** Rack indices claimed by the word being built, in typed order. */
  picks: number[];
  onTilePointerDown: (index: number, letter: string, e: React.PointerEvent) => void;
}

export function Rack({ letters, hiddenIndex, picks, onTilePointerDown }: RackProps) {
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
              }`}
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
