import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { extractRuns, validateBoard } from './game/board';
import { COMMON_WORDS } from './game/commonWords';
import { loadDictionary } from './game/dictionary';
import { generatePuzzle } from './game/generator';
import { findAvailable, planPlacement, planWordCells } from './game/placement';
import type { CellKey, Direction, TileMap } from './game/types';
import { keyOf, parseKey } from './game/types';
import { Grid } from './components/Grid';
import { Rack } from './components/Rack';
import { StatusBar } from './components/StatusBar';
import { WordBar } from './components/WordBar';

export const GRID_SIZE = 23;
const TILE_COUNT = 20;
/** Pointer travel under this (px) counts as a tap, not a drag. */
const TAP_SLOP = 6;

export type CellStatus = 'valid' | 'invalid' | 'isolated';

export type DragSource = { type: 'rack'; index: number } | { type: 'board'; key: CellKey };

interface DragState {
  letter: string;
  source: DragSource;
  pointerId: number;
  startX: number;
  startY: number;
}

/** Live dictionary check on the word being built, shown in the word bar. */
export interface WordVerdict {
  ok: boolean;
  /** The words being judged — just the offending ones when `ok` is false. */
  words: string[];
  /** True when these are the words the board would really gain, rather than
   * only the letters typed so far. */
  onBoard: boolean;
}

/** A maximal run of 2+ tiles on the board — what the word controls act on. */
export interface BoardWord {
  word: string;
  direction: Direction;
  cells: CellKey[];
}

/** A whole word being dragged as one piece, grabbed by its first letter. */
interface WordDragState {
  word: BoardWord;
  letters: string[];
  pointerId: number;
}

/** Grace period so the pointer can travel from a tile to its popover. */
const HOVER_GRACE_MS = 140;

/**
 * Word-building state, shared by both keyboard flows:
 *
 *  - `spell`: letters were chosen first (by typing or tapping the pile) and are
 *    waiting for a home. The player hovers a cell and clicks a direction arrow.
 *  - `place`: a board cell was chosen first. Once a direction is locked in,
 *    letters land on the board as they are typed, until confirmed or cancelled.
 *
 * `picks` holds pile indices in typed order in both cases, so a player can start
 * either way round and switch freely.
 */
type Interaction =
  | { kind: 'idle' }
  | { kind: 'spell'; picks: number[] }
  | { kind: 'place'; anchor: CellKey; dir: Direction | null; picks: number[] };

const IDLE: Interaction = { kind: 'idle' };

function picksOf(interaction: Interaction): number[] {
  return interaction.kind === 'idle' ? [] : interaction.picks;
}

function withPicks(interaction: Interaction, picks: number[]): Interaction {
  if (interaction.kind === 'place') return { ...interaction, picks };
  if (picks.length === 0) return IDLE;
  return { kind: 'spell', picks };
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
  const [interaction, setInteraction] = useState<Interaction>(IDLE);
  const [hoverArrow, setHoverArrow] = useState<{ key: CellKey; dir: Direction } | null>(null);
  const [openWordCell, setOpenWordCell] = useState<CellKey | null>(null);
  const [highlightedWord, setHighlightedWord] = useState<BoardWord | null>(null);
  const [wordDrag, setWordDrag] = useState<WordDragState | null>(null);

  const boardWrapRef = useRef<HTMLDivElement>(null);
  const ghostRef = useRef<HTMLDivElement>(null);
  const ghostPos = useRef({ x: 0, y: 0 });
  const wordGhostRef = useRef<HTMLDivElement>(null);
  const wordGhostPos = useRef({ x: 0, y: 0 });
  /** Swallow the click that follows a drop, so it doesn't also select a cell. */
  const swallowClick = useRef(false);
  const hoverTimer = useRef<number | null>(null);

  const newGame = useCallback(() => {
    const puzzle = generatePuzzle(COMMON_WORDS, TILE_COUNT);
    setRack(puzzle.letters);
    setBoard({});
    setDrag(null);
    setInteraction(IDLE);
    setHoverArrow(null);
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

  const picks = picksOf(interaction);

  const pickList = useMemo(
    () =>
      picks
        .filter((i) => rack[i] !== undefined)
        .map((i) => ({ letter: rack[i], rackIndex: i })),
    [picks, rack],
  );

  /** Where the word would go right now: the locked anchor, or a hovered arrow. */
  const target = useMemo(() => {
    if (interaction.kind === 'place' && interaction.dir !== null) {
      return { key: interaction.anchor, dir: interaction.dir };
    }
    if (hoverArrow && pickList.length > 0) return hoverArrow;
    return null;
  }, [interaction, hoverArrow, pickList.length]);

  const plan = useMemo(() => {
    if (!target || pickList.length === 0) return null;
    return planPlacement(board, GRID_SIZE, parseKey(target.key), target.dir, pickList);
  }, [target, board, pickList]);

  const preview = useMemo(() => {
    const map = new Map<CellKey, string>();
    if (plan) for (const step of plan.steps) map.set(step.key, step.letter);
    return map;
  }, [plan]);

  /**
   * Live dictionary check on the word being built.
   *
   * Once a target is known we judge the words the board would actually gain,
   * not the letters as typed — flowing over an existing tile or butting up
   * against a neighbour can spell something quite different (typing C,T through
   * an existing A makes CAT). Before a target is picked, the typed letters are
   * all there is to go on.
   */
  const verdict = useMemo((): WordVerdict | null => {
    if (!dictionary) return null;
    const typed = pickList.map((p) => p.letter).join('');
    // A lone tile is never a word on its own; it crosses one.
    if (typed.length < 2) return null;

    if (plan) {
      if (!plan.complete) return null; // overflow has its own message
      const next = { ...board };
      for (const step of plan.steps) next[step.key] = step.letter;
      const placed = new Set(plan.steps.map((step) => step.key));
      const runs = extractRuns(next).filter((run) =>
        run.cells.some((cell) => placed.has(cell)),
      );
      if (runs.length === 0) return null; // lands isolated; nothing to judge yet
      const bad = runs.filter((run) => !dictionary.has(run.word));
      return {
        ok: bad.length === 0,
        words: (bad.length > 0 ? bad : runs).map((run) => run.word),
        onBoard: true,
      };
    }

    return { ok: dictionary.has(typed), words: [typed], onBoard: false };
  }, [dictionary, pickList, plan, board]);

  const won =
    validation !== null &&
    validation.ok &&
    rack.length === 0 &&
    drag === null &&
    wordDrag === null &&
    interaction.kind === 'idle';

  /* ------------------------------ word controls ----------------------------- */

  // Every cell of a word maps to that word, so its controls are reachable from
  // any of its letters rather than only the first. A tile at a crossing belongs
  // to two runs and offers both.
  //
  // Runs come straight from the board, not from validation, so the controls work
  // before the dictionary has loaded and on words that aren't real words yet.
  const wordsByCell = useMemo(() => {
    const map = new Map<CellKey, BoardWord[]>();
    for (const run of extractRuns(board)) {
      for (const cell of run.cells) {
        const existing = map.get(cell);
        if (existing) existing.push(run);
        else map.set(cell, [run]);
      }
    }
    return map;
  }, [board]);

  const canRotate = useCallback(
    (word: BoardWord) =>
      planWordCells(
        board,
        GRID_SIZE,
        word.cells.length,
        new Set(word.cells),
        word.direction === 'across' ? 'down' : 'across',
        parseKey(word.cells[0]),
      ) !== null,
    [board],
  );

  const onWordHover = useCallback((key: CellKey, entering: boolean) => {
    if (hoverTimer.current !== null) {
      window.clearTimeout(hoverTimer.current);
      hoverTimer.current = null;
    }
    if (entering) {
      setOpenWordCell(key);
      return;
    }
    hoverTimer.current = window.setTimeout(() => {
      hoverTimer.current = null;
      setOpenWordCell(null);
      setHighlightedWord(null);
    }, HOVER_GRACE_MS);
  }, []);

  const closeWordControls = useCallback(() => {
    if (hoverTimer.current !== null) {
      window.clearTimeout(hoverTimer.current);
      hoverTimer.current = null;
    }
    setOpenWordCell(null);
    setHighlightedWord(null);
  }, []);

  useEffect(
    () => () => {
      if (hoverTimer.current !== null) window.clearTimeout(hoverTimer.current);
    },
    [],
  );

  /** Move a word's tiles so its first letter lands on `start`. */
  const moveWord = useCallback(
    (word: BoardWord, start: CellKey, dir: Direction) => {
      const own = new Set(word.cells);
      const targets = planWordCells(
        board,
        GRID_SIZE,
        word.cells.length,
        own,
        dir,
        parseKey(start),
      );
      if (!targets) return false;
      const letters = word.cells.map((key) => board[key]);
      setBoard((prev) => {
        const next = { ...prev };
        for (const key of word.cells) delete next[key];
        targets.forEach((key, i) => {
          next[key] = letters[i];
        });
        return next;
      });
      return true;
    },
    [board],
  );

  const rotateWord = useCallback(
    (word: BoardWord) => {
      moveWord(word, word.cells[0], word.direction === 'across' ? 'down' : 'across');
      setHighlightedWord(null);
    },
    [moveWord],
  );

  const removeWord = useCallback(
    (word: BoardWord) => {
      const letters = word.cells.map((key) => board[key]).filter((l) => l !== undefined);
      setBoard((prev) => {
        const next = { ...prev };
        for (const key of word.cells) delete next[key];
        return next;
      });
      setRack((prev) => [...prev, ...letters]);
      closeWordControls();
    },
    [board, closeWordControls],
  );

  const onWordGrab = useCallback(
    (word: BoardWord, e: React.PointerEvent) => {
      e.preventDefault();
      const letters = word.cells.map((key) => board[key]);
      wordGhostPos.current = { x: e.clientX, y: e.clientY };
      setWordDrag({ word, letters, pointerId: e.pointerId });
      closeWordControls();
    },
    [board, closeWordControls],
  );

  useEffect(() => {
    if (!wordDrag) return;
    const move = (e: PointerEvent) => {
      if (e.pointerId !== wordDrag.pointerId) return;
      wordGhostPos.current = { x: e.clientX, y: e.clientY };
      if (wordGhostRef.current) {
        wordGhostRef.current.style.transform = `translate(${e.clientX}px, ${e.clientY}px)`;
      }
    };
    const up = (e: PointerEvent) => {
      if (e.pointerId !== wordDrag.pointerId) return;
      setWordDrag(null);
      const el = document.elementFromPoint(e.clientX, e.clientY);
      const cellEl = el?.closest('[data-cell]') as HTMLElement | null;
      if (cellEl) {
        const key = keyOf(Number(cellEl.dataset.row), Number(cellEl.dataset.col));
        moveWord(wordDrag.word, key, wordDrag.word.direction);
        swallowClick.current = true;
        window.setTimeout(() => {
          swallowClick.current = false;
        }, 0);
      }
    };
    const cancel = (e: PointerEvent) => {
      if (e.pointerId === wordDrag.pointerId) setWordDrag(null);
    };
    window.addEventListener('pointermove', move);
    window.addEventListener('pointerup', up);
    window.addEventListener('pointercancel', cancel);
    return () => {
      window.removeEventListener('pointermove', move);
      window.removeEventListener('pointerup', up);
      window.removeEventListener('pointercancel', cancel);
    };
  }, [wordDrag, moveWord]);

  /* ------------------------------ word building ----------------------------- */

  const setPicks = useCallback((next: number[]) => {
    setInteraction((prev) => withPicks(prev, next));
  }, []);

  /** Claim a pile tile for the current word, or release it if already claimed. */
  const togglePick = useCallback(
    (index: number) => {
      setInteraction((prev) => {
        const current = picksOf(prev);
        const at = current.indexOf(index);
        return withPicks(
          prev,
          at === -1 ? [...current, index] : current.filter((_, i) => i !== at),
        );
      });
    },
    [],
  );

  const typeLetter = useCallback(
    (letter: string) => {
      setInteraction((prev) => {
        const current = picksOf(prev);
        const index = findAvailable(rack, letter, current);
        if (index === -1) return prev;
        return withPicks(prev, [...current, index]);
      });
    },
    [rack],
  );

  const cancelWord = useCallback(() => {
    setInteraction(IDLE);
    setHoverArrow(null);
  }, []);

  /** Drop the planned tiles onto the board and spend the pile letters they used. */
  const commit = useCallback(
    (anchor: CellKey, dir: Direction) => {
      if (pickList.length === 0) return;
      const result = planPlacement(board, GRID_SIZE, parseKey(anchor), dir, pickList);
      if (result.steps.length === 0 || !result.complete) return;

      setBoard((prev) => {
        const next = { ...prev };
        for (const step of result.steps) next[step.key] = step.letter;
        return next;
      });
      const spent = new Set(result.steps.map((step) => step.rackIndex));
      setRack((prev) => prev.filter((_, i) => !spent.has(i)));
      setInteraction(IDLE);
      setHoverArrow(null);
    },
    [board, pickList],
  );

  const onArrow = useCallback(
    (key: CellKey, dir: Direction) => {
      // Letters already chosen → this arrow says where they go. Otherwise the
      // player is starting from the board, so lock the direction and wait.
      if (pickList.length > 0) commit(key, dir);
      else setInteraction({ kind: 'place', anchor: key, dir, picks: [] });
      setHoverArrow(null);
    },
    [pickList.length, commit],
  );

  const onArrowHover = useCallback(
    (key: CellKey, dir: Direction, entering: boolean) => {
      setHoverArrow((prev) => {
        if (entering) return { key, dir };
        return prev && prev.key === key && prev.dir === dir ? null : prev;
      });
    },
    [],
  );

  const onCellClick = useCallback((key: CellKey) => {
    if (swallowClick.current) return;
    setInteraction((prev) => {
      // Mid-word: ignore stray board clicks so a word isn't lost by accident.
      if (prev.kind === 'place' && prev.dir !== null) return prev;
      return { kind: 'place', anchor: key, dir: null, picks: picksOf(prev) };
    });
  }, []);

  /* -------------------------------- keyboard -------------------------------- */

  useEffect(() => {
    const onKeyDown = (e: KeyboardEvent) => {
      if (e.metaKey || e.ctrlKey || e.altKey) return;
      const el = e.target as HTMLElement | null;
      const tag = el?.tagName;
      if (tag === 'INPUT' || tag === 'TEXTAREA' || el?.isContentEditable) return;
      // Let a focused button keep its own activation keys.
      if (tag === 'BUTTON' && (e.key === 'Enter' || e.key === ' ')) return;

      if (/^[a-zA-Z]$/.test(e.key)) {
        e.preventDefault();
        typeLetter(e.key);
        return;
      }

      if (e.key === 'Backspace') {
        if (picks.length === 0) return;
        e.preventDefault();
        setPicks(picks.slice(0, -1));
        return;
      }

      if (e.key === 'Escape') {
        if (interaction.kind === 'idle') return;
        e.preventDefault();
        cancelWord();
        return;
      }

      if (e.key === 'Enter') {
        if (interaction.kind !== 'place' || interaction.dir === null) return;
        e.preventDefault();
        commit(interaction.anchor, interaction.dir);
        return;
      }

      // Arrow keys choose a direction once a cell has been picked.
      if (interaction.kind === 'place' && interaction.dir === null) {
        const dir: Direction | null =
          e.key === 'ArrowRight' ? 'across' : e.key === 'ArrowDown' ? 'down' : null;
        if (dir) {
          e.preventDefault();
          onArrow(interaction.anchor, dir);
        }
      }
    };

    window.addEventListener('keydown', onKeyDown);
    return () => window.removeEventListener('keydown', onKeyDown);
  }, [interaction, picks, typeLetter, setPicks, cancelWord, commit, onArrow]);

  /* -------------------------------- dragging -------------------------------- */

  const startDrag = useCallback(
    (letter: string, source: DragSource, e: React.PointerEvent) => {
      e.preventDefault();
      ghostPos.current = { x: e.clientX, y: e.clientY };
      setDrag({
        letter,
        source,
        pointerId: e.pointerId,
        startX: e.clientX,
        startY: e.clientY,
      });
    },
    [],
  );

  const dropAt = useCallback(
    (x: number, y: number) => {
      if (!drag) return;
      const { letter, source, startX, startY } = drag;
      setDrag(null);

      // A tap on a pile tile selects it for the current word instead of moving it.
      const tap = Math.abs(x - startX) < TAP_SLOP && Math.abs(y - startY) < TAP_SLOP;
      if (tap && source.type === 'rack') {
        togglePick(source.index);
        return;
      }

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
            setInteraction(IDLE);
          }
        }
        swallowClick.current = true;
        window.setTimeout(() => {
          swallowClick.current = false;
        }, 0);
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
    },
    [drag, board, togglePick],
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

  const shufflePile = useCallback(() => {
    setRack(shuffleArray);
    setInteraction(IDLE);
    setHoverArrow(null);
  }, []);

  // Empty cells offer their direction arrows on hover, so a word can be started
  // anywhere without clicking the cell first. They stand down once letters are
  // actually landing (that word owns the board until it's confirmed) and while
  // something is mid-drag.
  const midFill = interaction.kind === 'place' && interaction.dir !== null;
  const hoverArrows = !midFill && drag === null && wordDrag === null;

  const hiddenKeys = useMemo(() => {
    const keys = new Set<CellKey>();
    if (drag?.source.type === 'board') keys.add(drag.source.key);
    if (wordDrag) for (const key of wordDrag.word.cells) keys.add(key);
    return keys;
  }, [drag, wordDrag]);

  const highlighted = useMemo(
    () => new Set<CellKey>(highlightedWord?.cells ?? []),
    [highlightedWord],
  );

  return (
    <div className="app">
      <header className="header">
        <div className="title-block">
          <h1 className="title">🍌 Nana</h1>
          <span className="subtitle">a Bananagrams-style word game</span>
        </div>
        <div className="header-actions">
          <button className="btn" onClick={shufflePile}>
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
          hiddenKeys={hiddenKeys}
          preview={preview}
          anchorKey={interaction.kind === 'place' ? interaction.anchor : null}
          hoverArrows={hoverArrows}
          anchorArrows={interaction.kind === 'place' && interaction.dir === null}
          wordsByCell={wordsByCell}
          // Word controls would fight the placement arrows, so stand down while
          // a word is being built.
          openWordCell={interaction.kind === 'idle' && !drag ? openWordCell : null}
          highlighted={highlighted}
          canRotate={canRotate}
          onTilePointerDown={onBoardTilePointerDown}
          onCellClick={onCellClick}
          onArrow={onArrow}
          onArrowHover={onArrowHover}
          onWordHover={onWordHover}
          onWordHighlight={setHighlightedWord}
          onWordGrab={onWordGrab}
          onWordRotate={rotateWord}
          onWordRemove={removeWord}
        />
      </div>

      <StatusBar
        validation={validation}
        dictionaryReady={dictionary !== null}
        dictionaryError={dictionaryError}
        tilesLeft={rack.length}
        won={won}
      />

      <WordBar
        letters={pickList.map((p) => p.letter)}
        mode={interaction.kind}
        direction={interaction.kind === 'place' ? interaction.dir : null}
        overflowed={plan !== null && !plan.complete}
        verdict={verdict}
        onRemove={(position) => setPicks(picks.filter((_, i) => i !== position))}
        onClear={cancelWord}
        onCancel={cancelWord}
        onConfirm={() => {
          if (interaction.kind === 'place' && interaction.dir !== null) {
            commit(interaction.anchor, interaction.dir);
          }
        }}
      />

      <Rack
        letters={rack}
        hiddenIndex={drag?.source.type === 'rack' ? drag.source.index : null}
        picks={picks}
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

      {wordDrag && (
        <div
          className={`word-ghost word-ghost-${wordDrag.word.direction}`}
          ref={wordGhostRef}
          style={{
            transform: `translate(${wordGhostPos.current.x}px, ${wordGhostPos.current.y}px)`,
          }}
        >
          {wordDrag.letters.map((letter, i) => (
            // eslint-disable-next-line react/no-array-index-key
            <div key={i} className="tile">
              {letter}
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
