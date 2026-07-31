import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { validateBoard } from './game/board';
import { COMMON_WORDS } from './game/commonWords';
import { loadDictionary } from './game/dictionary';
import { generatePuzzle } from './game/generator';
import type { CellKey, TileMap } from './game/types';
import { keyOf } from './game/types';
import { Grid } from './components/Grid';
import { Rack } from './components/Rack';
import { StatusBar } from './components/StatusBar';

export const GRID_SIZE = 23;
const TILE_COUNT = 20;

export type CellStatus = 'valid' | 'invalid' | 'isolated';

export type DragSource = { type: 'rack'; index: number } | { type: 'board'; key: CellKey };

interface DragState {
  letter: string;
  source: DragSource;
  pointerId: number;
}

function shuffleArray<T>(items: T[]): T[] {
  const arr = items.slice();
  for (let i = arr.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [arr[i], arr[j]] = [arr[j], arr[i]];
  }
  return arr;
}

export default function App() {
  const [rack, setRack] = useState<string[]>([]);
  const [board, setBoard] = useState<TileMap>({});
  const [drag, setDrag] = useState<DragState | null>(null);
  const [dictionary, setDictionary] = useState<Set<string> | null>(null);
  const [dictionaryError, setDictionaryError] = useState(false);
  const [gameId, setGameId] = useState(0);

  const boardWrapRef = useRef<HTMLDivElement>(null);
  const ghostRef = useRef<HTMLDivElement>(null);
  const ghostPos = useRef({ x: 0, y: 0 });

  const newGame = useCallback(() => {
    const puzzle = generatePuzzle(COMMON_WORDS, TILE_COUNT);
    setRack(puzzle.letters);
    setBoard({});
    setDrag(null);
    setGameId((id) => id + 1);
  }, []);

  useEffect(() => {
    newGame();
  }, [newGame]);

  useEffect(() => {
    let cancelled = false;
    loadDictionary(`${import.meta.env.BASE_URL}dictionary.txt`)
      .then((dict) => {
        if (!cancelled) setDictionary(dict);
      })
      .catch(() => {
        if (!cancelled) setDictionaryError(true);
      });
    return () => {
      cancelled = true;
    };
  }, []);

  // Center the board viewport on each new game.
  useEffect(() => {
    const wrap = boardWrapRef.current;
    if (wrap) {
      wrap.scrollLeft = (wrap.scrollWidth - wrap.clientWidth) / 2;
      wrap.scrollTop = (wrap.scrollHeight - wrap.clientHeight) / 2;
    }
  }, [gameId]);

  const validation = useMemo(
    () => (dictionary ? validateBoard(board, dictionary) : null),
    [board, dictionary],
  );

  const cellStatus = useMemo(() => {
    const status = new Map<CellKey, CellStatus>();
    if (!validation) return status;
    for (const run of validation.runs) {
      for (const cell of run.cells) {
        if (!run.valid) status.set(cell, 'invalid');
        else if (status.get(cell) !== 'invalid') status.set(cell, 'valid');
      }
    }
    for (const key of validation.isolatedTiles) status.set(key, 'isolated');
    return status;
  }, [validation]);

  const won =
    validation !== null && validation.ok && rack.length === 0 && drag === null;

  const startDrag = useCallback(
    (letter: string, source: DragSource, e: React.PointerEvent) => {
      e.preventDefault();
      ghostPos.current = { x: e.clientX, y: e.clientY };
      setDrag({ letter, source, pointerId: e.pointerId });
    },
    [],
  );

  const dropAt = useCallback(
    (x: number, y: number) => {
      if (!drag) return;
      const { letter, source } = drag;
      const target = document.elementFromPoint(x, y);
      const cellEl = target?.closest('[data-cell]') as HTMLElement | null;

      if (cellEl) {
        const key = keyOf(Number(cellEl.dataset.row), Number(cellEl.dataset.col));
        const sameCell = source.type === 'board' && source.key === key;
        if (sameCell || !(key in board)) {
          setBoard((prev) => {
            const next = { ...prev };
            if (source.type === 'board') delete next[source.key];
            next[key] = letter;
            return next;
          });
          if (source.type === 'rack') {
            setRack((prev) => prev.filter((_, i) => i !== source.index));
          }
        }
      } else if (target?.closest('[data-rack]')) {
        if (source.type === 'board') {
          setBoard((prev) => {
            const next = { ...prev };
            delete next[source.key];
            return next;
          });
          setRack((prev) => [...prev, letter]);
        }
      }
      setDrag(null);
    },
    [drag, board],
  );

  useEffect(() => {
    if (!drag) return;
    const move = (e: PointerEvent) => {
      if (e.pointerId !== drag.pointerId) return;
      ghostPos.current = { x: e.clientX, y: e.clientY };
      if (ghostRef.current) {
        ghostRef.current.style.transform = `translate(${e.clientX}px, ${e.clientY}px)`;
      }
    };
    const up = (e: PointerEvent) => {
      if (e.pointerId !== drag.pointerId) return;
      dropAt(e.clientX, e.clientY);
    };
    const cancel = (e: PointerEvent) => {
      if (e.pointerId === drag.pointerId) setDrag(null);
    };
    window.addEventListener('pointermove', move);
    window.addEventListener('pointerup', up);
    window.addEventListener('pointercancel', cancel);
    return () => {
      window.removeEventListener('pointermove', move);
      window.removeEventListener('pointerup', up);
      window.removeEventListener('pointercancel', cancel);
    };
  }, [drag, dropAt]);

  const returnToRack = useCallback(
    (key: CellKey) => {
      const letter = board[key];
      if (letter === undefined) return;
      setBoard((prev) => {
        const next = { ...prev };
        delete next[key];
        return next;
      });
      setRack((prev) => [...prev, letter]);
    },
    [board],
  );

  // Double-press detection on board tiles (works for mouse double-click and
  // touch double-tap; native dblclick is unreliable once pointerdown is
  // preventDefault-ed).
  const lastPress = useRef<{ key: CellKey; time: number } | null>(null);

  const onBoardTilePointerDown = useCallback(
    (key: CellKey, letter: string, e: React.PointerEvent) => {
      const now = performance.now();
      if (lastPress.current?.key === key && now - lastPress.current.time < 350) {
        lastPress.current = null;
        e.preventDefault();
        returnToRack(key);
        return;
      }
      lastPress.current = { key, time: now };
      startDrag(letter, { type: 'board', key }, e);
    },
    [returnToRack, startDrag],
  );

  return (
    <div className="app">
      <header className="header">
        <div className="title-block">
          <h1 className="title">🍌 Nana</h1>
          <span className="subtitle">a Bananagrams-style word game</span>
        </div>
        <div className="header-actions">
          <button className="btn" onClick={() => setRack(shuffleArray)}>
            Shuffle pile
          </button>
          <button className="btn btn-primary" onClick={newGame}>
            New game
          </button>
        </div>
      </header>

      <div className="board-wrap" ref={boardWrapRef}>
        <Grid
          size={GRID_SIZE}
          board={board}
          cellStatus={cellStatus}
          hiddenKey={drag?.source.type === 'board' ? drag.source.key : null}
          onTilePointerDown={onBoardTilePointerDown}
        />
      </div>

      <StatusBar
        validation={validation}
        dictionaryReady={dictionary !== null}
        dictionaryError={dictionaryError}
        tilesLeft={rack.length}
        won={won}
      />

      <Rack
        letters={rack}
        hiddenIndex={drag?.source.type === 'rack' ? drag.source.index : null}
        onTilePointerDown={(index, letter, e) => startDrag(letter, { type: 'rack', index }, e)}
      />

      {drag && (
        <div
          className="tile ghost"
          ref={ghostRef}
          style={{
            transform: `translate(${ghostPos.current.x}px, ${ghostPos.current.y}px)`,
          }}
        >
          {drag.letter}
        </div>
      )}
    </div>
  );
}
