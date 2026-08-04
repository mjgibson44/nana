import { useCallback, useEffect, useLayoutEffect, useMemo, useRef, useState } from 'react';
import { MIN_WORD_LENGTH, extractRuns, validateBoard } from './game/board';
import { COMMON_WORDS } from './game/commonWords';
import { loadDictionary } from './game/dictionary';
import { extendPuzzle, generatePuzzle } from './game/generator';
import { boardBounds, scoreBoard, wordScore } from './game/levels';
import {
  DUEL_DRIP_SECONDS,
  DUEL_PILE_LIMIT,
  DUEL_ROUNDS,
  DUEL_ROUND_SECONDS,
  DUEL_START_TILES,
  ENDLESS_CLEAR_TILES,
  ENDLESS_CONNECT_BONUS,
  ENDLESS_INITIAL_SECONDS,
  ENDLESS_LOOSE_LIMIT,
  ENDLESS_START_TILES,
  duelAttackMultiplier,
  duelAttackTiles,
  duelDripTiles,
  duelDripTilesAt,
  endlessDripSeconds,
  endlessDripTiles,
  formatSeconds,
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
  type Pick as PilePick,
} from './game/placement';
import { loadStats, recordGame, type Stats } from './game/stats';
import {
  codeFromHash,
  createTileStream,
  rankPlayers,
  type BattleMode,
  type BattleState,
  type TileStream,
} from './game/battle';
import type { CellKey, Direction, TileMap } from './game/types';
import { keyOf, parseKey } from './game/types';
import { hostBattle, joinBattle, type BattleEvents, type BattleHandle } from './net/battleSession';
import { applyTheme, loadThemePref, saveThemePref, type ThemePref } from './theme';
import { BattleLobby } from './components/BattleLobby';
import { BattleMenu } from './components/BattleMenu';
import { BattleResults } from './components/BattleResults';
import { ConfirmDialog } from './components/ConfirmDialog';
import { ConnectionOverlay } from './components/ConnectionOverlay';
import { GameSummary, type ScoredWord } from './components/GameSummary';
import { Grid } from './components/Grid';
import { HomeScreen } from './components/HomeScreen';
import { HowToModal } from './components/HowToModal';
import { Menu } from './components/Menu';
import { PileTools } from './components/PileTools';
import { Rack } from './components/Rack';
import { Scoreboard, type ScorePop } from './components/Scoreboard';
import { SettingsPage } from './components/SettingsPage';
import { SplashCard, type Splash } from './components/Splash';
import { StatsPage } from './components/StatsPage';
import { WordBar } from './components/WordBar';

/** Pointer travel under this (px) counts as a tap, not a drag. */
const TAP_SLOP = 6;

/** How many moves back undo can reach. */
const UNDO_DEPTH = 50;

/** How long the splash card stays up before bowing out. */
const SPLASH_MS = 1700;

/** The between-rounds battle scoreboard gets longer — five seconds of reading. */
const ROUND_SPLASH_MS = 5000;

/** Holding a touch this long on the board picks the staged word up to drag. */
const HOLD_DRAG_MS = 300;

/** Tiles dealt into the tutorial, enough for a couple of crossing words. */
const TUTORIAL_TILES = 14;

/** Pinch limits, as a multiple of the stylesheet's cell size. */
const MIN_ZOOM = 0.55;
const MAX_ZOOM = 1.6;

/**
 * Auto-fit: whenever tiles change, the zoom is re-picked so every placed tile
 * fits on screen. It only ever backs out — the default size is as big as tiles
 * get, so a small crossword is left at the size the player is used to rather
 * than blown up. The pad keeps the outermost tiles off the very edge; the
 * epsilon ignores changes too small to matter.
 */
const AUTO_ZOOM_MAX = 1;
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

/** Once set, the how-to stays put — it only auto-opens on the first game. */
const HOWTO_SEEN_KEY = 'nana.howto.v1';

/** The name last used in a multiplayer lobby, so it's typed once per device. */
const PLAYER_NAME_KEY = 'nana.player.v1';

/** How the game came to an end — the summary's headline depends on it. */
type EndReason = 'won' | 'timeout' | 'buried';

/**
 * The header clock. It's either counting toward a wall-clock deadline or
 * holding a frozen remainder — frozen whenever something worth reading (the
 * how-to, a splash) is covering the board, so the modes with a clock never
 * charge for reading. Multiplayer games freeze it only for connection
 * trouble, when the whole game holds.
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
  /** Which screen is up: the mode-picking splash, a multiplayer door/lobby,
   * or a game. */
  const [screen, setScreen] = useState<'home' | 'battle' | 'game'>('home');
  const [mode, setMode] = useState<GameMode>('endless');

  /* ------------------------------ theme ------------------------------------- */

  const [themePref, setThemePref] = useState<ThemePref>(() => loadThemePref());
  const [settingsOpen, setSettingsOpen] = useState(false);

  const chooseTheme = useCallback((pref: ThemePref) => {
    setThemePref(pref);
    applyTheme(pref);
    saveThemePref(pref);
  }, []);

  /* ------------------------------ battle state ------------------------------ */

  /** Which multiplayer door the battle screen opens: Endless Battle or Duel. */
  const [battleIntent, setBattleIntent] = useState<BattleMode>('endless');
  /** The live multiplayer connection, or null outside one. */
  const [battle, setBattle] = useState<BattleHandle | null>(null);
  /** The host's latest broadcast: roster, scores, phase, pauses. */
  const [battleState, setBattleState] = useState<BattleState | null>(null);
  /** What connecting is currently doing ("Opening a lobby…"), or null. */
  const [battleBusy, setBattleBusy] = useState<string | null>(null);
  /** Why the last host/join attempt failed, shown on the battle menu. */
  const [battleError, setBattleError] = useState<string | null>(null);
  /** Why a battle ended out from under us, shown once back home. */
  const [battleNotice, setBattleNotice] = useState<string | null>(null);
  /** Whether the end-of-battle standings are up. */
  const [showBattleResults, setShowBattleResults] = useState(false);
  /** A host action that deserves a second thought before hitting everyone. */
  const [confirmBattle, setConfirmBattle] = useState<'restart' | 'lobby' | 'leave' | null>(null);
  /** A code carried in by a share link, waiting on the join form. */
  const [joinCodePrefill, setJoinCodePrefill] = useState('');
  /** True while this player's own link to the host is being redialed. */
  const [selfReconnecting, setSelfReconnecting] = useState(false);
  const [playerName, setPlayerName] = useState(() => {
    try {
      return window.localStorage.getItem(PLAYER_NAME_KEY) ?? '';
    } catch {
      return '';
    }
  });
  /**
   * The shared deal. Every client grows the same batches from the seed the
   * host announced, so nobody's tiles ever cross the network. Non-null only
   * while a multiplayer game is being played (or looked back on).
   */
  const battleStream = useRef<TileStream | null>(null);
  /** Duel: where this player's incoming attack tiles are drawn from. Seeded
   * off the shared seed and this player's own id, so attacks arrive as a
   * count and the letters never cross the wire either. */
  const attackStream = useRef<TileStream | null>(null);
  /** The battle connection for callbacks that shouldn't re-bind on renders. */
  const battleRef = useRef<BattleHandle | null>(null);

  const inBattle = battle !== null;
  const battlePhase = battleState?.phase ?? null;
  /** Whether the how-to reference is up (auto on first game, or from a menu). */
  const [showHowTo, setShowHowTo] = useState(false);
  /** The clock, in modes that have one. Null in the tutorial, in a duel's
   * final round, and once a game ends. */
  const [countdown, setCountdown] = useState<Countdown | null>(null);
  /** Endless: 'initial' is the opening two minutes; 'drip' is ever after,
   * when batches arrive on the clock and the loose count is live. */
  const [endlessPhase, setEndlessPhase] = useState<'initial' | 'drip'>('initial');
  /** Endless: how many drip intervals have run out (the opening phase isn't
   * one), which sets how big the next batch is. */
  const [dripsElapsed, setDripsElapsed] = useState(0);
  /** Duel: which round the screw is on — 1, 2, or the endless final 3. */
  const [duelRound, setDuelRound] = useState(1);
  /** Duel: the 20-second drip clock, separate from the round clock. */
  const [duelDrip, setDuelDrip] = useState<Countdown | null>(null);
  /** Duel: how many drips have landed, which sizes the next one. */
  const duelDripIndex = useRef(0);
  /** Tutorial: 1 = place a word, 2 = use a gap, 3 = done (dialog up),
   * 4 = free practice after the dialog. */
  const [tutorialStep, setTutorialStep] = useState(1);
  /** How the finished game ended, for the summary's headline. */
  const [endReason, setEndReason] = useState<EndReason | null>(null);
  /** The banner riding over the board ("+5 tiles!"), keyed so repeats replay. */
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
  /**
   * Bonuses banked so far. Word scores aren't banked — those words are still
   * on the board, so they're still being counted.
   */
  const [bankedBonus, setBankedBonus] = useState(0);
  const [complete, setComplete] = useState(false);
  /** Frozen at the moment the game ends, so "final" means final. */
  const [finalScore, setFinalScore] = useState(0);
  /** The finished board's words and points, frozen alongside the score. */
  const [finalWords, setFinalWords] = useState<ScoredWord[] | null>(null);
  /** Whether the full-screen finish summary is up. */
  const [showSummary, setShowSummary] = useState(false);
  /** The stats being looked at, or null while the stats page is closed. */
  const [statsView, setStatsView] = useState<Stats | null>(null);
  /**
   * Board-and-pile snapshots, oldest first, for undo. Duels never record —
   * placed words are permanent there, so there is nothing to take back.
   */
  const [history, setHistory] = useState<Array<{ board: TileMap; rack: string[] }>>([]);
  /**
   * Moves taken back and waiting to be redone, most recent last. Any fresh
   * move forks the timeline and empties it — see remember — so redo is only
   * offered while going forward again still makes sense.
   */
  const [future, setFuture] = useState<Array<{ board: TileMap; rack: string[] }>>([]);
  /** What the splash card is announcing, or null while nothing is showing. */
  const [splash, setSplash] = useState<Splash | null>(null);
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

  /** One expiry of each clock is handled exactly once. */
  const expiryHandled = useRef<number | null>(null);
  const dripHandled = useRef<number | null>(null);

  /** Start a fresh game. Multiplayer games hand in the shared deal's opening
   * letters; solo games draw their own at random. */
  const newGame = useCallback((nextMode: GameMode, dealtLetters?: string[]) => {
    setMode(nextMode);
    const opening =
      dealtLetters ??
      generatePuzzle(
        COMMON_WORDS,
        nextMode === 'tutorial' ? TUTORIAL_TILES : ENDLESS_START_TILES,
      ).letters;
    setRack(opening);
    setBoard({});
    setDrag(null);
    setWordDrag(null);
    setInteraction(IDLE);
    setHighlightedWord(null);
    setSelection(null);
    setBankedBonus(0);
    setComplete(false);
    setFinalScore(0);
    setFinalWords(null);
    setShowSummary(false);
    setHistory([]);
    setFuture([]);
    setSplash(
      nextMode === 'endless'
        ? {
            kind: 'start',
            eyebrow: 'Endless mode',
            title: 'Game on!',
            note: `${opening.length} tiles · ${formatSeconds(ENDLESS_INITIAL_SECONDS)} to place them`,
          }
        : nextMode === 'duel'
          ? {
              kind: 'duelRound',
              round: 1,
              final: false,
              multiplier: duelAttackMultiplier(1),
              dripTiles: duelDripTiles(1),
            }
          : null,
    );
    setEndReason(null);
    setEndlessPhase('initial');
    setDripsElapsed(0);
    setDuelRound(1);
    duelDripIndex.current = 0;
    setDuelDrip(nextMode === 'duel' ? runningCountdown(DUEL_DRIP_SECONDS) : null);
    setTutorialStep(1);
    setToast(null);
    setTileDrop(null);
    setZoom(1);
    finished.current = false;
    expiryHandled.current = null;
    dripHandled.current = null;
    setCountdown(
      nextMode === 'endless'
        ? runningCountdown(ENDLESS_INITIAL_SECONDS)
        : nextMode === 'duel'
          ? runningCountdown(DUEL_ROUND_SECONDS)
          : null,
    );
    setGameId((id) => id + 1);
  }, []);

  /** Pick a mode on the splash screen and dive in. The how-to reference
   * fronts the very first real game; the tutorial explains itself. */
  const startGame = useCallback(
    (nextMode: GameMode) => {
      newGame(nextMode);
      setScreen('game');
      if (nextMode === 'tutorial') return;
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
    setDuelDrip(null);
    setShowSummary(false);
    setSplash(null);
  }, []);

  /* --------------------------- battle lifecycle ----------------------------- */

  // A share link opens straight onto the join form, code filled in. The hash
  // is then dropped so a later refresh doesn't replay a stale invitation.
  useEffect(() => {
    const code = codeFromHash(window.location.hash);
    if (code === null) return;
    setJoinCodePrefill(code);
    setBattleIntent('endless');
    setScreen('battle');
    try {
      window.history.replaceState(null, '', window.location.pathname + window.location.search);
    } catch {
      // Leaving the hash in place is harmless.
    }
  }, []);

  /** The host said "go": grow the shared deal from the seed and dive in. */
  const handleBattleStart = useCallback(
    (seed: string) => {
      const handle = battleRef.current;
      const duel = handle?.snapshot().mode === 'duel';
      const stream = createTileStream(seed);
      battleStream.current = stream;
      attackStream.current =
        duel && handle ? createTileStream(`${seed}/attacks/${handle.selfId}`) : null;
      setShowBattleResults(false);
      setConfirmBattle(null);
      newGame(duel ? 'duel' : 'endless', stream.next(duel ? DUEL_START_TILES : ENDLESS_START_TILES));
      setScreen('game');
    },
    [newGame],
  );

  /** The host gathered everyone back in the lobby. */
  const handleBattleStop = useCallback(() => {
    battleStream.current = null;
    attackStream.current = null;
    setScreen('battle');
    setCountdown(null);
    setDuelDrip(null);
    setShowSummary(false);
    setShowBattleResults(false);
    setSplash(null);
    setConfirmBattle(null);
  }, []);

  /** The battle is gone — connection lost for good or lobby closed. Land
   * back home with a note saying why. */
  const handleBattleEnded = useCallback((message: string) => {
    battleStream.current = null;
    attackStream.current = null;
    battleRef.current = null;
    setBattle(null);
    setBattleState(null);
    setSelfReconnecting(false);
    setShowBattleResults(false);
    setConfirmBattle(null);
    setCountdown(null);
    setDuelDrip(null);
    setShowSummary(false);
    setSplash(null);
    setScreen('home');
    setBattleNotice(message);
  }, []);

  /** Duel: the opponent's word landed — their attack tiles join our pile.
   * The letters are drawn locally from the attack stream; only the count
   * crossed the network. */
  const handleAttack = useCallback((count: number) => {
    const stream = attackStream.current;
    if (!stream || count <= 0 || finished.current) return;
    const letters = stream.next(count);
    setRack((prev) => [...prev, ...letters]);
    const serial = ++dropSerial.current;
    setTileDrop({ count: letters.length, serial });
    setToast({
      text: `Incoming! +${letters.length} tile${letters.length === 1 ? '' : 's'} from your opponent`,
      serial,
    });
  }, []);

  const battleEvents = useMemo<BattleEvents>(
    () => ({
      onState: setBattleState,
      onStart: handleBattleStart,
      onStop: handleBattleStop,
      onEnded: handleBattleEnded,
      onAttack: handleAttack,
      onReconnecting: () => setSelfReconnecting(true),
      onReconnected: () => setSelfReconnecting(false),
    }),
    [handleBattleStart, handleBattleStop, handleBattleEnded, handleAttack],
  );

  const rememberPlayerName = useCallback((name: string) => {
    setPlayerName(name);
    try {
      window.localStorage.setItem(PLAYER_NAME_KEY, name);
    } catch {
      // It'll just need typing again next time.
    }
  }, []);

  const hostGame = useCallback(
    async (name: string) => {
      rememberPlayerName(name);
      setBattleBusy('Opening a lobby…');
      setBattleError(null);
      try {
        const handle = await hostBattle(name, battleIntent, battleEvents);
        battleRef.current = handle;
        setBattle(handle);
        setBattleState(handle.snapshot());
      } catch (err) {
        setBattleError(err instanceof Error ? err.message : String(err));
      } finally {
        setBattleBusy(null);
      }
    },
    [battleIntent, battleEvents, rememberPlayerName],
  );

  const joinGame = useCallback(
    async (name: string, code: string) => {
      rememberPlayerName(name);
      setBattleBusy('Joining the game…');
      setBattleError(null);
      try {
        const handle = await joinBattle(code, name, battleEvents);
        battleRef.current = handle;
        setBattle(handle);
        setBattleState(handle.snapshot());
      } catch (err) {
        setBattleError(err instanceof Error ? err.message : String(err));
      } finally {
        setBattleBusy(null);
      }
    },
    [battleEvents, rememberPlayerName],
  );

  /** Walk out — and, as the host, take the lobby down. Always by choice, so
   * no notice needed on the way home. */
  const leaveBattle = useCallback(() => {
    battleRef.current?.leave();
    battleRef.current = null;
    battleStream.current = null;
    attackStream.current = null;
    setBattle(null);
    setBattleState(null);
    setSelfReconnecting(false);
    setShowBattleResults(false);
    setConfirmBattle(null);
    setCountdown(null);
    setDuelDrip(null);
    setShowSummary(false);
    setSplash(null);
    setScreen('home');
  }, []);

  /** Host controls, with a pause for thought while a game is still running —
   * these land on every player at once. */
  const requestBattleRestart = useCallback(() => {
    if (battlePhase === 'playing') setConfirmBattle('restart');
    else battleRef.current?.start();
  }, [battlePhase]);

  const requestBattleLobby = useCallback(() => {
    if (battlePhase === 'playing') setConfirmBattle('lobby');
    else battleRef.current?.stop();
  }, [battlePhase]);

  /** Leaving deserves a second thought when it costs something: a host with
   * guests takes the lobby down, and a live board is abandoned mid-game. */
  const requestLeaveBattle = useCallback(() => {
    const handle = battleRef.current;
    if (!handle) {
      leaveBattle();
      return;
    }
    const players = battleState?.players ?? [];
    const self = players.find((p) => p.id === handle.selfId);
    const playingNow = battlePhase === 'playing' && self !== undefined && !self.waiting;
    if ((handle.isHost && players.length > 1) || playingNow) setConfirmBattle('leave');
    else leaveBattle();
  }, [battleState, battlePhase, leaveBattle]);

  /**
   * Remember the board and pile as they are, so the change about to be made can
   * be taken back. Called before a move, never after. Duels don't record:
   * placed words are permanent there.
   */
  const remember = useCallback(() => {
    if (mode === 'duel') return;
    setHistory((past) => [...past.slice(-UNDO_DEPTH + 1), { board, rack }]);
    // A new move forks the timeline; the moves undone before it can't come
    // back any more.
    setFuture([]);
  }, [mode, board, rack]);

  const undo = useCallback(() => {
    const last = history[history.length - 1];
    if (!last) return;
    // The state being left is exactly what redo comes back to.
    setFuture((ahead) => [...ahead, { board, rack }]);
    setHistory(history.slice(0, -1));
    setBoard(last.board);
    setRack(last.rack);
    setInteraction(IDLE);
    setSelection(null);
    setHighlightedWord(null);
  }, [history, board, rack]);

  /** Walk forward again through the moves undo took back. */
  const redo = useCallback(() => {
    const next = future[future.length - 1];
    if (!next) return;
    setFuture(future.slice(0, -1));
    // Straight onto the history stack rather than via remember — redoing a
    // move mustn't wipe the rest of the way forward.
    setHistory((past) => [...past.slice(-UNDO_DEPTH + 1), { board, rack }]);
    setBoard(next.board);
    setRack(next.rack);
    setInteraction(IDLE);
    setSelection(null);
    setHighlightedWord(null);
  }, [future, board, rack]);

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

  /** A scroll compensation waiting for its zoom to reach the DOM first. */
  const pendingFit = useRef<{ zoom: number; fx: number; fy: number } | null>(null);

  // Keep the whole crossword fittable: whenever the tiles change, re-pick the
  // zoom that would show all of them — larger while the crossword is small,
  // backing out as it spreads, until the zoom-out limit is reached. The
  // viewport is never steered toward the tiles, though: whatever point the
  // player is looking at stays put while the board resizes around it. Reads
  // zoom fresh on each run but deliberately doesn't depend on it, so a manual
  // pinch is left alone until the next placement.
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
    if (Math.abs(target - zoom) <= ZOOM_EPSILON) return;

    // Note where the viewport's centre sits relative to the tiles, so it can
    // be put back once the new zoom renders — the refit must not move the
    // player's focus.
    pendingFit.current = {
      zoom: target,
      fx: (wrap.scrollLeft + wrap.clientWidth / 2 - measured.left) / measured.width,
      fy: (wrap.scrollTop + wrap.clientHeight / 2 - measured.top) / measured.height,
    };
    setZoom(target);
    // eslint-disable-next-line react-hooks/exhaustive-deps -- zoom and bounds
    // are read fresh each run; depending on them would refit on every pinch.
  }, [tileBox, fitTick]);

  // The second half of the fit: once the DOM is laid out at the new zoom, put
  // the point the player was looking at straight back under the viewport's
  // centre. This only cancels the drift the resize itself would cause — it
  // never glides the view toward the crossword.
  useLayoutEffect(() => {
    const wrap = boardWrapRef.current;
    const pending = pendingFit.current;
    if (!wrap || !pending || !tileBox) return;
    if (pending.zoom !== zoom) return; // the zoom render hasn't landed yet
    pendingFit.current = null;
    const measured = measureTiles(wrap, bounds, tileBox);
    if (!measured) return;
    wrap.scrollLeft = measured.left + pending.fx * measured.width - wrap.clientWidth / 2;
    wrap.scrollTop = measured.top + pending.fy * measured.height - wrap.clientHeight / 2;
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

  /** What "every tile placed and connected" pays right now. */
  const allTilesBonus = ENDLESS_CONNECT_BONUS;

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
      // A multiplayer game's own standings screen does the announcing there —
      // and only once the whole game is decided, not when one player goes under.
      setShowSummary(!inBattle);
      setEndReason(reason);
      setCountdown(null);
      setDuelDrip(null);
      recordGame(runningScore, words.length);
      clearFocus();
    },
    [validation, runningScore, clearFocus, inBattle],
  );

  // The splash announces and then gets out of the way. The between-rounds
  // scoreboard has more to read, so it lingers longer.
  useEffect(() => {
    if (splash === null) return;
    const ms = splash.kind === 'round' ? ROUND_SPLASH_MS : SPLASH_MS;
    const timer = window.setTimeout(() => setSplash(null), ms);
    return () => window.clearTimeout(timer);
  }, [splash]);

  /* ------------------------------- the clock -------------------------------- */

  // Anything worth reading over the board stops the clock while it's up.
  // Except in multiplayer: everyone's clock has to run as one, so nothing a
  // single player does — opening the how-to, reading a splash — may stop
  // theirs while the others' tick on. What does stop a multiplayer clock is
  // connection trouble: the host pauses the game for everyone while a
  // dropped player redials, and a player redialing pauses their own.
  const battlePaused = inBattle && ((battleState?.paused ?? false) || selfReconnecting);
  const clockPaused = inBattle
    ? battlePaused
    : showHowTo || splash !== null || settingsOpen || statsView !== null;

  // Flip the clocks between running and paused as overlays come and go.
  // Written as normalization (rather than one effect per transition) so a
  // countdown started behind an overlay also gets released the moment the
  // board is clear.
  useEffect(() => {
    const normalize = (prev: Countdown | null): Countdown | null => {
      if (!prev) return prev;
      if (clockPaused && prev.kind === 'running') {
        return { kind: 'paused', remainingMs: Math.max(0, prev.endsAt - Date.now()) };
      }
      if (!clockPaused && prev.kind === 'paused') {
        return { kind: 'running', endsAt: Date.now() + prev.remainingMs };
      }
      return prev;
    };
    setCountdown(normalize);
    setDuelDrip(normalize);
  }, [clockPaused, countdown, duelDrip]);

  // The clock's own heartbeat: only ticks while genuinely counting down.
  const [clockNow, setClockNow] = useState(() => Date.now());
  useEffect(() => {
    const running = countdown?.kind === 'running' || duelDrip?.kind === 'running';
    if (!running || complete) return;
    setClockNow(Date.now());
    const timer = window.setInterval(() => setClockNow(Date.now()), 250);
    return () => window.clearInterval(timer);
  }, [countdown, duelDrip, complete]);

  const remainingMs =
    countdown === null
      ? null
      : countdown.kind === 'paused'
        ? countdown.remainingMs
        : Math.max(0, countdown.endsAt - clockNow);

  /**
   * Deal bonus tiles into the pile — from the shared stream in multiplayer so
   * every player draws the same letters, grown off this player's own board
   * otherwise — with their landing animation and a banner saying what just
   * happened.
   */
  const dealBonusTiles = useCallback(
    (count: number, message: string) => {
      const letters =
        battleRef.current !== null && battleStream.current !== null
          ? battleStream.current.next(count)
          : extendPuzzle(board, bounds, COMMON_WORDS, count).letters;
      setRack((prev) => [...prev, ...letters]);
      // The dealt tiles join every remembered pile too: undoing a move must
      // take back the move alone, never disappear tiles the clock has dealt.
      setHistory((past) =>
        past.map((snap) => ({ ...snap, rack: [...snap.rack, ...letters] })),
      );
      setFuture((ahead) =>
        ahead.map((snap) => ({ ...snap, rack: [...snap.rack, ...letters] })),
      );
      const serial = ++dropSerial.current;
      setTileDrop({ count: letters.length, serial });
      setToast({ text: message, serial });
    },
    [board, bounds],
  );

  /**
   * Endless's pressure gauge: tiles not yet doing their job — still in the
   * pile, or on the board but not part of a valid, connected word. Going over
   * the limit doesn't end the game by itself; still being over when a drip
   * round ends does.
   */
  const looseTiles = useMemo(() => {
    let onBoard = 0;
    for (const status of cellStatus.values()) {
      if (status !== 'valid') onBoard++;
    }
    return rack.length + onBoard;
  }, [cellStatus, rack.length]);

  /**
   * The round clock ran out. In Endless that's the next batch of tiles
   * arriving — and the first expiry is the end of the opening phase, which
   * also switches the loose count on. In a Duel it's the next round starting,
   * with a bigger multiplier and drip. The ref keeps one expiry from being
   * handled twice while the new countdown state lands.
   */
  useEffect(() => {
    if (complete || countdown?.kind !== 'running') return;
    if (countdown.endsAt - clockNow > 0) return;
    if (expiryHandled.current === countdown.endsAt) return;
    expiryHandled.current = countdown.endsAt;

    if (mode === 'duel') {
      const next = Math.min(DUEL_ROUNDS, duelRound + 1);
      setDuelRound(next);
      setSplash({
        kind: 'duelRound',
        round: next,
        final: next >= DUEL_ROUNDS,
        multiplier: duelAttackMultiplier(next),
        dripTiles: duelDripTiles(next),
      });
      // The final round has no clock — it runs until somebody overflows.
      setCountdown(next < DUEL_ROUNDS ? runningCountdown(DUEL_ROUND_SECONDS) : null);
      return;
    }

    if (mode === 'endless') {
      // The round's reckoning comes before its new tiles: end a drip round
      // still over the loose limit and the pile wins.
      if (endlessPhase === 'drip' && looseTiles > ENDLESS_LOOSE_LIMIT) {
        finishGame('buried');
        return;
      }
      // The opening clock running out starts the drip phase; every expiry
      // after that is one drip interval gone. The batch dealt here opens the
      // round numbered `elapsed`, so that's the size it lands at.
      const elapsed = endlessPhase === 'drip' ? dripsElapsed + 1 : 0;
      const seconds = endlessDripSeconds(elapsed);
      const batch = endlessDripTiles(elapsed);
      dealBonusTiles(batch, `+${batch} tiles!`);
      if (inBattle && battle && battleState) {
        // Between rounds a battle shows the whole field's scores — this
        // player's own straight from their board, the rest as last reported.
        const standings = rankPlayers(
          battleState.players
            .filter((p) => !p.waiting)
            .map((p) => (p.id === battle.selfId ? { ...p, score: runningScore } : p)),
        ).map(({ player, rank }) => ({
          rank,
          name: player.name,
          score: player.score,
          self: player.id === battle.selfId,
          buried: player.buried || player.left,
        }));
        setSplash({ kind: 'round', standings, seconds, tiles: batch });
      } else if (
        elapsed > 0 &&
        (seconds < endlessDripSeconds(elapsed - 1) || batch > endlessDripTiles(elapsed - 1))
      ) {
        // Solo keeps the pressure card: the wait got shorter or the batches
        // grew, and the splash says so — holding the new clock until it's
        // been read, the same way the opening splash does.
        setSplash({ kind: 'speedup', seconds, tiles: batch });
      }
      setEndlessPhase('drip');
      setDripsElapsed(elapsed);
      setCountdown(runningCountdown(seconds));
    }
  }, [
    clockNow,
    countdown,
    complete,
    mode,
    duelRound,
    endlessPhase,
    dripsElapsed,
    looseTiles,
    inBattle,
    battle,
    battleState,
    runningScore,
    finishGame,
    dealBonusTiles,
  ]);

  /* --------------------------------- duel ----------------------------------- */

  /**
   * The Duel drip: every 20 seconds a batch lands in the pile, sized by the
   * round the game is in. Both players draw drip k from the same stream, so
   * the letters stay identical however their clocks drift.
   */
  useEffect(() => {
    if (mode !== 'duel' || complete || duelDrip?.kind !== 'running') return;
    if (duelDrip.endsAt - clockNow > 0) return;
    if (dripHandled.current === duelDrip.endsAt) return;
    dripHandled.current = duelDrip.endsAt;

    const index = duelDripIndex.current;
    duelDripIndex.current = index + 1;
    const batch = duelDripTilesAt(index);
    dealBonusTiles(batch, `+${batch} tile${batch === 1 ? '' : 's'}`);
    setDuelDrip(runningCountdown(DUEL_DRIP_SECONDS));
  }, [clockNow, duelDrip, mode, complete, dealBonusTiles]);

  /**
   * The Duel's one loss rule: let the pile exceed the limit — for any reason,
   * at any moment — and the game is over on the spot.
   */
  useEffect(() => {
    if (mode !== 'duel' || complete) return;
    if (rack.length > DUEL_PILE_LIMIT) finishGame('buried');
  }, [mode, complete, rack.length, finishGame]);

  /** Duel: the opponent's side of the header — their pile against the limit. */
  const duelOpponent = useMemo(() => {
    if (mode !== 'duel' || !battle || !battleState) return null;
    const other = battleState.players.find(
      (p) => p.id !== battle.selfId && !p.waiting && !p.left,
    );
    if (!other) return null;
    return {
      name: other.name,
      tiles: other.tiles,
      limit: DUEL_PILE_LIMIT,
      out: other.buried,
    };
  }, [mode, battle, battleState]);

  /* -------------------------------- endless --------------------------------- */

  /**
   * Clearing the pile in Endless: the connect bonus banks (the live bonus
   * swaps for it, so the score holds steady) and a fresh batch arrives — the
   * same size as a timed drop. The short wait lets the bonus land on the
   * scoreboard before the pile refills.
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

  /* -------------------------------- battle ---------------------------------- */

  /**
   * This player's live place in the field, for the header. Their own score is
   * read straight off the board — the host's echo of it can lag a beat — and
   * everyone else's as last reported.
   */
  const battleRank = useMemo(() => {
    if (!inBattle || !battle || !battleState || mode !== 'endless') return null;
    const contestants = battleState.players
      .filter((p) => !p.waiting)
      .map((p) =>
        p.id === battle.selfId ? { ...p, score: complete ? finalScore : runningScore } : p,
      );
    if (contestants.length === 0) return null;
    const ranked = rankPlayers(contestants);
    const self = ranked.find((entry) => entry.player.id === battle.selfId);
    if (!self) return null;
    return {
      place: self.rank,
      of: ranked.length,
      buried: self.player.buried || (complete && endReason === 'buried'),
    };
  }, [inBattle, battle, battleState, mode, complete, finalScore, runningScore, endReason]);

  /**
   * Keep the host's standings current: every score or pile change reports in,
   * and going under reports itself the moment the board freezes. The host
   * aggregates these into the state everyone sees.
   */
  useEffect(() => {
    if (!battle || battlePhase !== 'playing' || screen !== 'game') return;
    battle.reportProgress(
      complete ? finalScore : runningScore,
      endReason === 'buried',
      rack.length,
    );
  }, [battle, battlePhase, screen, runningScore, complete, finalScore, endReason, rack.length]);

  /**
   * The multiplayer game is decided. Freeze this board where it stands —
   * survivors keep the score they're on, exactly what the host ranked them
   * by — and raise the standings. The ref keeps later re-renders (the board
   * can still be fiddled with behind the results) from re-raising them.
   */
  const battleFinishSeen = useRef(false);
  useEffect(() => {
    if (!battle || battlePhase !== 'finished' || screen !== 'game') {
      battleFinishSeen.current = false;
      return;
    }
    if (battleFinishSeen.current) return;
    battleFinishSeen.current = true;
    finishGame('won');
    setShowBattleResults(true);
  }, [battle, battlePhase, screen, finishGame]);

  // Going under in an Endless Battle isn't the end of the show — say so,
  // once, while the survivors race on. (A duel ends the moment anyone does.)
  useEffect(() => {
    if (!inBattle || mode !== 'endless' || battlePhase !== 'playing') return;
    if (!complete || endReason !== 'buried') return;
    const serial = ++dropSerial.current;
    setToast({ text: 'You’re buried! The race goes on…', serial });
  }, [inBattle, mode, battlePhase, complete, endReason]);

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

  /**
   * A placement was refused — say why. A refusal that changes nothing on
   * screen reads as a bug, so it always gets a banner.
   */
  const rejectToast = useCallback((text: string) => {
    setToast({ text, serial: ++dropSerial.current });
  }, []);

  /**
   * Drop the planned tiles onto the board and spend the pile letters they
   * used. Places the staged word by default; a drag-and-dropped tile passes
   * its own single pick instead, so every landing goes through the same rules.
   */
  const commit = useCallback(
    (anchor: CellKey, dir: Direction, picksToPlace: PilePick[] = pickList) => {
      if (picksToPlace.length === 0) return;
      const result = planPlacement(board, bounds, parseKey(anchor), dir, picksToPlace);
      if (result.steps.length === 0 || !result.complete) return;

      const next = { ...board };
      for (const step of result.steps) next[step.key] = step.letter;
      const placed = new Set(result.steps.map((step) => step.key));
      // The words this placement makes or grows — what a duel judges and
      // what its attacks are sized by.
      const newRuns = extractRuns(next).filter((run) =>
        run.cells.some((cell) => placed.has(cell)),
      );

      // A Duel placement is forever, so only real words are allowed down —
      // and a lone letter spelling nothing isn't a word at all.
      if (mode === 'duel') {
        if (!dictionary) {
          rejectToast('Hold on — the dictionary is still loading.');
          return;
        }
        if (newRuns.length === 0) {
          rejectToast('A lone letter has to join a word.');
          return;
        }
        const bad = newRuns.filter(
          (run) => run.word.length < MIN_WORD_LENGTH || !dictionary.has(run.word),
        );
        if (bad.length > 0) {
          const words = bad.map((run) => run.word.toUpperCase());
          rejectToast(
            words.length === 1
              ? `${words[0]} isn’t a word`
              : `${words.join(', ')} aren’t words`,
          );
          return;
        }
      }

      remember();
      setBoard(next);
      const spent = new Set(result.steps.map((step) => step.rackIndex));
      setRack((prev) => prev.filter((_, i) => !spent.has(i)));
      setLastDir(dir);

      // Duel: the word that just landed hits the opponent — one tile per
      // letter past three, scaled by the round. The longest word the
      // placement made counts, so extending a word is worth the whole word.
      if (mode === 'duel' && battleRef.current) {
        const wordLength = newRuns.reduce((top, run) => Math.max(top, run.word.length), 0);
        const attack = duelAttackTiles(wordLength, duelRound);
        if (attack > 0) {
          battleRef.current.sendAttack(attack);
          const serial = ++dropSerial.current;
          setToast({
            text: `Sent ${attack} tile${attack === 1 ? '' : 's'} to your opponent!`,
            serial,
          });
        }
      }

      // The tutorial watches for its two milestones: any word placed, then a
      // word placed through a gap.
      if (mode === 'tutorial') {
        const usedGap = picksToPlace.some((pick) => pick.letter === null);
        setTutorialStep((step) => (step === 1 ? 2 : step === 2 && usedGap ? 3 : step));
      }

      // Confirming ends the whole gesture, however the word was submitted:
      // no anchored cell, no selection ring, no word controls left behind.
      clearFocus();
    },
    [board, bounds, pickList, mode, duelRound, dictionary, remember, clearFocus, rejectToast],
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
      if (fits.length === 0) {
        // The gap was aimed but the word has no room either way round — say
        // so, or the dead tap looks like a bug.
        rejectToast('That word doesn’t fit over this letter.');
        return false;
      }

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
    [board, pickList, wordsByCell, lastDir, bounds, dictionary, commit, rejectToast],
  );

  /**
   * Single-tap a placed tile to pick it out for deletion.
   *
   * While letters are waiting to be placed the tap doesn't select: a word
   * staged with a gap lands here instead, the clicked letter filling its first
   * gap — and a word without one stays put, so a stray tap can't throw it away.
   *
   * In a Duel placed tiles are permanent, so the tap can aim a gap or anchor
   * the next word from the letter, but never selects for deletion.
   */
  const selectTile = useCallback(
    (key: CellKey) => {
      if (picksOf(interaction).length > 0) {
        commitThroughLetter(key);
        return;
      }
      if (mode !== 'duel') {
        const runs = wordsByCell.get(key);
        // Delete walks along the word this tile reads in. A crossing tile
        // belongs to two, and across wins: it matches reading order, and
        // selecting the other direction's next letter is only a click away.
        const dir: Direction = runs?.some((run) => run.direction === 'across')
          ? 'across'
          : 'down';
        setSelection({ key, dir });
      }
      // Anchoring it too means one click on a letter surfaces everything that
      // letter can do: its word's controls, and a direction for carrying a new
      // word on from it. A boxed-in letter can't start one, so it just selects.
      const startDir = assumeDir(key);
      setInteraction(
        startDir === null ? IDLE : { kind: 'place', anchor: key, dir: startDir, picks: [] },
      );
    },
    [interaction, mode, commitThroughLetter, wordsByCell, assumeDir],
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
      if (screen !== 'game' || showHowTo || showBattleResults || battlePaused) return;
      if (settingsOpen || statsView !== null) return;
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
    showBattleResults,
    battlePaused,
    settingsOpen,
    statsView,
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

      // A Duel drop goes through the same commit flow as a typed word, so the
      // dictionary judging and attack rules still apply to a dragged tile.
      if (mode === 'duel') {
        const duelTarget = document.elementFromPoint(x, y);
        const duelCell = duelTarget?.closest('[data-cell]') as HTMLElement | null;
        if (duelCell && source.type === 'rack') {
          const key = keyOf(Number(duelCell.dataset.row), Number(duelCell.dataset.col));
          if (!(key in board)) {
            commit(key, 'across', [{ letter, rackIndex: source.index }]);
          }
          swallowNextClick();
        }
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
    [drag, mode, board, togglePick, selectTile, remember, swallowNextClick, commit],
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
      // Duel tiles are permanent: no dragging, no double-tap return. A tap
      // still aims a staged gap or anchors the next word from the letter.
      if (mode === 'duel') {
        e.preventDefault();
        selectTile(key);
        swallowNextClick();
        return;
      }
      const now = performance.now();
      if (lastPress.current?.key === key && now - lastPress.current.time < 350) {
        lastPress.current = null;
        e.preventDefault();
        // A double-press on a word's first letter turns the word about it;
        // on any other tile it returns the letter to the pile.
        const leads = (wordsByCell.get(key) ?? []).filter((run) => run.cells[0] === key);
        if (leads.length > 0) {
          const word =
            leads.find((run) => run.direction === 'across' && canRotate(run)) ??
            leads.find(canRotate);
          if (word) rotateWord(word);
          else rejectToast(`No room to turn ${leads[0].word.toUpperCase()}`);
          swallowNextClick();
          return;
        }
        returnToRack(key);
        return;
      }
      lastPress.current = { key, time: now };
      startDrag(letter, { type: 'board', key }, e);
    },
    [
      mode,
      selectTile,
      swallowNextClick,
      returnToRack,
      startDrag,
      wordsByCell,
      canRotate,
      rotateWord,
      rejectToast,
    ],
  );

  const shufflePile = useCallback(() => {
    setRack(shuffleArray);
    setInteraction(IDLE);
  }, []);

  /* --------------------------- hold-to-drag preview -------------------------- */

  /**
   * On touch screens, pressing and holding the board while a word is staged
   * picks the word's preview up: the ghost letters follow the finger so the
   * landing spot can be lined up, and letting go anchors the word there —
   * ready for confirm. While it's active it owns the gesture outright,
   * overriding the pan the same touch would otherwise scroll the board with.
   */
  const [previewDrag, setPreviewDrag] = useState<{ pointerId: number } | null>(null);
  const holdPending = useRef<{ pointerId: number; x: number; y: number; timer: number } | null>(
    null,
  );

  const hoverFromPoint = useCallback((x: number, y: number) => {
    const el = document.elementFromPoint(x, y);
    const cellEl = el?.closest('[data-cell]') as HTMLElement | null;
    if (cellEl) {
      setHoverCell(keyOf(Number(cellEl.dataset.row), Number(cellEl.dataset.col)));
    }
  }, []);

  const cancelHold = useCallback(() => {
    const pending = holdPending.current;
    if (!pending) return;
    window.clearTimeout(pending.timer);
    holdPending.current = null;
  }, []);

  const onBoardPointerDown = useCallback(
    (e: React.PointerEvent) => {
      // Mouse users aim by hovering; the hold is a touch (and pen) affordance.
      if (e.pointerType === 'mouse') return;
      if (picks.length === 0 || drag !== null || wordDrag !== null) return;
      // A press on a tile starts the tile's own gesture, not this one.
      if ((e.target as HTMLElement).closest('.board-tile')) return;
      cancelHold();
      const { pointerId, clientX, clientY } = e;
      const timer = window.setTimeout(() => {
        holdPending.current = null;
        // A held anchor lets the preview follow the finger again.
        setInteraction((prev) =>
          prev.kind === 'place' ? { kind: 'spell', picks: prev.picks } : prev,
        );
        setPreviewDrag({ pointerId });
        hoverFromPoint(clientX, clientY);
      }, HOLD_DRAG_MS);
      holdPending.current = { pointerId, x: clientX, y: clientY, timer };
    },
    [picks.length, drag, wordDrag, cancelHold, hoverFromPoint],
  );

  const onBoardPointerMove = useCallback(
    (e: React.PointerEvent) => {
      const pending = holdPending.current;
      if (!pending || pending.pointerId !== e.pointerId) return;
      // Real movement before the hold fires means a pan — let the board scroll.
      if (
        Math.abs(e.clientX - pending.x) > TAP_SLOP ||
        Math.abs(e.clientY - pending.y) > TAP_SLOP
      ) {
        cancelHold();
      }
    },
    [cancelHold],
  );

  useEffect(() => {
    if (!previewDrag) return;
    const move = (e: PointerEvent) => {
      if (e.pointerId !== previewDrag.pointerId) return;
      hoverFromPoint(e.clientX, e.clientY);
    };
    const up = (e: PointerEvent) => {
      if (e.pointerId !== previewDrag.pointerId) return;
      setPreviewDrag(null);
      const el = document.elementFromPoint(e.clientX, e.clientY);
      const cellEl = el?.closest('[data-cell]') as HTMLElement | null;
      if (cellEl) {
        onCellClick(keyOf(Number(cellEl.dataset.row), Number(cellEl.dataset.col)));
        swallowNextClick();
      }
    };
    const cancel = (e: PointerEvent) => {
      if (e.pointerId === previewDrag.pointerId) setPreviewDrag(null);
    };
    window.addEventListener('pointermove', move);
    window.addEventListener('pointerup', up);
    window.addEventListener('pointercancel', cancel);
    return () => {
      window.removeEventListener('pointermove', move);
      window.removeEventListener('pointerup', up);
      window.removeEventListener('pointercancel', cancel);
    };
  }, [previewDrag, hoverFromPoint, onCellClick, swallowNextClick]);

  // While the preview drag owns the touch, the board must not scroll under
  // it — a non-passive listener is the only way to veto the native pan.
  useEffect(() => {
    const wrap = boardWrapRef.current;
    if (!wrap || !previewDrag) return;
    const block = (e: TouchEvent) => e.preventDefault();
    wrap.addEventListener('touchmove', block, { passive: false });
    return () => wrap.removeEventListener('touchmove', block);
  }, [previewDrag]);

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

  /**
   * Duel: the header counts down to the next tile drop — the clock the player
   * is actually racing — while the round chip says where the match stands.
   * The round clock still runs underneath to advance the rounds.
   */
  const duelDripMs =
    duelDrip === null
      ? null
      : duelDrip.kind === 'paused'
        ? duelDrip.remainingMs
        : Math.max(0, duelDrip.endsAt - clockNow);
  const duelDripSeconds = duelDripMs === null ? null : Math.ceil(duelDripMs / 1000);

  /* --------------------------------- screens -------------------------------- */

  if (screen === 'home') {
    return (
      <div className="app">
        <HomeScreen
          onPlayEndless={() => startGame('endless')}
          onBattle={() => {
            setBattleNotice(null);
            setBattleError(null);
            setBattleIntent('endless');
            setScreen('battle');
          }}
          onDuel={() => {
            setBattleNotice(null);
            setBattleError(null);
            setBattleIntent('duel');
            setScreen('battle');
          }}
          onTutorial={() => startGame('tutorial')}
          onShowHowTo={() => setShowHowTo(true)}
          onShowStats={() => setStatsView(loadStats())}
          onShowSettings={() => setSettingsOpen(true)}
        />
        {battleNotice && (
          <button type="button" className="battle-notice" onClick={() => setBattleNotice(null)}>
            {battleNotice}
          </button>
        )}
        {showHowTo && <HowToModal onClose={dismissHowTo} />}
        <StatsPage stats={statsView} onClose={() => setStatsView(null)} />
        <SettingsPage
          open={settingsOpen}
          theme={themePref}
          onTheme={chooseTheme}
          onClose={() => setSettingsOpen(false)}
        />
      </div>
    );
  }

  if (screen === 'battle') {
    return (
      <div className="app">
        {battle && battleState ? (
          <BattleLobby
            state={battleState}
            code={battle.code}
            selfId={battle.selfId}
            isHost={battle.isHost}
            onStart={() => battleRef.current?.start()}
            onLeave={requestLeaveBattle}
          />
        ) : (
          <BattleMenu
            mode={battleIntent}
            initialName={playerName}
            initialCode={joinCodePrefill}
            busy={battleBusy}
            error={battleError}
            onHost={hostGame}
            onJoin={joinGame}
            onBack={() => {
              setBattleError(null);
              setJoinCodePrefill('');
              setScreen('home');
            }}
          />
        )}
        <ConnectionOverlay
          reconnecting={selfReconnecting}
          state={battleState}
          selfId={battle?.selfId ?? null}
          onLeave={leaveBattle}
        />
        <ConfirmDialog
          message={
            confirmBattle === 'leave'
              ? battle?.isHost
                ? 'You’re the host — leaving closes the lobby for everyone.'
                : 'Leave the game? The others play on without you.'
              : null
          }
          confirmLabel={battle?.isHost ? 'Close the lobby' : 'Leave game'}
          cancelLabel="Stay"
          onConfirm={() => {
            setConfirmBattle(null);
            leaveBattle();
          }}
          onCancel={() => setConfirmBattle(null)}
        />
      </div>
    );
  }

  return (
    <div className="app">
      <header className="header">
        <Scoreboard
          score={totalScore}
          bonusEarned={boardScore.bonusEarned && !complete && mode !== 'duel'}
          bonusAmount={allTilesBonus}
          complete={complete}
          timer={
            mode === 'duel'
              ? duelDripSeconds !== null && !complete
                ? { label: 'Next tiles', seconds: duelDripSeconds, urgent: false }
                : null
              : timerSeconds !== null && !complete
                ? {
                    label:
                      mode === 'endless' && endlessPhase === 'drip' ? 'Next tiles' : 'Time',
                    seconds: timerSeconds,
                    // Over the loose limit, the round clock is the deadline to
                    // dig back under — it pleads as hard as a dying timer.
                    urgent:
                      mode === 'endless' &&
                      endlessPhase === 'drip' &&
                      looseTiles > ENDLESS_LOOSE_LIMIT,
                  }
                : null
          }
          round={
            mode === 'duel' && !complete
              ? duelRound < DUEL_ROUNDS
                ? `${duelRound}/${DUEL_ROUNDS}`
                : 'Final'
              : null
          }
          tiles={
            mode === 'endless' && endlessPhase === 'drip' && !complete
              ? { label: 'Loose tiles', loose: looseTiles, limit: ENDLESS_LOOSE_LIMIT }
              : mode === 'duel' && !complete
                ? { label: 'Pile', loose: rack.length, limit: DUEL_PILE_LIMIT }
                : null
          }
          opponent={duelOpponent}
          rank={battleRank}
          pops={scorePops}
          onPopEnd={endScorePop}
        />
        <div className="header-actions">
          {complete && !inBattle ? (
            // In a multiplayer game the next round is the host's call, made
            // from the standings screen — a lone "Play again" here would fork
            // the lobby.
            <button
              className="btn btn-primary"
              onClick={(e) => {
                e.currentTarget.blur();
                newGame(mode);
              }}
            >
              Play again
            </button>
          ) : null}
          <Menu
            onResetGame={inBattle ? null : () => newGame(mode)}
            onShowHowTo={() => setShowHowTo(true)}
            onShowStats={() => setStatsView(loadStats())}
            onShowSettings={() => setSettingsOpen(true)}
            onShowSummary={
              inBattle
                ? battlePhase === 'finished'
                  ? () => setShowBattleResults(true)
                  : null
                : complete
                  ? () => setShowSummary(true)
                  : null
            }
            onReturnHome={inBattle ? requestLeaveBattle : returnHome}
            battle={
              inBattle && battle
                ? {
                    isHost: battle.isHost,
                    onRestart: requestBattleRestart,
                    onToLobby: requestBattleLobby,
                  }
                : null
            }
          />
        </div>
      </header>

      {/* The tutorial's running instructions, step by step. */}
      {mode === 'tutorial' && tutorialStep <= 2 && (
        <div className="tutorial-banner" role="status">
          <span className="tutorial-step">Step {tutorialStep} of 2</span>
          {tutorialStep === 1 ? (
            <p className="tutorial-text">
              Type a word with your tiles (or tap them in the pile), then click an empty square
              on the board and press <kbd>Enter</kbd> (or the ✓) to place it. On a phone, you
              can also press and hold the board to drag the word around — let go where it
              should land, then confirm.
            </p>
          ) : (
            <p className="tutorial-text">
              Now cross a word you&rsquo;ve placed: type a new word, but press <kbd>Space</kbd>{' '}
              (or the dashed gap button) instead of the letter that&rsquo;s already on the
              board. Then tap that letter on the board — the gap lands right on it.
            </p>
          )}
        </div>
      )}

      {/* The tile-drop banner: announces new tiles the moment they land. */}
      {toast && (
        <div key={toast.serial} className="game-toast" role="status">
          {toast.text}
        </div>
      )}

      {/* The zoom rides on a CSS variable so only the tiles resize. */}
      <div className="board-area">
      <div
        className="board-wrap"
        ref={boardWrapRef}
        style={{ '--zoom': zoom } as React.CSSProperties}
        onPointerDown={onBoardPointerDown}
        onPointerMove={onBoardPointerMove}
        onPointerUp={cancelHold}
        onPointerCancel={cancelHold}
        onPointerLeave={cancelHold}
        onContextMenu={(e) => {
          // A long-press must not summon the context menu mid-drag.
          if (previewDrag || holdPending.current) e.preventDefault();
        }}
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
          boardLocked={mode === 'duel'}
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
          plan.steps.length > 0 &&
          (mode !== 'duel' || (verdict?.ok ?? false))
        }
        canCancel={interaction.kind !== 'idle' || selectedKey !== null}
        onRemove={(position) => setPicks(picks.filter((_, i) => i !== position))}
        onConfirm={() => {
          if (target) commit(target.key, target.dir);
        }}
        onCancel={clearFocus}
        tools={
          <PileTools
            onUndo={undo}
            canUndo={history.length > 0}
            onRedo={redo}
            canRedo={future.length > 0}
            onBackspace={backspace}
            canBackspace={selectedKey !== null || picks.length > 0}
            onRotate={rotateDirection}
            canRotate={canRotateAnchor}
            rotateTo={
              interaction.kind === 'place' && interaction.dir === 'across' ? 'down' : 'across'
            }
            onAddGap={addGap}
          />
        }
      />

      <Rack
        letters={rack}
        hiddenIndex={drag?.source.type === 'rack' ? drag.source.index : null}
        picks={picks}
        justAdded={tileDrop?.count ?? 0}
        onShuffle={shufflePile}
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

      <SplashCard splash={splash} onDismiss={() => setSplash(null)} />

      {showSummary && !inBattle && (
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
              ? 'Out of time!'
              : endReason === 'buried'
                ? 'Buried in tiles!'
                : 'Well played!'
          }
          onPlayAgain={() => newGame(mode)}
          onClose={() => setShowSummary(false)}
          onReturnHome={returnHome}
        />
      )}

      {showHowTo && <HowToModal onClose={dismissHowTo} />}

      <StatsPage stats={statsView} onClose={() => setStatsView(null)} />

      <SettingsPage
        open={settingsOpen}
        theme={themePref}
        onTheme={chooseTheme}
        onClose={() => setSettingsOpen(false)}
      />

      {/* The tutorial's graduation: both steps done. */}
      <ConfirmDialog
        message={
          mode === 'tutorial' && tutorialStep === 3
            ? 'That’s the whole game: weave every tile into one connected crossword of real ' +
              'words. Green means good, red means not a word, orange means not connected yet. ' +
              'You’re ready.'
            : null
        }
        confirmLabel="Back to the menu"
        cancelLabel="Keep practicing"
        onConfirm={returnHome}
        onCancel={() => setTutorialStep(4)}
      />

      {/* Connection trouble: our own redial, or the host pausing for someone. */}
      <ConnectionOverlay
        reconnecting={selfReconnecting}
        state={battleState}
        selfId={battle?.selfId ?? null}
        onLeave={leaveBattle}
      />

      {/* The end of a multiplayer game: who won, and what the host does next. */}
      {showBattleResults && battle && battleState && (
        <BattleResults
          state={battleState}
          selfId={battle.selfId}
          isHost={battle.isHost}
          onPlayAgain={() => battleRef.current?.start()}
          onToLobby={() => battleRef.current?.stop()}
          onLeave={requestLeaveBattle}
          onClose={() => setShowBattleResults(false)}
        />
      )}

      {/* Host actions that hit every player mid-game get a second thought. */}
      <ConfirmDialog
        message={
          confirmBattle === 'restart'
            ? 'Restart the game? Every player’s board resets and a fresh game starts for everyone.'
            : confirmBattle === 'lobby'
              ? 'End this game and send every player back to the lobby?'
              : confirmBattle === 'leave'
                ? battle?.isHost
                  ? 'You’re the host — leaving ends the game for everyone.'
                  : 'Leave the game? The others play on without you.'
                : null
        }
        confirmLabel={
          confirmBattle === 'restart'
            ? 'Restart for everyone'
            : confirmBattle === 'lobby'
              ? 'Back to the lobby'
              : 'Leave game'
        }
        cancelLabel="Keep playing"
        onConfirm={() => {
          setConfirmBattle(null);
          if (confirmBattle === 'restart') battleRef.current?.start();
          else if (confirmBattle === 'lobby') battleRef.current?.stop();
          else if (confirmBattle === 'leave') leaveBattle();
        }}
        onCancel={() => setConfirmBattle(null)}
      />
    </div>
  );
}
