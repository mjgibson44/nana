import { COMMON_WORDS } from './commonWords';
import { extendPuzzle, generatePuzzle } from './generator';
import { boardBounds } from './levels';
import { seededRng } from './rng';
import type { TileMap } from './types';

/**
 * Multiplayer: several players race the same Endless game (Endless Battle),
 * or exactly two fight a Duel.
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

/** What game the lobby plays: Endless raced by everyone, or a two-player Duel. */
export type BattleMode = 'endless' | 'duel';

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
   * False while the player's connection is down. A disconnected player isn't
   * out — the game pauses and waits for them to reconnect; only once the
   * grace period runs out (or they leave on purpose) do they become `left`.
   */
  connected: boolean;
  /** Gone for good — left by choice, or never came back from a drop. */
  left: boolean;
  /** Joined while a game was running; playing from the next start. */
  waiting: boolean;
  /** How many tiles are in the player's pile right now — the Duel gauge. */
  tiles: number;
}

/** The whole shared truth, owned by the host and broadcast on every change. */
export interface BattleState {
  mode: BattleMode;
  phase: BattlePhase;
  players: BattlePlayer[];
  /** Counts the games started in this lobby, so clients can tell restarts apart. */
  game: number;
  /** True while the game is held for a player who lost their connection. */
  paused: boolean;
  /** Duel only: who won, once the phase is 'finished'. Null for a draw. */
  winnerId: string | null;
}

/* ------------------------------- join codes ------------------------------- */

/** No 0/O, 1/I/L — codes get read out loud and typed on phones. */
const CODE_ALPHABET = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
export const CODE_LENGTH = 5;

export function newBattleCode(): string {
  let code = '';
  for (let i = 0; i < CODE_LENGTH; i++) {
    code += CODE_ALPHABET[Math.floor(Math.random() * CODE_ALPHABET.length)];
  }
  return code;
}

/** Forgive how a code was typed: trim, uppercase, and map the letters the
 * alphabet deliberately avoids onto what was meant. */
export function normalizeBattleCode(raw: string): string {
  return raw
    .trim()
    .toUpperCase()
    .replace(/[^A-Z0-9]/g, '')
    .replace(/0/g, 'O')
    .replace(/1/g, 'I');
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
 * sequence of letters, however the requests are sized. Drip batches grow as
 * an Endless game wears on while pile-clears stay small, so players' request
 * sizes interleave differently — which is why the hidden board always grows
 * by the same fixed chunk and requests just drain the resulting sequence.
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
        // crossword needs, so a stream can serve requests of any size (duel
        // attacks ask for as little as one tile).
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
   * disconnected player is NOT left: the game pauses and waits for them. */
  left: boolean;
  waiting: boolean;
}

/** In the current game and still able to change their score. */
function isAlive(player: Contestant): boolean {
  return !player.waiting && !player.buried && !player.left;
}

/**
 * Whether the game is decided. It ends when every player is buried (or gone),
 * and also as soon as a single player is left standing while already strictly
 * ahead — nothing they do can change the outcome, so there's no reason to
 * make them dig on. A last player standing who is tied or behind plays on:
 * the result still hangs on them.
 */
export function battleOver(players: Contestant[]): boolean {
  const inGame = players.filter((p) => !p.waiting);
  if (inGame.length === 0) return false;
  const alive = inGame.filter(isAlive);
  if (alive.length === 0) return true;
  if (alive.length === 1 && inGame.length > 1) {
    const best = Math.max(
      ...inGame.filter((p) => p !== alive[0]).map((p) => p.score),
    );
    return alive[0].score > best;
  }
  return false;
}

/**
 * Whether a duel is decided: both players are dealt in and at most one is
 * still alive. (A duel can't be decided before it has two contestants.)
 */
export function duelOver(players: Contestant[]): boolean {
  const inGame = players.filter((p) => !p.waiting);
  if (inGame.length < 2) return false;
  return inGame.filter(isAlive).length <= 1;
}

/**
 * Who won a decided duel: the last player alive, or null when nobody is —
 * a draw, which in practice takes both players going down together.
 */
export function duelWinner<T extends Contestant>(players: T[]): T | null {
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
 * The standings, best first. Waiting players aren't in this game and don't
 * get a rank — filter them out before calling. Ties share a rank.
 */
export function rankPlayers<T extends Contestant>(players: T[]): RankedPlayer<T>[] {
  const sorted = [...players].sort((a, b) => b.score - a.score);
  const ranked: RankedPlayer<T>[] = [];
  for (let i = 0; i < sorted.length; i++) {
    const tied = i > 0 && sorted[i].score === sorted[i - 1].score;
    ranked.push({ player: sorted[i], rank: tied ? ranked[i - 1].rank : i + 1 });
  }
  return ranked;
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
