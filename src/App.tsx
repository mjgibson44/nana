import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { MIN_WORD_LENGTH, extractRuns, validateBoard } from './game/board';
import { COMMON_WORDS } from './game/commonWords';
import { loadDictionary } from './game/dictionary';
import { extendPuzzle, generatePuzzle } from './game/generator';
import {
  ALL_TILES_BONUS,
  BOARD_SIZE,
  LEVEL_COUNT,
  scoreBoard,
  tilesAddedForLevel,
} from './game/levels';
import {
  GAP,
  cursorCell,
  findAvailable,
  impliedDirections,
  planPlacement,
  planWordCells,
  startableDirections,
} from './game/placement';
import type { CellKey, Direction, TileMap } from './game/types';
import { keyOf, parseKey } from './game/types';
import { ConfirmDialog } from './components/ConfirmDialog';
import { Grid } from './components/Grid';
import { LevelSplash } from './components/LevelSplash';
import { Menu } from './components/Menu';
import { PileTools } from './components/PileTools';
import { Rack } from './components/Rack';
import { Scoreboard } from './components/Scoreboard';
import { WordBar } from './components/WordBar';

/** Pointer travel under this (px) counts as a tap, not a drag. */
const TAP_SLOP = 6;

/** How many moves back undo can reach. */
const UNDO_DEPTH = 50;

/** How long the level splash stays up before bowing out. */
const SPLASH_MS = 1700;

/** Pinch limits, as a multiple of the stylesheet's cell size. */
const MIN_ZOOM = 0.55;
const MAX_ZOOM = 1.6;

export type CellStatus = 'valid' | 'invalid' | 'isolated' | 'disconnected';

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

/**
 * Word-building state, shared by both keyboard flows:
 *
 *  - `spell`: letters were chosen first (by typing or tapping the pile) and are
 *    waiting for a cell to land on.
 *  - `place`: a board cell was chosen first. It always comes with a direction —
 *    picked for the player — so letters preview from it as soon as they're typed.
 *
 * `picks` holds pile indices in typed order in both cases, so a player can start
 * either way round and switch freely.
 */
type Interaction =
  | { kind: 'idle' }
  | { kind: 'spell'; picks: number[] }
  | { kind: 'place'; anchor: CellKey; dir: Direction; picks: number[] };

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
  /**
   * The direction to assume next time a cell that could go either way is
   * chosen. Players tend to lay several words the same way, so carrying the
   * last one forward guesses right most of the time.
   */
  const [lastDir, setLastDir] = useState<Direction>('across');
  const [highlightedWord, setHighlightedWord] = useState<BoardWord | null>(null);
  const [wordDrag, setWordDrag] = useState<WordDragState | null>(null);
  /**
   * A placed tile picked out for editing, and the direction Delete walks in.
   * Deleting steps the selection along the word so a run of letters — or the
   * whole word — can be cleared with repeated presses.
   */
  const [selection, setSelection] = useState<{ key: CellKey; dir: Direction } | null>(null);
  const [level, setLevel] = useState(1);
  /**
   * All-tiles bonuses from levels already left behind. Word scores aren't banked
   * — those words are still on the board, so they're still being counted.
   */
  const [bankedBonus, setBankedBonus] = useState(0);
  const [complete, setComplete] = useState(false);
  /** Frozen at the moment the last level is finished, so "final" means final. */
  const [finalScore, setFinalScore] = useState(0);
  /**
   * Board-and-pile snapshots, oldest first, for undo. Only play is recorded —
   * changing level or starting over wipes it, so undo never rewinds a level.
   */
  const [history, setHistory] = useState<Array<{ board: TileMap; rack: string[] }>>([]);
  /** The level the splash is announcing, or null while nothing is showing. */
  const [splashLevel, setSplashLevel] = useState<number | null>(null);
  /** Set when leaving a level early needs an answer first. */
  const [confirmSkip, setConfirmSkip] = useState<string | null>(null);
  /** Cell size in px, driven by pinch on touch devices. */
  const [zoom, setZoom] = useState(1);

  const boardWrapRef = useRef<HTMLDivElement>(null);
  const ghostRef = useRef<HTMLDivElement>(null);
  const ghostPos = useRef({ x: 0, y: 0 });
  const wordGhostRef = useRef<HTMLDivElement>(null);
  const wordGhostPos = useRef({ x: 0, y: 0 });
  /** Swallow the click that follows a drop, so it doesn't also select a cell. */
  const swallowClick = useRef(false);

  const newGame = useCallback(() => {
    setRack(generatePuzzle(COMMON_WORDS, tilesAddedForLevel(1)).letters);
    setBoard({});
    setDrag(null);
    setWordDrag(null);
    setInteraction(IDLE);
    setHighlightedWord(null);
    setSelection(null);
    setLevel(1);
    setBankedBonus(0);
    setComplete(false);
    setHistory([]);
    setConfirmSkip(null);
    setSplashLevel(1);
    setGameId((id) => id + 1);
  }, []);

  /**
   * Remember the board and pile as they are, so the change about to be made can
   * be taken back. Called before a move, never after.
   */
  const remember = useCallback(() => {
    setHistory((past) => [...past.slice(-UNDO_DEPTH + 1), { board, rack }]);
  }, [board, rack]);

  const undo = useCallback(() => {
    setHistory((past) => {
      const last = past[past.length - 1];
      if (!last) return past;
      setBoard(last.board);
      setRack(last.rack);
      setInteraction(IDLE);
      setSelection(null);
      setHighlightedWord(null);
      return past.slice(0, -1);
    });
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

  /**
   * What each tile should be showing. Worst problem wins, so a tile is only
   * shown as adrift once it actually spells something: not-a-word (red) beats
   * not-part-of-a-word beats cut-off-from-the-board (orange) beats fine (green).
   */
  const cellStatus = useMemo(() => {
    const status = new Map<CellKey, CellStatus>();
    if (!validation) return status;
    for (const key of validation.disconnectedTiles) status.set(key, 'disconnected');
    for (const run of validation.runs) {
      for (const cell of run.cells) {
        if (!run.valid) status.set(cell, 'invalid');
        else if (status.get(cell) === undefined) status.set(cell, 'valid');
      }
    }
    for (const key of validation.isolatedTiles) status.set(key, 'isolated');
    return status;
  }, [validation]);

  const picks = picksOf(interaction);

  const pickList = useMemo(
    () =>
      picks
        .filter((i) => i === GAP || rack[i] !== undefined)
        .map((i) =>
          i === GAP ? { letter: null, rackIndex: GAP } : { letter: rack[i], rackIndex: i },
        ),
    [picks, rack],
  );

  /** Where the word would go right now — the chosen cell, and its direction. */
  const target = useMemo(
    () =>
      interaction.kind === 'place'
        ? { key: interaction.anchor, dir: interaction.dir }
        : null,
    [interaction],
  );

  /**
   * The direction to use for a cell without asking. Null means the cell can't
   * start a word at all — it's walled in on both sides.
   *
   * The tiles around it get the first say: a letter to the left means a word is
   * already running across into this cell, a letter above means one is running
   * down into it, and either way the player is almost certainly carrying it on.
   * With nothing to go on, fall back to whichever way the last word went.
   */
  const assumeDir = useCallback(
    (key: CellKey): Direction | null => {
      const cell = parseKey(key);
      const startable = startableDirections(board, BOARD_SIZE, cell);
      if (startable.length === 0) return null;

      const implied = impliedDirections(board, cell).filter((dir) => startable.includes(dir));
      // Letters on both sides, so the neighbours don't settle it either.
      const choices = implied.length > 0 ? implied : startable;
      return choices.includes(lastDir) ? lastDir : choices[0];
    },
    [board, lastDir],
  );

  /** Only offer to rotate when the cell genuinely could go either way. */
  const canRotateAnchor =
    interaction.kind === 'place' &&
    startableDirections(board, BOARD_SIZE, parseKey(interaction.anchor)).length > 1;

  const plan = useMemo(() => {
    if (!target || pickList.length === 0) return null;
    return planPlacement(board, BOARD_SIZE, parseKey(target.key), target.dir, pickList);
  }, [target, board, pickList]);

  const preview = useMemo(() => {
    const map = new Map<CellKey, string>();
    if (plan) for (const step of plan.steps) map.set(step.key, step.letter);
    return map;
  }, [plan]);

  /**
   * The square the next letter lands on. With nothing typed it's the cell that
   * was chosen; as letters go in it walks ahead of them, stepping over words
   * already on the board so it always points at a cell that can take a letter.
   */
  const cursorKey = useMemo(
    () =>
      interaction.kind === 'place'
        ? cursorCell(board, BOARD_SIZE, parseKey(interaction.anchor), interaction.dir, pickList)
        : null,
    [interaction, board, pickList],
  );

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

    if (plan) {
      if (!plan.complete) return null; // doesn't fit, or a gap missed its letter
      const next = { ...board };
      for (const step of plan.steps) next[step.key] = step.letter;
      const placed = new Set(plan.steps.map((step) => step.key));
      const runs = extractRuns(next).filter((run) =>
        run.cells.some((cell) => placed.has(cell)),
      );
      if (runs.length === 0) return null; // lands isolated; nothing to judge yet
      const bad = runs.filter(
        (run) => run.word.length < MIN_WORD_LENGTH || !dictionary.has(run.word),
      );
      return {
        ok: bad.length === 0,
        words: (bad.length > 0 ? bad : runs).map((run) => run.word),
        onBoard: true,
      };
    }

    // Nowhere to put it yet, so the typed letters are all there is to go on —
    // and a gap has no letter, so there's nothing to look up until it lands.
    if (pickList.some((p) => p.letter === null)) return null;
    const typed = pickList.map((p) => p.letter).join('');
    if (typed.length < MIN_WORD_LENGTH) return null;
    return { ok: dictionary.has(typed), words: [typed], onBoard: false };
  }, [dictionary, pickList, plan, board]);

  /** Put the board back to nothing chosen: no selected tile, no anchor. */
  const clearFocus = useCallback(() => {
    setSelection(null);
    setHighlightedWord(null);
    setInteraction(IDLE);
  }, []);

  /* --------------------------------- scoring -------------------------------- */

  // Deliberately keyed off the raw board rather than a drag-sensitive "won", so
  // the bonus doesn't blink out of the scoreboard while a tile is mid-drag.
  const boardScore = useMemo(() => scoreBoard(validation, rack.length), [validation, rack.length]);

  // The board's own words are counted live, so only bonuses need banking.
  const runningScore = bankedBonus + boardScore.words + boardScore.bonus;
  const totalScore = complete ? finalScore : runningScore;

  /**
   * Move up a level: keep the board exactly as it stands and add the next batch
   * of tiles to the pile. Available any time, so a level can be skipped.
   *
   * The new letters are grown off the tiles already played, so they're known to
   * have somewhere to go on the board as it is right now.
   */
  const advanceLevel = useCallback(() => {
    // The bonus has to be locked in here: a moment from now the pile won't be
    // empty any more, so the test that earned it can't be re-run.
    if (boardScore.bonusEarned) setBankedBonus((banked) => banked + ALL_TILES_BONUS);
    setConfirmSkip(null);
    // Undo works within a level; it shouldn't reach back across a deal.
    setHistory([]);

    if (level >= LEVEL_COUNT) {
      setFinalScore(runningScore);
      setComplete(true);
      setSplashLevel(level);
      clearFocus();
      return;
    }

    const next = level + 1;
    const dealt = extendPuzzle(board, BOARD_SIZE, COMMON_WORDS, tilesAddedForLevel(next));
    setRack((prev) => [...prev, ...dealt.letters]);
    setLevel(next);
    setSplashLevel(next);
    clearFocus();
  }, [boardScore.bonusEarned, runningScore, level, board, clearFocus]);

  /**
   * Leaving a level by hand. With tiles still in the pile that's giving up on
   * points rather than finishing, so it asks first.
   */
  const requestAdvance = useCallback(() => {
    if (rack.length > 0) {
      const n = rack.length;
      setConfirmSkip(
        `You still have ${n} tile${n === 1 ? '' : 's'} in your pile. Moving on leaves ` +
          `${n === 1 ? 'it' : 'them'} unplayed and gives up the ${ALL_TILES_BONUS}-point bonus.`,
      );
      return;
    }
    advanceLevel();
  }, [rack.length, advanceLevel]);

  /**
   * Finishing a level is the whole goal, so it carries the player onward by
   * itself rather than making them find a button. The short wait lets the bonus
   * land on the scoreboard first.
   */
  useEffect(() => {
    if (complete || !boardScore.bonusEarned) return;
    if (drag !== null || wordDrag !== null) return;
    const timer = window.setTimeout(advanceLevel, 900);
    return () => window.clearTimeout(timer);
  }, [complete, boardScore.bonusEarned, drag, wordDrag, advanceLevel]);

  // The splash announces and then gets out of the way.
  useEffect(() => {
    if (splashLevel === null) return;
    const timer = window.setTimeout(() => setSplashLevel(null), SPLASH_MS);
    return () => window.clearTimeout(timer);
  }, [splashLevel]);

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
        BOARD_SIZE,
        word.cells.length,
        new Set(word.cells),
        word.direction === 'across' ? 'down' : 'across',
        parseKey(word.cells[0]),
      ) !== null,
    [board],
  );

  /** Move a word's tiles so its first letter lands on `start`. */
  const moveWord = useCallback(
    (word: BoardWord, start: CellKey, dir: Direction) => {
      const own = new Set(word.cells);
      const targets = planWordCells(
        board,
        BOARD_SIZE,
        word.cells.length,
        own,
        dir,
        parseKey(start),
      );
      if (!targets) return false;
      const letters = word.cells.map((key) => board[key]);
      remember();
      // The word's letters are all landing somewhere new.
      setSelection(null);
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
    [board, remember],
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
      remember();
      setBoard((prev) => {
        const next = { ...prev };
        for (const key of word.cells) delete next[key];
        return next;
      });
      setRack((prev) => [...prev, ...letters]);
      clearFocus();
    },
    [board, clearFocus, remember],
  );

  const onWordGrab = useCallback(
    (word: BoardWord, e: React.PointerEvent) => {
      e.preventDefault();
      const letters = word.cells.map((key) => board[key]);
      wordGhostPos.current = { x: e.clientX, y: e.clientY };
      setWordDrag({ word, letters, pointerId: e.pointerId });
      clearFocus();
    },
    [board, clearFocus],
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

  /* ---------------------------- tile selection ------------------------------ */

  /**
   * Single-tap a placed tile to pick it out for deletion.
   *
   * Ignored while letters are waiting to be placed — that word owns the board
   * until it's confirmed, and a stray tap shouldn't throw it away.
   */
  const selectTile = useCallback(
    (key: CellKey) => {
      if (picksOf(interaction).length > 0) return;
      const runs = wordsByCell.get(key);
      // Delete walks along the word this tile reads in. A crossing tile belongs
      // to two, and across wins: it matches reading order, and selecting the
      // other direction's next letter is only a click away.
      const dir: Direction = runs?.some((run) => run.direction === 'across')
        ? 'across'
        : 'down';
      setSelection({ key, dir });
      // Anchoring it too means one click on a letter surfaces everything that
      // letter can do: its word's controls, and a direction for carrying a new
      // word on from it. A boxed-in letter can't start one, so it just selects.
      const startDir = assumeDir(key);
      setInteraction(
        startDir === null ? IDLE : { kind: 'place', anchor: key, dir: startDir, picks: [] },
      );
    },
    [interaction, wordsByCell, assumeDir],
  );

  /**
   * Send the selected tile back to the pile and step onto the next letter of
   * its word, so holding Delete eats the rest of the word. Stops at the end.
   */
  const deleteSelected = useCallback(() => {
    if (!selection) return;
    const { key, dir } = selection;
    const letter = board[key];
    if (letter === undefined) {
      setSelection(null);
      return;
    }
    const { row, col } = parseKey(key);
    const nextKey = dir === 'across' ? keyOf(row, col + 1) : keyOf(row + 1, col);

    remember();
    setBoard((prev) => {
      const next = { ...prev };
      delete next[key];
      return next;
    });
    setRack((prev) => [...prev, letter]);
    setSelection(board[nextKey] !== undefined ? { key: nextKey, dir } : null);
  }, [selection, board, remember]);

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

  /**
   * Add a gap to the word being built: a hole that has to land on a letter
   * already on the board, so a whole word can be typed straight through one.
   */
  const addGap = useCallback(() => {
    setInteraction((prev) => withPicks(prev, [...picksOf(prev), GAP]));
  }, []);

  const cancelWord = useCallback(() => {
    setInteraction(IDLE);
  }, []);

  /** Drop the planned tiles onto the board and spend the pile letters they used. */
  const commit = useCallback(
    (anchor: CellKey, dir: Direction) => {
      if (pickList.length === 0) return;
      const result = planPlacement(board, BOARD_SIZE, parseKey(anchor), dir, pickList);
      if (result.steps.length === 0 || !result.complete) return;

      remember();
      setBoard((prev) => {
        const next = { ...prev };
        for (const step of result.steps) next[step.key] = step.letter;
        return next;
      });
      const spent = new Set(result.steps.map((step) => step.rackIndex));
      setRack((prev) => prev.filter((_, i) => !spent.has(i)));
      setLastDir(dir);
      setInteraction(IDLE);
    },
    [board, pickList, remember],
  );

  /** Flip the chosen cell between across and down, and remember the new way. */
  const rotateDirection = useCallback(() => {
    setInteraction((prev) => {
      if (prev.kind !== 'place') return prev;
      const dir: Direction = prev.dir === 'across' ? 'down' : 'across';
      setLastDir(dir);
      return { ...prev, dir };
    });
  }, []);

  const onCellClick = useCallback(
    (key: CellKey) => {
      if (swallowClick.current) return;
      setSelection(null);
      // Staged letters ride along to the new cell — nothing lands until it's
      // confirmed, so moving the word around costs nothing.

      // A single letter reads the same across as down, so there is nothing to
      // decide — clicking the cell is the whole gesture.
      if (pickList.length === 1 && !(key in board)) {
        commit(key, 'across');
        return;
      }

      const dir = assumeDir(key);
      if (dir === null) {
        setInteraction(IDLE);
        return;
      }
      setInteraction((prev) => ({
        kind: 'place',
        anchor: key,
        dir,
        picks: picksOf(prev),
      }));
    },
    [pickList.length, board, commit, assumeDir],
  );

  /* -------------------------------- keyboard -------------------------------- */

  useEffect(() => {
    const onKeyDown = (e: KeyboardEvent) => {
      if (e.metaKey || e.ctrlKey || e.altKey) return;
      const el = e.target as HTMLElement | null;
      const tag = el?.tagName;
      if (tag === 'INPUT' || tag === 'TEXTAREA' || el?.isContentEditable) return;
      // A focused button keeps its own activation keys — except Enter while a
      // word is staged, which belongs to that word. A click leaves the button
      // focused, so otherwise one press of New game would keep owning Enter.
      if (tag === 'BUTTON' && (e.key === ' ' || (e.key === 'Enter' && picks.length === 0))) {
        return;
      }

      // Space leaves a gap in the word for a letter that's already on the board.
      if (e.key === ' ') {
        e.preventDefault();
        addGap();
        return;
      }

      if (/^[a-zA-Z]$/.test(e.key)) {
        e.preventDefault();
        typeLetter(e.key);
        return;
      }

      if (e.key === 'Backspace' || e.key === 'Delete') {
        // A selected tile is the thing being edited, so it goes first.
        if (selection) {
          e.preventDefault();
          deleteSelected();
          return;
        }
        if (e.key === 'Delete' || picks.length === 0) return;
        e.preventDefault();
        setPicks(picks.slice(0, -1));
        return;
      }

      if (e.key === 'Escape') {
        // Selecting a letter also anchors its cell, so one press has to drop
        // both — otherwise the arrows would linger after the ring went away.
        if (selection) {
          e.preventDefault();
          clearFocus();
          return;
        }
        if (interaction.kind === 'idle') return;
        e.preventDefault();
        cancelWord();
        return;
      }

      // Confirm whatever the board is previewing.
      if (e.key === 'Enter') {
        if (!target || picks.length === 0) return;
        e.preventDefault();
        commit(target.key, target.dir);
        return;
      }

      // Arrow keys aim the chosen cell, the keyboard's answer to the rotate
      // button. Only directions that cell can actually start a word in.
      if (interaction.kind === 'place') {
        const dir: Direction | null =
          e.key === 'ArrowRight' ? 'across' : e.key === 'ArrowDown' ? 'down' : null;
        if (dir && startableDirections(board, BOARD_SIZE, parseKey(interaction.anchor)).includes(dir)) {
          e.preventDefault();
          setLastDir(dir);
          setInteraction((prev) => (prev.kind === 'place' ? { ...prev, dir } : prev));
        }
      }
    };

    window.addEventListener('keydown', onKeyDown);
    return () => window.removeEventListener('keydown', onKeyDown);
  }, [
    interaction,
    picks,
    typeLetter,
    setPicks,
    cancelWord,
    commit,
    selection,
    deleteSelected,
    target,
    clearFocus,
    board,
    addGap,
  ]);

  /* -------------------------------- dragging -------------------------------- */

  const startDrag = useCallback(
    (letter: string, source: DragSource, e: React.PointerEvent) => {
      e.preventDefault();
      // The arrows unmount while dragging, so they never get their pointerleave.
      // Drop the hover now, or it would keep aiming the preview (and Enter).
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

      // A tap picks a tile out rather than moving it: in the pile it claims the
      // letter for the current word, on the board it selects it for deletion.
      const tap = Math.abs(x - startX) < TAP_SLOP && Math.abs(y - startY) < TAP_SLOP;
      if (tap && source.type === 'rack') {
        togglePick(source.index);
        return;
      }
      if (tap && source.type === 'board') {
        selectTile(source.key);
        // The click that follows this tap would otherwise re-anchor the cell.
        swallowClick.current = true;
        window.setTimeout(() => {
          swallowClick.current = false;
        }, 0);
        return;
      }

      const target = document.elementFromPoint(x, y);
      const cellEl = target?.closest('[data-cell]') as HTMLElement | null;

      if (cellEl) {
        const key = keyOf(Number(cellEl.dataset.row), Number(cellEl.dataset.col));
        const sameCell = source.type === 'board' && source.key === key;
        if (sameCell || !(key in board)) {
          remember();
          setBoard((prev) => {
            const next = { ...prev };
            if (source.type === 'board') delete next[source.key];
            next[key] = letter;
            return next;
          });
          if (source.type === 'rack') {
            setRack((prev) => prev.filter((_, i) => i !== source.index));
            setInteraction(IDLE);
          } else {
            // The tile moved, so the old cell is no longer what's selected.
            setSelection((prev) => (prev?.key === source.key ? null : prev));
          }
        }
        swallowClick.current = true;
        window.setTimeout(() => {
          swallowClick.current = false;
        }, 0);
      } else if (target?.closest('[data-rack]')) {
        if (source.type === 'board') {
          remember();
          setBoard((prev) => {
            const next = { ...prev };
            delete next[source.key];
            return next;
          });
          setRack((prev) => [...prev, letter]);
        }
      }
    },
    [drag, board, togglePick, selectTile, remember],
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
      remember();
      setBoard((prev) => {
        const next = { ...prev };
        delete next[key];
        return next;
      });
      setRack((prev) => [...prev, letter]);
      setSelection((prev) => (prev?.key === key ? null : prev));
    },
    [board, remember],
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
  }, []);

  // Controls belong to the cell you chose, not the one you happen to be over,
  // and they get out of the way while something is being dragged.
  const showRotate = canRotateAnchor && drag === null && wordDrag === null;

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

  // A tile can be moved or removed out from under the selection; only show the
  // ring while there is still a tile there to delete.
  const selectedKey =
    selection && board[selection.key] !== undefined ? selection.key : null;

  /* --------------------------------- zooming -------------------------------- */

  /**
   * Pinch the board to zoom. Boards run to 33 squares, which is far more than a
   * phone can show at a comfortable tile size, so this scales the tiles rather
   * than the page — the header, pile and word bar stay put and readable.
   *
   * Handled here rather than left to the browser because tiles set
   * `touch-action: none` for dragging, which stops native pinch reaching them.
   */
  const pinch = useRef<{ startGap: number; startZoom: number } | null>(null);

  useEffect(() => {
    const wrap = boardWrapRef.current;
    if (!wrap) return;

    const gap = (touches: TouchList) => {
      const dx = touches[0].clientX - touches[1].clientX;
      const dy = touches[0].clientY - touches[1].clientY;
      return Math.hypot(dx, dy);
    };

    const onTouchStart = (e: TouchEvent) => {
      if (e.touches.length !== 2) return;
      pinch.current = { startGap: gap(e.touches), startZoom: zoom };
    };
    const onTouchMove = (e: TouchEvent) => {
      if (e.touches.length !== 2 || !pinch.current) return;
      e.preventDefault(); // don't let it turn into a page scroll
      const ratio = gap(e.touches) / pinch.current.startGap;
      const next = pinch.current.startZoom * ratio;
      setZoom(Math.min(MAX_ZOOM, Math.max(MIN_ZOOM, next)));
    };
    const onTouchEnd = (e: TouchEvent) => {
      if (e.touches.length < 2) pinch.current = null;
    };

    wrap.addEventListener('touchstart', onTouchStart, { passive: true });
    wrap.addEventListener('touchmove', onTouchMove, { passive: false });
    wrap.addEventListener('touchend', onTouchEnd);
    wrap.addEventListener('touchcancel', onTouchEnd);
    return () => {
      wrap.removeEventListener('touchstart', onTouchStart);
      wrap.removeEventListener('touchmove', onTouchMove);
      wrap.removeEventListener('touchend', onTouchEnd);
      wrap.removeEventListener('touchcancel', onTouchEnd);
    };
  }, [zoom]);

  return (
    <div className="app">
      <header className="header">
        <Scoreboard
          score={totalScore}
          level={level}
          bonusEarned={boardScore.bonusEarned && !complete}
          complete={complete}
        />
        <div className="header-actions">
          {complete ? (
            <button
              className="btn btn-primary"
              onClick={(e) => {
                e.currentTarget.blur();
                newGame();
              }}
            >
              Play again
            </button>
          ) : (
            <button
              className="btn btn-primary"
              onClick={(e) => {
                e.currentTarget.blur();
                requestAdvance();
              }}
            >
              {level >= LEVEL_COUNT ? (
                'Finish'
              ) : (
                <>
                  Next<span className="btn-long"> level</span> &rarr;
                </>
              )}
            </button>
          )}
          <Menu onNewGame={newGame} />
        </div>
      </header>

      {/* The zoom rides on a CSS variable so only the tiles resize. */}
      <div
        className="board-wrap"
        ref={boardWrapRef}
        style={{ '--zoom': zoom } as React.CSSProperties}
      >
        <Grid
          size={BOARD_SIZE}
          board={board}
          cellStatus={cellStatus}
          hiddenKeys={hiddenKeys}
          preview={preview}
          cursorKey={cursorKey}
          cursorDir={interaction.kind === 'place' ? interaction.dir : null}
          showRotate={showRotate}
          wordsByCell={wordsByCell}
          // The controls belong to the selected letter, and get out of the way
          // once something is being dragged.
          openWordCell={drag || wordDrag ? null : selectedKey}
          highlighted={highlighted}
          selectedKey={selectedKey}
          canRotate={canRotate}
          onTilePointerDown={onBoardTilePointerDown}
          onCellClick={onCellClick}
          onRotateDirection={rotateDirection}
          onWordHighlight={setHighlightedWord}
          onWordGrab={onWordGrab}
          onWordRotate={rotateWord}
          onWordRemove={removeWord}
        />
      </div>

      {/* Nothing is ever a valid word without the dictionary, so the one thing
          the board can't explain on its own still needs saying. */}
      {dictionaryError && (
        <div className="dictionary-error">
          Couldn&rsquo;t load the dictionary — refresh the page to try again.
        </div>
      )}

      <WordBar
        letters={pickList.map((p) => p.letter)}
        mode={interaction.kind}
        overflowed={plan !== null && !plan.complete}
        verdict={verdict}
        onRemove={(position) => setPicks(picks.filter((_, i) => i !== position))}
        onClear={cancelWord}
        onCancel={cancelWord}
        onConfirm={() => {
          if (target) commit(target.key, target.dir);
        }}
      />

      <div className="pile">
        <PileTools
          onUndo={undo}
          canUndo={history.length > 0}
          onShuffle={shufflePile}
          onAddGap={addGap}
        />
        <Rack
          letters={rack}
          hiddenIndex={drag?.source.type === 'rack' ? drag.source.index : null}
          picks={picks}
          onTilePointerDown={(index, letter, e) => startDrag(letter, { type: 'rack', index }, e)}
        />
      </div>

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

      <LevelSplash
        level={splashLevel}
        complete={complete}
        finalScore={totalScore}
        onDismiss={() => setSplashLevel(null)}
      />

      <ConfirmDialog
        message={confirmSkip}
        confirmLabel={level >= LEVEL_COUNT ? 'Finish anyway' : 'Move on anyway'}
        onConfirm={advanceLevel}
        onCancel={() => setConfirmSkip(null)}
      />
    </div>
  );
}
