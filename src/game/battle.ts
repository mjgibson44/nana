import { COMMON_WORDS } from './commonWords';
import { extendPuzzle, generatePuzzle } from './generator';
import { boardBounds } from './levels';
import { seededRng } from './rng';
import type { TileMap } from './types';

/**
 * Multiplayer: a Battle — two to eight players on one shared deal, every
 * attack split across the field, run until one player stands.
 *
 * Everything here is pure and serializable — the networking layer
 * (src/net/battleSession.ts) moves these values between browsers, and the
 * host runs the referee functions below to decide standings and the end of
 * the game. Fairness rests on one idea: tiles are never sent over the wire.
 * Each client regrows the identical deal from a shared seed (see
 * createTileStream), so the host has no privileged knowledge of what's
 * coming.
 */

/** Where a battle currently stands, for everyone in it. */
export type BattlePhase = 'lobby' | 'playing' | 'finished';

export interface BattlePlayer {
  /**
   * The player's stable identity — a random key their browser holds on to, so
   * a dropped connection can be re-attached to the same seat. (Peer ids
   * change on every reconnect, so they can't be the identity.)
   */
  id: string;
  name: string;
  host: boolean;
  /** Live score while playing; final score once buried or finished. */
  score: number;
  /** Buried under loose tiles — out of the current game. */
  buried: boolean;
  /**
   * False while the player's connection is down. The game plays on without
   * them — the host just holds their seat for a short grace so a quick
   * redial slots them straight back in; only once the grace runs out (or
   * they leave on purpose) do they become `left`.
   */
  connected: boolean;
  /** Gone for good — left by choice, or never came back from a drop. */
  left: boolean;
  /** Joined while a game was running; playing from the next start. */
  waiting: boolean;
  /** How many tiles are in the player's pile right now — the pile gauge. */
  tiles: number;
  /**
   * When this player fell out of the running — 1 for the first buried (or
   * gone for good), counting up. Null while still standing. The host writes
   * it once and never rewrites it, so a Battle's final standings read
   * straight off it: the later you went out, the higher you place.
   */
  outOrder: number | null;
}

/** The whole shared truth, owned by the host and broadcast on every change. */
export interface BattleState {
  phase: BattlePhase;
  players: BattlePlayer[];
  /** Counts the games started in this lobby, so clients can tell restarts apart. */
  game: number;
  /** Who won, once the phase is 'finished'. Null for a draw. */
  winnerId: string | null;
}

/* ------------------------------- join codes ------------------------------- */

/**
 * Letters only — no digits at all, so a code is always read and typed as a
 * word. I, L and O stay out too: they're the letters that get mistaken for
 * 1 and 0 when a code is read off a screen or spelled out down the phone.
 *
 * Three places, not five: a code exists to be read out loud across a room and
 * typed on a phone, and three letters is what fits in one glance. Twenty-three
 * letters over three places is 12,167 codes — small enough that two lobbies
 * can genuinely collide, which is why claiming one retries (`hostBattle`)
 * rather than trusting the draw.
 */
const CODE_ALPHABET = 'ABCDEFGHJKMNPQRSTUVWXYZ';
export const CODE_LENGTH = 3;

export function newBattleCode(): string {
  let code = '';
  for (let i = 0; i < CODE_LENGTH; i++) {
    code += CODE_ALPHABET[Math.floor(Math.random() * CODE_ALPHABET.length)];
  }
  return code;
}

/**
 * Forgive how a code was typed: trim, uppercase, and drop anything that isn't
 * a letter — spaces and dashes from a code written out in groups, and digits,
 * which no code contains. Normalizing never invents a character the generator
 * couldn't have dealt, so whatever comes out can be judged as typed.
 */
export function normalizeBattleCode(raw: string): string {
  return raw.trim().toUpperCase().replace(/[^A-Z]/g, '');
}

export function isValidBattleCode(code: string): boolean {
  if (code.length !== CODE_LENGTH) return false;
  for (const ch of code) {
    if (!CODE_ALPHABET.includes(ch)) return false;
  }
  return true;
}

/** The link a host shares; opening it lands on the join screen, code filled in. */
export function battleLink(code: string): string {
  const { origin, pathname } = window.location;
  return `${origin}${pathname}#battle=${code}`;
}

/** The code carried by a share link, or null when the URL isn't one. */
export function codeFromHash(hash: string): string | null {
  const match = /^#battle=([A-Za-z0-9]+)$/.exec(hash);
  if (!match) return null;
  const code = normalizeBattleCode(match[1]);
  return isValidBattleCode(code) ? code : null;
}

/* ------------------------------- tile stream ------------------------------ */

/** Deals the shared game: batch after batch of letters, identical for every
 * stream built from the same seed. */
export interface TileStream {
  next(count: number): string[];
}

/** The fixed size the stream grows its hidden board by, whatever callers ask
 * for — see the determinism contract on createTileStream. */
const STREAM_CHUNK = 5;

/**
 * The battle deal. Exactly Endless's generator — a hidden crossword grown
 * word by word — but driven by a seeded RNG, and grown off its own private
 * solution board rather than the player's real one. Players' boards diverge
 * immediately, so growing from them would deal different letters; growing
 * from the shared hidden board keeps every player's letters identical while
 * still drawing letters that weave into real crossing words.
 *
 * Determinism contract: two streams with the same seed deal the same opening
 * batch (every client asks for the same one) and after it the identical
 * sequence of letters, however the requests are sized. Drips and attacks
 * interleave differently on every player's screen — which is why the hidden
 * board always grows by the same fixed chunk and requests just drain the
 * resulting sequence.
 */
export function createTileStream(seed: string, wordPool: string[] = COMMON_WORDS): TileStream {
  const rng = seededRng(seed);
  let hidden: TileMap | null = null;
  /** Letters grown but not yet handed out. */
  const pending: string[] = [];
  return {
    next(count: number): string[] {
      if (hidden === null) {
        // The opening deal sizes the hidden board — but never below what a
        // crossword needs, so a stream can serve requests of any size
        // (attacks ask for as little as one tile).
        const puzzle = generatePuzzle(wordPool, Math.max(count, STREAM_CHUNK), rng);
        hidden = puzzle.solution ?? {};
        pending.push(...puzzle.letters);
      }
      while (pending.length < count) {
        const grown = extendPuzzle(hidden, boardBounds(hidden), wordPool, STREAM_CHUNK, rng);
        if (grown.solution) hidden = grown.solution;
        pending.push(...grown.letters);
      }
      return pending.splice(0, count);
    },
  };
}

/* -------------------------------- referee --------------------------------- */

/** The slice of a player the referee functions need. */
export interface Contestant {
  score: number;
  buried: boolean;
  /** Permanently out — left by choice or never reconnected. A merely
   * disconnected player is NOT left: their seat is held while they redial. */
  left: boolean;
  waiting: boolean;
}

/** In the current game and still able to change their score. */
function isAlive(player: Contestant): boolean {
  return !player.waiting && !player.buried && !player.left;
}

/**
 * Whether a battle is decided: at least two players are dealt in and at most
 * one is still alive. (No game can be decided before it has two
 * contestants.) The size of the field doesn't matter — a Battle of eight
 * ends exactly when one of two does, on the last player standing.
 */
export function battleOver(players: Contestant[]): boolean {
  const inGame = players.filter((p) => !p.waiting);
  if (inGame.length < 2) return false;
  return inGame.filter(isAlive).length <= 1;
}

/**
 * Who won a decided battle: the last player alive, or null when nobody is —
 * a draw, which in practice takes the last players going down together.
 */
export function battleWinner<T extends Contestant>(players: T[]): T | null {
  const alive = players.filter((p) => !p.waiting).filter(isAlive);
  return alive.length === 1 ? alive[0] : null;
}

/** One row of the standings: a player and where they sit. */
export interface RankedPlayer<T extends Contestant> {
  player: T;
  /** Competition ranking: tied scores share a rank, and the next rank skips
   * past them (1, 2, 2, 4). */
  rank: number;
}

/**
 * The standings of a survival game, best first: whoever is still standing
 * (outOrder null) leads, then everyone else in reverse order of falling —
 * the later you went out, the higher you place. Ties share a rank, which in
 * practice is only the draw where the last players went down together and
 * nobody has a null outOrder to lead with. Waiting players sat this game
 * out — filter them out before calling.
 */
export function rankByElimination<T extends Contestant & { outOrder: number | null }>(
  players: T[],
): RankedPlayer<T>[] {
  const later = (a: T, b: T): number => {
    if (a.outOrder === null && b.outOrder === null) return 0;
    if (a.outOrder === null) return -1;
    if (b.outOrder === null) return 1;
    return b.outOrder - a.outOrder;
  };
  const sorted = [...players].sort(later);
  const ranked: RankedPlayer<T>[] = [];
  for (let i = 0; i < sorted.length; i++) {
    const tied = i > 0 && later(sorted[i], sorted[i - 1]) === 0;
    ranked.push({ player: sorted[i], rank: tied ? ranked[i - 1].rank : i + 1 });
  }
  return ranked;
}

/**
 * Who took a decided game: the survivor the host named — and nobody at all
 * for the draw where the last players went down together.
 *
 * Waiting players sat this game out and can't have won it. Callers who only
 * want a yes or no for themselves ask whether their own id is in here.
 */
export function battleWinners(state: BattleState): BattlePlayer[] {
  const contestants = state.players.filter((p) => !p.waiting);
  return state.winnerId === null
    ? []
    : contestants.filter((p) => p.id === state.winnerId);
}

/** "1st", "2nd", "3rd"… for the rank badge and the results screen. */
export function ordinal(rank: number): string {
  const tens = rank % 100;
  if (tens >= 11 && tens <= 13) return `${rank}th`;
  switch (rank % 10) {
    case 1:
      return `${rank}st`;
    case 2:
      return `${rank}nd`;
    case 3:
      return `${rank}rd`;
    default:
      return `${rank}th`;
  }
}
