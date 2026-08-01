import { useCallback, useEffect, useLayoutEffect, useMemo, useRef, useState } from 'react';
import { MIN_WORD_LENGTH, extractRuns, validateBoard } from './game/board';
import { COMMON_WORDS } from './game/commonWords';
import { loadDictionary } from './game/dictionary';
import { extendPuzzle, generatePuzzle } from './game/generator';
import {
  ALL_TILES_BONUS,
  LEVEL_COUNT,
  boardBounds,
  scoreBoard,
  tilesAddedForLevel,
  wordScore,
} from './game/levels';
import {
  ENDLESS_CLEAR_TILES,
  ENDLESS_CONNECT_BONUS,
  ENDLESS_DRIP_SECONDS,
  ENDLESS_DRIP_TILES,
  ENDLESS_INITIAL_SECONDS,
  ENDLESS_LOOSE_LIMIT,
  timedLevelSeconds,
  type GameMode,
} from './game/modes';
import {
  GAP,
  anchorForGapTarget,
  cursorCell,
  findAvailable,
  impliedDirections,
  planPlacement,
  planWordCells,
  startableDirections,
} from './game/placement';
import { loadStats, recordGame, type Stats } from './game/stats';
import type { CellKey, Direction, TileMap } from './game/types';
import { keyOf, parseKey } from './game/types';
import { ConfirmDialog } from './components/ConfirmDialog';
import { GameSummary, type ScoredWord } from './components/GameSummary';
import { Grid } from './components/Grid';
import { HomeScreen } from './components/HomeScreen';
import { HowToModal } from './components/HowToModal';
import { LevelSplash } from './components/LevelSplash';
import { Menu } from './components/Menu';
import { PileTools } from './components/PileTools';
import { Rack } from './components/Rack';
import { Scoreboard, type ScorePop } from './components/Scoreboard';
import { StatsPage } from './components/StatsPage';
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

/**
 * Auto-fit: whenever tiles change, the zoom is re-picked so every placed tile
 * fits on screen — in for a small crossword, out as it spreads. The cap stops
 * one lonely word turning into billboard tiles; the pad keeps the outermost
 * tiles off the very edge; the epsilon ignores changes too small to matter.
 */
const AUTO_ZOOM_MAX = 1.25;
const FIT_PAD_CELLS = 1;
const ZOOM_EPSILON = 0.03;

/** The rectangle of cells that actually hold tiles. */
interface TileBox {
  minRow: number;
  maxRow: number;
  minCol: number;
  maxCol: number;
}

/**
 * Where the placed tiles sit in the board viewport's scroll space, measured
 * from the live DOM so it's true at whatever zoom is currently rendered.
 * Null before the grid has cells to measure.
 */
function measureTiles(
  wrap: HTMLElement,
  gridOrigin: { minRow: number; minCol: number },
  box: TileBox,
): { step: number; left: number; top: number; width: number; height: number } | null {
  const cell = wrap.querySelector('[data-cell]') as HTMLElement | null;
  const boardEl = wrap.querySelector('.board') as HTMLElement | null;
  if (!cell || !boardEl) return null;
  const step = cell.getBoundingClientRect().width + 1; // +1 for the grid's hairline gap
  const wrapRect = wrap.getBoundingClientRect();
  const boardRect = boardEl.getBoundingClientRect();
  // Client coordinates shifted into scroll coordinates; +1 skips the border.
  const originX = boardRect.left - wrapRect.left + wrap.scrollLeft + 1;
  const originY = boardRect.top - wrapRect.top + wrap.scrollTop + 1;
  return {
    step,
    left: originX + (box.minCol - gridOrigin.minCol) * step,
    top: originY + (box.minRow - gridOrigin.minRow) * step,
    width: (box.maxCol - box.minCol + 1) * step - 1,
    height: (box.maxRow - box.minRow + 1) * step - 1,
  };
}

/** Once set, the tutorial stays put — it only auto-opens on the first game. */
const HOWTO_SEEN_KEY = 'nana.howto.v1';

/** How the game came to an end — the summary's headline depends on it. */
type EndReason = 'won' | 'timeout' | 'buried';

/**
 * The header clock. It's either counting toward a wall-clock deadline or
 * holding a frozen remainder — frozen whenever something worth reading (the
 * tutorial, a level splash) is covering the board, so the modes with a clock
 * never charge for reading.
 */
type Countdown = { kind: 'running'; endsAt: number } | { kind: 'paused'; remainingMs: number };

function runningCountdown(seconds: number): Countdown {
  return { kind: 'running', endsAt: Date.now() + seconds * 1000 };
}

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
  /** Which screen is up: the mode-picking splash, or a game. */
  const [screen, setScreen] = useState<'home' | 'game'>('home');
  const [mode, setMode] = useState<GameMode>('puzzle');
  /** Whether the how-to tutorial is up (auto on first game, or from a menu). */
  const [showHowTo, setShowHowTo] = useState(false);
  /** The clock, in modes that have one. Null in Solo Puzzle and once a game ends. */
  const [countdown, setCountdown] = useState<Countdown | null>(null);
  /** Endless: 'initial' is the opening two minutes; 'drip' is ever after,
   * when batches arrive on the clock and the health bar is live. */
  const [endlessPhase, setEndlessPhase] = useState<'initial' | 'drip'>('initial');
  /** How the finished game ended, for the summary's headline. */
  const [endReason, setEndReason] = useState<EndReason | null>(null);
  /** The banner riding over the board ("+3 tiles!"), keyed so repeats replay. */
  const [toast, setToast] = useState<{ text: string; serial: number } | null>(null);
  /** How many just-dealt tiles at the pile's end should play their landing
   * animation, keyed like the toast. */
  const [tileDrop, setTileDrop] = useState<{ count: number; serial: number } | null>(null);
  const dropSerial = useRef(0);

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
  /** The finished board's words and points, frozen alongside the score. */
  const [finalWords, setFinalWords] = useState<ScoredWord[] | null>(null);
  /** Whether the full-screen finish summary is up. */
  const [showSummary, setShowSummary] = useState(false);
  /** The stats being looked at, or null while the stats page is closed. */
  const [statsView, setStatsView] = useState<Stats | null>(null);
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
  /**
   * The cell under the pointer, but only tracked while letters are waiting to be
   * placed — the rest of the time it stays null, so simply moving across a
   * thousand-cell board costs nothing.
   */
  const [hoverCell, setHoverCell] = useState<CellKey | null>(null);

  const boardWrapRef = useRef<HTMLDivElement>(null);
  const ghostRef = useRef<HTMLDivElement>(null);
  const ghostPos = useRef({ x: 0, y: 0 });
  const wordGhostRef = useRef<HTMLDivElement>(null);
  const wordGhostPos = useRef({ x: 0, y: 0 });
  /** Swallow the click that follows a drop, so it doesn't also select a cell. */
  const swallowClick = useRef(false);

  /**
   * Arm the swallow until the gesture's trailing click has actually come and
   * gone. The click arrives in its own task — on touch screens well after any
   * zero-delay timer — so a timer alone sometimes lowered the flag too early
   * and let the click re-anchor a cell. The timer stays only as a backstop for
   * gestures whose click never arrives at all.
   */
  const swallowNextClick = useCallback(() => {
    swallowClick.current = true;
    let timer: number | undefined;
    const clear = () => {
      swallowClick.current = false;
      window.removeEventListener('click', clear);
      window.clearTimeout(timer);
    };
    // Bubble phase on window, so it runs after the board has seen the click.
    window.addEventListener('click', clear);
    timer = window.setTimeout(clear, 500);
  }, []);

  /** A game already recorded to stats must not record again — see finishGame. */
  const finished = useRef(false);

  const newGame = useCallback((nextMode: GameMode) => {
    setMode(nextMode);
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
    setFinalScore(0);
    setFinalWords(null);
    setShowSummary(false);
    setHistory([]);
    setConfirmSkip(null);
    setSplashLevel(1);
    setEndReason(null);
    setEndlessPhase('initial');
    setToast(null);
    setTileDrop(null);
    setZoom(1);
    finished.current = false;
    setCountdown(
      nextMode === 'timed'
        ? runningCountdown(timedLevelSeconds(1))
        : nextMode === 'endless'
          ? runningCountdown(ENDLESS_INITIAL_SECONDS)
          : null,
    );
    setGameId((id) => id + 1);
  }, []);

  /** Pick a mode on the splash screen and dive in. The tutorial fronts the
   * very first game; after that a localStorage flag keeps it away. */
  const startGame = useCallback(
    (nextMode: GameMode) => {
      newGame(nextMode);
      setScreen('game');
      let seen = false;
      try {
        seen = window.localStorage.getItem(HOWTO_SEEN_KEY) !== null;
      } catch {
        // Storage blocked — show it this time; there's nothing to remember by.
      }
      if (!seen) setShowHowTo(true);
    },
    [newGame],
  );

  const dismissHowTo = useCallback(() => {
    setShowHowTo(false);
    try {
      window.localStorage.setItem(HOWTO_SEEN_KEY, String(Date.now()));
    } catch {
      // Storage full or blocked — it'll just show again next time.
    }
  }, []);

  const returnHome = useCallback(() => {
    setScreen('home');
    setCountdown(null);
    setShowSummary(false);
    setConfirmSkip(null);
    setSplashLevel(null);
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

  /** The cells in play. Grows whenever tiles come near an edge, so the board
   * can never actually be run out of. */
  const bounds = useMemo(() => boardBounds(board), [board]);

  // Growing at the top or left prepends rows and columns, which would shove
  // the tiles the player is looking at down and across the screen. Nudge the
  // scroll by the same amount so the board doesn't appear to move at all.
  const boardOrigin = useRef<{ row: number; col: number } | null>(null);
  useLayoutEffect(() => {
    const wrap = boardWrapRef.current;
    const prev = boardOrigin.current;
    boardOrigin.current = { row: bounds.minRow, col: bounds.minCol };
    if (!wrap || !prev) return;
    const cell = wrap.querySelector('[data-cell]') as HTMLElement | null;
    if (!cell) return;
    const step = cell.offsetWidth + 1; // +1 for the grid's hairline gap
    if (prev.row !== bounds.minRow) wrap.scrollTop += (prev.row - bounds.minRow) * step;
    if (prev.col !== bounds.minCol) wrap.scrollLeft += (prev.col - bounds.minCol) * step;
  }, [bounds.minRow, bounds.minCol]);

  /* -------------------------------- auto-fit -------------------------------- */

  /** The rectangle the placed tiles span, or null on an empty board. */
  const tileBox = useMemo((): TileBox | null => {
    const keys = Object.keys(board);
    if (keys.length === 0) return null;
    let minRow = Infinity;
    let maxRow = -Infinity;
    let minCol = Infinity;
    let maxCol = -Infinity;
    for (const key of keys) {
      const { row, col } = parseKey(key);
      if (row < minRow) minRow = row;
      if (row > maxRow) maxRow = row;
      if (col < minCol) minCol = col;
      if (col > maxCol) maxCol = col;
    }
    return { minRow, maxRow, minCol, maxCol };
  }, [board]);

  /** Bumped when the board viewport changes size (window resized, pile grew a
   * row), so the fit gets rechecked against the room actually left. */
  const [fitTick, setFitTick] = useState(0);
  useEffect(() => {
    const wrap = boardWrapRef.current;
    if (!wrap) return;
    const observer = new ResizeObserver(() => setFitTick((tick) => tick + 1));
    observer.observe(wrap);
    return () => observer.disconnect();
  }, [screen]);

  /** A centering job waiting for its zoom to reach the DOM first. */
  const pendingCenter = useRef<{ zoom: number } | null>(null);

  // Keep the whole crossword on screen. Whenever the tiles change, re-pick the
  // zoom that shows all of them — larger while the crossword is small, backing
  // out as it spreads — and if the zoom moved, or a tile has strayed out of
  // view, glide the viewport back to centre on the tiles. Reads zoom fresh on
  // each run but deliberately doesn't depend on it, so a manual pinch is left
  // alone until the next placement.
  useLayoutEffect(() => {
    const wrap = boardWrapRef.current;
    if (!wrap || !tileBox) return;
    const measured = measureTiles(wrap, bounds, tileBox);
    if (!measured) return;

    const cellBase = (measured.step - 1) / zoom;
    const cols = tileBox.maxCol - tileBox.minCol + 1 + FIT_PAD_CELLS * 2;
    const rows = tileBox.maxRow - tileBox.minRow + 1 + FIT_PAD_CELLS * 2;
    const fitAcross = (wrap.clientWidth / cols - 1) / cellBase;
    const fitDown = (wrap.clientHeight / rows - 1) / cellBase;
    const target = Math.min(Math.max(Math.min(fitAcross, fitDown), MIN_ZOOM), AUTO_ZOOM_MAX);
    if (!Number.isFinite(target)) return;

    const zoomChanged = Math.abs(target - zoom) > ZOOM_EPSILON;
    const slack = 2; // px of rounding forgiveness before "off screen" counts
    const inView =
      measured.left >= wrap.scrollLeft - slack &&
      measured.left + measured.width <= wrap.scrollLeft + wrap.clientWidth + slack &&
      measured.top >= wrap.scrollTop - slack &&
      measured.top + measured.height <= wrap.scrollTop + wrap.clientHeight + slack;
    if (!zoomChanged && inView) return;

    pendingCenter.current = { zoom: zoomChanged ? target : zoom };
    if (zoomChanged) setZoom(target);
    // eslint-disable-next-line react-hooks/exhaustive-deps -- zoom and bounds
    // are read fresh each run; depending on them would refit on every pinch.
  }, [tileBox, fitTick]);

  // The second half of the fit: once the DOM is laid out at the target zoom,
  // slide the viewport so the tiles sit in the middle of it.
  useLayoutEffect(() => {
    const wrap = boardWrapRef.current;
    const pending = pendingCenter.current;
    if (!wrap || !pending || !tileBox) return;
    if (pending.zoom !== zoom) return; // the zoom render hasn't landed yet
    pendingCenter.current = null;
    const measured = measureTiles(wrap, bounds, tileBox);
    if (!measured) return;
    wrap.scrollTo({
      left: measured.left + measured.width / 2 - wrap.clientWidth / 2,
      top: measured.top + measured.height / 2 - wrap.clientHeight / 2,
      behavior: 'smooth',
    });
    // eslint-disable-next-line react-hooks/exhaustive-deps -- bounds is read
    // fresh; it only ever changes alongside tileBox.
  }, [zoom, tileBox, fitTick]);

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
      const startable = startableDirections(board, bounds, cell);
      if (startable.length === 0) return null;

      const implied = impliedDirections(board, cell).filter((dir) => startable.includes(dir));
      // Letters on both sides, so the neighbours don't settle it either.
      const choices = implied.length > 0 ? implied : startable;
      return choices.includes(lastDir) ? lastDir : choices[0];
    },
    [board, bounds, lastDir],
  );

  /**
   * Where the word would go right now.
   *
   * A cell that's been chosen owns the preview and keeps it — otherwise it would
   * jump about as the pointer crossed the board on its way to a button. Until
   * one is chosen, though, letters waiting in the bar follow the pointer, so it's
   * plain where they'd land before committing to anywhere.
   */
  const target = useMemo(() => {
    if (interaction.kind === 'place') {
      return { key: interaction.anchor, dir: interaction.dir };
    }
    if (hoverCell !== null && picksOf(interaction).length > 0) {
      const dir = assumeDir(hoverCell);
      if (dir !== null) return { key: hoverCell, dir };
    }
    return null;
  }, [interaction, hoverCell, assumeDir]);

  /**
   * Follow the pointer across the board, but only while there's a word waiting
   * for a home and nothing is being dragged. Otherwise hold at null, which keeps
   * the board from re-rendering on every cell the pointer crosses.
   */
  const onCellHover = useCallback(
    (key: CellKey | null) => {
      const wanted = picks.length > 0 && drag === null && wordDrag === null ? key : null;
      setHoverCell((prev) => (prev === wanted ? prev : wanted));
    },
    [picks.length, drag, wordDrag],
  );

  /** Only offer to rotate when the cell genuinely could go either way. */
  const canRotateAnchor =
    interaction.kind === 'place' &&
    startableDirections(board, bounds, parseKey(interaction.anchor)).length > 1;

  const plan = useMemo(() => {
    if (!target || pickList.length === 0) return null;
    return planPlacement(board, bounds, parseKey(target.key), target.dir, pickList);
  }, [target, board, bounds, pickList]);

  const preview = useMemo(() => {
    const map = new Map<CellKey, string>();
    if (plan) for (const step of plan.steps) map.set(step.key, step.letter);
    return map;
  }, [plan]);

  /** Squares a gap is holding open but has no letter under it yet. */
  const previewGaps = useMemo(
    () => new Set<CellKey>(plan?.unfilledGaps ?? []),
    [plan],
  );

  /**
   * The square the next letter lands on. With nothing typed it's the cell that
   * was chosen; as letters go in it walks ahead of them, stepping over words
   * already on the board so it always points at a cell that can take a letter.
   */
  const cursorKey = useMemo(
    () =>
      interaction.kind === 'place'
        ? cursorCell(board, bounds, parseKey(interaction.anchor), interaction.dir, pickList)
        : null,
    [interaction, board, bounds, pickList],
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

  /** What "every tile placed and connected" pays right now — Endless clears
   * are worth less than a level's all-tiles bonus, but come again and again. */
  const allTilesBonus = mode === 'endless' ? ENDLESS_CONNECT_BONUS : ALL_TILES_BONUS;

  // The board's own words are counted live, so only bonuses need banking.
  const runningScore =
    bankedBonus + boardScore.words + (boardScore.bonusEarned ? allTilesBonus : 0);
  const totalScore = complete ? finalScore : runningScore;

  /**
   * Every change to the score announces itself: a little "+12" (or "−12")
   * floats off the scoreboard whenever a move lands, loses or wins points —
   * placing a word, taking letters back, earning a bonus. Watched from the
   * score itself rather than raised by each action, so every way of changing
   * the board reports the same way. Pops clear themselves as their animation
   * ends.
   */
  const [scorePops, setScorePops] = useState<ScorePop[]>([]);
  const popSerial = useRef(0);
  const scoreTrail = useRef({ gameId: 0, score: 0 });

  useEffect(() => {
    const trail = scoreTrail.current;
    const from = trail.gameId === gameId ? trail.score : null;
    scoreTrail.current = { gameId, score: totalScore };
    // A new deal resets the score; that's not a move worth announcing.
    if (from === null || from === totalScore) return;
    const pop = { id: ++popSerial.current, delta: totalScore - from };
    setScorePops((pops) => [...pops, pop]);
  }, [gameId, totalScore]);

  const endScorePop = useCallback((id: number) => {
    setScorePops((pops) => pops.filter((pop) => pop.id !== id));
  }, []);

  /**
   * The one way any game ends — win, clock, or tile overload. Freezes the
   * board's words and score for the summary and records the game once; the
   * ref guard keeps a double call (two effects racing) from double-counting.
   */
  const finishGame = useCallback(
    (reason: EndReason) => {
      if (finished.current) return;
      finished.current = true;
      // Freeze what the finished board actually said, for the summary screen.
      const words = (validation?.runs ?? [])
        .filter((run) => run.valid)
        .map((run) => ({ word: run.word, points: wordScore(run.word) }));
      setFinalScore(runningScore);
      setFinalWords(words);
      setComplete(true);
      setShowSummary(true);
      setEndReason(reason);
      setCountdown(null);
      setConfirmSkip(null);
      recordGame(runningScore, words.length);
      clearFocus();
    },
    [validation, runningScore, clearFocus],
  );

  /**
   * Move up a level: keep the board exactly as it stands and add the next batch
   * of tiles to the pile. Available any time, so a level can be skipped.
   * (Solo Puzzle and Solo Timed only — Endless has no levels to move up.)
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
      finishGame('won');
      return;
    }

    const next = level + 1;
    const dealt = extendPuzzle(board, bounds, COMMON_WORDS, tilesAddedForLevel(next));
    setRack((prev) => [...prev, ...dealt.letters]);
    setLevel(next);
    setSplashLevel(next);
    // Each timed level gets its own, shorter clock. It starts paused behind
    // the splash; the pause effect below releases it when the splash goes.
    if (mode === 'timed') setCountdown(runningCountdown(timedLevelSeconds(next)));
    clearFocus();
  }, [boardScore.bonusEarned, level, board, bounds, mode, finishGame, clearFocus]);

  /**
   * Leaving a level by hand. Doing that while the bonus isn't earned is giving
   * up on points rather than finishing, so it asks first — whether the shortfall
   * is tiles still in the pile or a board that doesn't qualify yet.
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
    if (!boardScore.bonusEarned) {
      // Every tile is down but the board doesn't earn the bonus. Words that
      // aren't right are the more urgent problem to name; only a board whose
      // words all check out gets the connectedness explanation.
      const wordsAllGood =
        validation !== null &&
        validation.invalidRuns.length === 0 &&
        validation.isolatedTiles.length === 0;
      setConfirmSkip(
        wordsAllGood
          ? `Your words aren't all joined into one crossword. Moving on gives up the ` +
              `${ALL_TILES_BONUS}-point bonus.`
          : `Your board isn't a valid crossword yet. Moving on gives up the ` +
              `${ALL_TILES_BONUS}-point bonus.`,
      );
      return;
    }
    advanceLevel();
  }, [rack.length, boardScore.bonusEarned, validation, advanceLevel]);

  /**
   * Finishing a level is the whole goal, so it carries the player onward by
   * itself rather than making them find a button. The short wait lets the bonus
   * land on the scoreboard first. (Endless clears are handled below instead.)
   */
  useEffect(() => {
    if (mode === 'endless' || complete || !boardScore.bonusEarned) return;
    if (drag !== null || wordDrag !== null) return;
    const timer = window.setTimeout(advanceLevel, 900);
    return () => window.clearTimeout(timer);
  }, [mode, complete, boardScore.bonusEarned, drag, wordDrag, advanceLevel]);

  // The splash announces and then gets out of the way.
  useEffect(() => {
    if (splashLevel === null) return;
    const timer = window.setTimeout(() => setSplashLevel(null), SPLASH_MS);
    return () => window.clearTimeout(timer);
  }, [splashLevel]);

  /* ------------------------------- the clock -------------------------------- */

  // Anything worth reading over the board stops the clock while it's up.
  const clockPaused = showHowTo || splashLevel !== null;

  // Flip the clock between running and paused as overlays come and go. Written
  // as normalization (rather than one effect per transition) so a countdown
  // started behind an overlay also gets released the moment the board is clear.
  useEffect(() => {
    setCountdown((prev) => {
      if (!prev) return prev;
      if (clockPaused && prev.kind === 'running') {
        return { kind: 'paused', remainingMs: Math.max(0, prev.endsAt - Date.now()) };
      }
      if (!clockPaused && prev.kind === 'paused') {
        return { kind: 'running', endsAt: Date.now() + prev.remainingMs };
      }
      return prev;
    });
  }, [clockPaused, countdown]);

  // The clock's own heartbeat: only ticks while genuinely counting down.
  const [clockNow, setClockNow] = useState(() => Date.now());
  useEffect(() => {
    if (countdown?.kind !== 'running' || complete) return;
    setClockNow(Date.now());
    const timer = window.setInterval(() => setClockNow(Date.now()), 250);
    return () => window.clearInterval(timer);
  }, [countdown, complete]);

  const remainingMs =
    countdown === null
      ? null
      : countdown.kind === 'paused'
        ? countdown.remainingMs
        : Math.max(0, countdown.endsAt - clockNow);

  /**
   * Deal Endless bonus tiles into the pile — grown off the board where
   * possible, so they always have somewhere to go — with their landing
   * animation and a banner saying what just happened.
   */
  const dealBonusTiles = useCallback(
    (count: number, message: string) => {
      const dealt = extendPuzzle(board, bounds, COMMON_WORDS, count);
      setRack((prev) => [...prev, ...dealt.letters]);
      const serial = ++dropSerial.current;
      setTileDrop({ count: dealt.letters.length, serial });
      setToast({ text: message, serial });
    },
    [board, bounds],
  );

  /**
   * The clock ran out. In Solo Timed that's the whole game; in Endless it's
   * just the next batch of tiles arriving — and the first expiry is the end of
   * the opening phase, which also switches the health bar on. The ref keeps
   * one expiry from being handled twice while the new countdown state lands.
   */
  const expiryHandled = useRef<number | null>(null);
  useEffect(() => {
    if (complete || countdown?.kind !== 'running') return;
    if (countdown.endsAt - clockNow > 0) return;
    if (expiryHandled.current === countdown.endsAt) return;
    expiryHandled.current = countdown.endsAt;

    if (mode === 'timed') {
      finishGame('timeout');
      return;
    }
    if (mode === 'endless') {
      dealBonusTiles(ENDLESS_DRIP_TILES, `+${ENDLESS_DRIP_TILES} tiles!`);
      setEndlessPhase('drip');
      setCountdown(runningCountdown(ENDLESS_DRIP_SECONDS));
    }
  }, [clockNow, countdown, complete, mode, finishGame, dealBonusTiles]);

  /* -------------------------------- endless --------------------------------- */

  /**
   * Clearing the pile in Endless: the connect bonus banks (the live bonus
   * swaps for it, so the score holds steady) and a fresh batch arrives — the
   * same size as a timed drop. Same short wait as a level-up, so the bonus
   * lands on the scoreboard before the pile refills.
   */
  useEffect(() => {
    if (mode !== 'endless' || complete || !boardScore.bonusEarned) return;
    if (drag !== null || wordDrag !== null) return;
    const timer = window.setTimeout(() => {
      setBankedBonus((banked) => banked + ENDLESS_CONNECT_BONUS);
      dealBonusTiles(
        ENDLESS_CLEAR_TILES,
        `Board clear! +${ENDLESS_CONNECT_BONUS} points · +${ENDLESS_CLEAR_TILES} tiles`,
      );
    }, 900);
    return () => window.clearTimeout(timer);
  }, [mode, complete, boardScore.bonusEarned, drag, wordDrag, dealBonusTiles]);

  /**
   * The health bar's measure: tiles not yet doing their job — still in the
   * pile, or on the board but not part of a valid, connected word. Hit the
   * limit once the opening phase is over and the game is lost.
   */
  const looseTiles = useMemo(() => {
    let onBoard = 0;
    for (const status of cellStatus.values()) {
      if (status !== 'valid') onBoard++;
    }
    return rack.length + onBoard;
  }, [cellStatus, rack.length]);

  useEffect(() => {
    if (mode !== 'endless' || complete || endlessPhase !== 'drip') return;
    if (looseTiles >= ENDLESS_LOOSE_LIMIT) finishGame('buried');
  }, [mode, complete, endlessPhase, looseTiles, finishGame]);

  // Banners and landing animations clean themselves up.
  useEffect(() => {
    if (toast === null) return;
    const timer = window.setTimeout(() => setToast(null), 2500);
    return () => window.clearTimeout(timer);
  }, [toast]);

  useEffect(() => {
    if (tileDrop === null) return;
    const timer = window.setTimeout(() => setTileDrop(null), 1600);
    return () => window.clearTimeout(timer);
  }, [tileDrop]);

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
        bounds,
        word.cells.length,
        new Set(word.cells),
        word.direction === 'across' ? 'down' : 'across',
        parseKey(word.cells[0]),
      ) !== null,
    [board, bounds],
  );

  /** Move a word's tiles so its first letter lands on `start`. */
  const moveWord = useCallback(
    (word: BoardWord, start: CellKey, dir: Direction) => {
      const own = new Set(word.cells);
      const targets = planWordCells(
        board,
        bounds,
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
    [board, bounds, remember],
  );

  /**
   * Turn a word about its first letter, which stays put while the rest swing
   * round. The word stays selected afterwards — it's still the one being worked
   * on, and turning it is usually the first of several tries.
   */
  const rotateWord = useCallback(
    (word: BoardWord) => {
      const pivot = word.cells[0];
      const dir: Direction = word.direction === 'across' ? 'down' : 'across';
      // moveWord drops the selection, since normally a moved word leaves the
      // selected cell behind. Here the pivot doesn't move, so take it back.
      if (!moveWord(word, pivot, dir)) return;
      setSelection({ key: pivot, dir });
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
        swallowNextClick();
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
  }, [wordDrag, moveWord, swallowNextClick]);

  /* ---------------------------- tile selection ------------------------------ */

  /**
   * Send the selected tile back to the pile and step onto its neighbour, so
   * holding the key eats the rest of the word. Stops when it runs out of word.
   *
   * `step` is which way along the word to carry on. Backspace goes 'back' — the
   * letter before this one, as it does in any text field — and Delete goes
   * 'forward', so a word can be unpicked from either end.
   */
  const deleteSelected = useCallback(
    (step: 'back' | 'forward') => {
      if (!selection) return;
      const { key, dir } = selection;
      const letter = board[key];
      if (letter === undefined) {
        setSelection(null);
        return;
      }
      const { row, col } = parseKey(key);
      const delta = step === 'back' ? -1 : 1;
      const nextKey =
        dir === 'across' ? keyOf(row, col + delta) : keyOf(row + delta, col);

      remember();
      setBoard((prev) => {
        const next = { ...prev };
        delete next[key];
        return next;
      });
      setRack((prev) => [...prev, letter]);
      setSelection(board[nextKey] !== undefined ? { key: nextKey, dir } : null);
    },
    [selection, board, remember],
  );

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


  /** Drop the planned tiles onto the board and spend the pile letters they used. */
  const commit = useCallback(
    (anchor: CellKey, dir: Direction) => {
      if (pickList.length === 0) return;
      const result = planPlacement(board, bounds, parseKey(anchor), dir, pickList);
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
      // Confirming ends the whole gesture, however the word was submitted:
      // no anchored cell, no selection ring, no word controls left behind.
      clearFocus();
    },
    [board, bounds, pickList, remember, clearFocus],
  );

  /**
   * Place the staged word so its first gap sits on the letter at `key` — the
   * click-a-letter way of aiming a gap. With more than one gap it's the first
   * that lands on the click; the rest still have to find letters of their own.
   * Returns false when the picks have no gap or the word fits neither way.
   */
  const commitThroughLetter = useCallback(
    (key: CellKey): boolean => {
      if (board[key] === undefined) return false;
      if (!pickList.some((pick) => pick.letter === null)) return false;

      const cell = parseKey(key);
      // Crossing the word the clicked letter already reads in is the likelier
      // intent, so that direction goes first. A letter in both words — or in
      // none — settles nothing, so fall back to the way the last word went.
      const runDirs = new Set((wordsByCell.get(key) ?? []).map((run) => run.direction));
      const ordered: Direction[] =
        runDirs.has('across') === runDirs.has('down')
          ? lastDir === 'across'
            ? ['across', 'down']
            : ['down', 'across']
          : runDirs.has('across')
            ? ['down', 'across']
            : ['across', 'down'];

      const fits = ordered.flatMap((dir) => {
        const anchor = anchorForGapTarget(board, bounds, cell, dir, pickList);
        if (!anchor) return [];
        const plan = planPlacement(board, bounds, anchor, dir, pickList);
        return plan.complete && plan.steps.length > 0 ? [{ anchor, dir, plan }] : [];
      });
      if (fits.length === 0) return false;

      // When the word fits both ways, prefer the way that spells real words.
      const best =
        fits.find(({ plan }) => {
          if (!dictionary) return false;
          const next = { ...board };
          for (const step of plan.steps) next[step.key] = step.letter;
          const placed = new Set(plan.steps.map((step) => step.key));
          placed.add(key);
          return extractRuns(next)
            .filter((run) => run.cells.some((c) => placed.has(c)))
            .every((run) => run.word.length >= MIN_WORD_LENGTH && dictionary.has(run.word));
        }) ?? fits[0];

      commit(keyOf(best.anchor.row, best.anchor.col), best.dir);
      return true;
    },
    [board, pickList, wordsByCell, lastDir, bounds, dictionary, commit],
  );

  /**
   * Single-tap a placed tile to pick it out for deletion.
   *
   * While letters are waiting to be placed the tap doesn't select: a word
   * staged with a gap lands here instead, the clicked letter filling its first
   * gap — and a word without one stays put, so a stray tap can't throw it away.
   */
  const selectTile = useCallback(
    (key: CellKey) => {
      if (picksOf(interaction).length > 0) {
        commitThroughLetter(key);
        return;
      }
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
    [interaction, commitThroughLetter, wordsByCell, assumeDir],
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

  /**
   * The Backspace key as a button, for players without one under their thumb:
   * a selected tile on the board goes first, otherwise the last staged letter
   * comes back.
   */
  const backspace = useCallback(() => {
    if (selection && board[selection.key] !== undefined) {
      deleteSelected('back');
      return;
    }
    if (picks.length > 0) setPicks(picks.slice(0, -1));
  }, [selection, board, deleteSelected, picks, setPicks]);

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
      // The board owns the keyboard only while it's actually being played.
      if (screen !== 'game' || showHowTo) return;
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
        // A selected tile is the thing being edited, so it goes first. Backspace
        // works back through the word from where it started, Delete works on.
        if (selection) {
          e.preventDefault();
          deleteSelected(e.key === 'Backspace' ? 'back' : 'forward');
          return;
        }
        if (e.key === 'Delete' || picks.length === 0) return;
        e.preventDefault();
        setPicks(picks.slice(0, -1));
        return;
      }

      if (e.key === 'Escape') {
        // One press drops everything at once — selection ring, anchored cell
        // and staged word — so nothing lingers after the escape.
        if (!selection && interaction.kind === 'idle') return;
        e.preventDefault();
        clearFocus();
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
        if (dir && startableDirections(board, bounds, parseKey(interaction.anchor)).includes(dir)) {
          e.preventDefault();
          setLastDir(dir);
          setInteraction((prev) => (prev.kind === 'place' ? { ...prev, dir } : prev));
        }
      }
    };

    window.addEventListener('keydown', onKeyDown);
    return () => window.removeEventListener('keydown', onKeyDown);
  }, [
    screen,
    showHowTo,
    interaction,
    picks,
    typeLetter,
    setPicks,
    commit,
    selection,
    deleteSelected,
    target,
    clearFocus,
    board,
    bounds,
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
        swallowNextClick();
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
        swallowNextClick();
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
    [drag, board, togglePick, selectTile, remember, swallowNextClick],
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

  const timerSeconds = remainingMs === null ? null : Math.ceil(remainingMs / 1000);

  if (screen === 'home') {
    return (
      <div className="app">
        <HomeScreen
          onPlay={startGame}
          onShowHowTo={() => setShowHowTo(true)}
          onShowStats={() => setStatsView(loadStats())}
        />
        {showHowTo && <HowToModal onClose={dismissHowTo} />}
        <StatsPage stats={statsView} onClose={() => setStatsView(null)} />
      </div>
    );
  }

  return (
    <div className="app">
      <header className="header">
        <Scoreboard
          score={totalScore}
          level={mode === 'endless' ? null : level}
          bonusEarned={boardScore.bonusEarned && !complete}
          bonusAmount={allTilesBonus}
          complete={complete}
          timer={
            timerSeconds !== null && !complete
              ? {
                  label: mode === 'endless' && endlessPhase === 'drip' ? 'Next tiles' : 'Time',
                  seconds: timerSeconds,
                  urgent: mode === 'timed' && timerSeconds <= 15,
                }
              : null
          }
          health={
            mode === 'endless' && endlessPhase === 'drip' && !complete
              ? { loose: looseTiles, limit: ENDLESS_LOOSE_LIMIT }
              : null
          }
          pops={scorePops}
          onPopEnd={endScorePop}
        />
        <div className="header-actions">
          {complete ? (
            <button
              className="btn btn-primary"
              onClick={(e) => {
                e.currentTarget.blur();
                newGame(mode);
              }}
            >
              Play again
            </button>
          ) : mode !== 'endless' ? (
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
          ) : null}
          <Menu
            onResetGame={() => newGame(mode)}
            onShowHowTo={() => setShowHowTo(true)}
            onShowStats={() => setStatsView(loadStats())}
            onShowSummary={complete ? () => setShowSummary(true) : null}
            onReturnHome={returnHome}
          />
        </div>
      </header>

      {/* The tile-drop banner: announces new tiles the moment they land. */}
      {toast && (
        <div key={toast.serial} className="game-toast" role="status">
          {toast.text}
        </div>
      )}

      {/* The zoom rides on a CSS variable so only the tiles resize. */}
      <div
        className="board-wrap"
        ref={boardWrapRef}
        style={{ '--zoom': zoom } as React.CSSProperties}
      >
        <Grid
          bounds={bounds}
          board={board}
          cellStatus={cellStatus}
          hiddenKeys={hiddenKeys}
          preview={preview}
          previewGaps={previewGaps}
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
          onCellHover={onCellHover}
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
        canConfirm={
          interaction.kind === 'place' &&
          plan !== null &&
          plan.complete &&
          plan.steps.length > 0
        }
        onRemove={(position) => setPicks(picks.filter((_, i) => i !== position))}
        onCancel={clearFocus}
        onConfirm={() => {
          if (target) commit(target.key, target.dir);
        }}
        tools={
          <PileTools
            onUndo={undo}
            canUndo={history.length > 0}
            onBackspace={backspace}
            canBackspace={selectedKey !== null || picks.length > 0}
            onRotate={rotateDirection}
            canRotate={canRotateAnchor}
            rotateTo={
              interaction.kind === 'place' && interaction.dir === 'across' ? 'down' : 'across'
            }
            onShuffle={shufflePile}
            onAddGap={addGap}
          />
        }
      />

      <Rack
        letters={rack}
        hiddenIndex={drag?.source.type === 'rack' ? drag.source.index : null}
        picks={picks}
        justAdded={tileDrop?.count ?? 0}
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

      <LevelSplash level={splashLevel} mode={mode} onDismiss={() => setSplashLevel(null)} />

      {showSummary && (
        <GameSummary
          words={finalWords}
          score={totalScore}
          eyebrow={
            endReason === 'timeout'
              ? 'Time’s up'
              : endReason === 'buried'
                ? 'Game over'
                : 'Game finished'
          }
          title={
            endReason === 'timeout'
              ? '⏱️ Out of time!'
              : endReason === 'buried'
                ? '🫠 Buried in tiles!'
                : '🍌 Well played!'
          }
          onPlayAgain={() => newGame(mode)}
          onClose={() => setShowSummary(false)}
        />
      )}

      {showHowTo && <HowToModal onClose={dismissHowTo} />}

      <StatsPage stats={statsView} onClose={() => setStatsView(null)} />

      <ConfirmDialog
        message={confirmSkip}
        confirmLabel={level >= LEVEL_COUNT ? 'Finish anyway' : 'Move on anyway'}
        onConfirm={advanceLevel}
        onCancel={() => setConfirmSkip(null)}
      />
    </div>
  );
}
