interface RackProps {
  letters: string[];
  hiddenIndex: number | null;
  onTilePointerDown: (index: number, letter: string, e: React.PointerEvent) => void;
}

export function Rack({ letters, hiddenIndex, onTilePointerDown }: RackProps) {
  return (
    <div className="rack" data-rack>
      {letters.length === 0 ? (
        <span className="rack-empty">Pile empty &mdash; every tile is on the board</span>
      ) : (
        letters.map((letter, index) => (
          <div
            // eslint-disable-next-line react/no-array-index-key
            key={index}
            className={`tile rack-tile${index === hiddenIndex ? ' tile-hidden' : ''}`}
            onPointerDown={(e) => onTilePointerDown(index, letter, e)}
          >
            {letter}
          </div>
        ))
      )}
    </div>
  );
}
