import { Peer, util } from 'peerjs';
import type { DataConnection, PeerJSOption } from 'peerjs';
import {
  battleOver,
  battleWinner,
  newBattleCode,
  type BattlePlayer,
  type BattleState,
} from '../game/battle';
import { BATTLE_MAX_PLAYERS, splitAttackTiles } from '../game/modes';
import { randomSeed } from '../game/rng';

/**
 * Multiplayer plumbing: browser-to-browser connections over WebRTC, with
 * PeerJS's public broker doing the introductions. There is no game server —
 * the host's browser is the authority. It owns the roster, starts and stops
 * games, collects everyone's scores, and decides when the game is over; the
 * other players hold one data connection to the host and follow its
 * broadcasts. The join code doubles as the host's address: hosting claims the
 * peer id `nana-battle-<code>`, and joining dials exactly that id.
 *
 * Tiles never travel over these connections. The host shares one seed per
 * game and every client grows the identical deal from it — see
 * src/game/battle.ts. (Attack batches are the one exception in spirit: even
 * they travel as a count, not letters — the receiver draws the letters from
 * a stream seeded off the shared seed.)
 *
 * Connection failsafes, in three layers:
 *
 *  - Identity survives the connection. Every player carries a stable random
 *    key (per tab), so when their WebRTC link dies and they dial back in,
 *    the host re-attaches them to the same seat — score, board and all.
 *  - The game never waits. A player who vanishes mid-game doesn't pause
 *    anyone: the battle plays on while the host holds their seat for a
 *    short grace. Dial back inside it and nothing happened; miss it and
 *    they're counted out and the game continues without them. Coming back
 *    even later still lands them in the lobby, dealt into the next game.
 *  - Clients heal themselves. On any loss — or on waking from a phone's app
 *    switch to find the link stale — the client quietly redials with backoff
 *    until the reconnect budget is spent, and only then gives up.
 *  - Joining retries itself. A first dial that silently stalls (a flaky
 *    broker, a jammed negotiation) isn't the answer — joinBattle keeps
 *    dialing with fresh connections until its budget runs out, and only a
 *    definitive no (wrong code, host said no) fails right away.
 */

/** Bumped when messages change shape, so a stale tab fails loud, not weird. */
const PROTOCOL = 5;

/** How long connecting may take before it's called a failure. */
const CONNECT_TIMEOUT_MS = 20_000;

/** Each join attempt gets this long before a fresh dial replaces it. */
const JOIN_ATTEMPT_MS = 12_000;

/** Total time joining may spend across attempts before giving up. */
const JOIN_BUDGET_MS = 30_000;

/**
 * How long the host holds a dropped player's seat before they're out. The
 * game plays on regardless — this only decides how long a redial gets them
 * their board back rather than a spectator's seat for the next game. Long
 * enough for a couple of fresh dials through the broker; short enough that
 * the field isn't fighting a ghost for long.
 */
export const RECONNECT_GRACE_MS = 30_000;

/** How long a client keeps redialing before giving up. Deliberately far past
 * the host's grace: landing late doesn't fail the reconnect, it just means
 * this game went on without them — they're back in the lobby, dealt into
 * the next one. */
const RECONNECT_BUDGET_MS = 115_000;

/** Each reconnect attempt gets this long before the next try. */
const RECONNECT_ATTEMPT_MS = 12_000;

/** The host announces itself this often so everyone can tell live from dead. */
const PING_INTERVAL_MS = 10_000;

/**
 * Silence longer than this means the link is gone even if nobody said so —
 * wide enough that one delayed ping doesn't trip it, tight enough that a
 * dead player doesn't haunt the field for long. (Tripping it isn't fatal
 * anyway: the seat is held for the grace while the player redials.)
 */
const STALE_LINK_MS = 25_000;

/**
 * The transport's own verdict, when it gives one: an ICE state of failed,
 * closed — or disconnected, which on a dead peer never recovers — means the
 * link is done. Reacting to it beats waiting out the staleness window.
 */
function watchTransport(conn: DataConnection, onDead: () => void): void {
  const pc = (conn as unknown as { peerConnection?: RTCPeerConnection }).peerConnection;
  if (!pc) return;
  const check = () => {
    const state = pc.iceConnectionState;
    if (state === 'failed' || state === 'closed') onDead();
  };
  pc.addEventListener('iceconnectionstatechange', check);
}

const PEER_ID_PREFIX = 'nana-battle-';

function peerIdFor(code: string): string {
  return `${PEER_ID_PREFIX}${code.toLowerCase()}`;
}

/**
 * This tab's stable player identity. Peer ids change on every reconnect, so
 * seats are keyed by this instead — sessionStorage keeps it per-tab (so two
 * tabs in one browser stay two players) and across reloads.
 */
function playerKey(): string {
  const KEY = 'nana.playerKey.v1';
  try {
    const existing = window.sessionStorage.getItem(KEY);
    if (existing) return existing;
    const fresh = `p-${randomSeed()}${randomSeed()}`;
    window.sessionStorage.setItem(KEY, fresh);
    return fresh;
  } catch {
    return `p-${randomSeed()}${randomSeed()}`;
  }
}

/**
 * Which broker introduces the peers. Unset, PeerJS's free public cloud does
 * it — fine for casual play. A deployment that wants its own signaling
 * server (e.g. `npx peer --port 9000`) points these at it at build time:
 * VITE_PEER_HOST, and optionally VITE_PEER_PORT, VITE_PEER_PATH and
 * VITE_PEER_SECURE=false. Only introductions run through the broker; the
 * game itself flows peer to peer either way.
 */
function brokerOptions(): { host: string; port: number; path: string; secure: boolean } | null {
  const host = import.meta.env.VITE_PEER_HOST as string | undefined;
  if (!host) return null;
  return {
    host,
    port: Number(import.meta.env.VITE_PEER_PORT ?? 443),
    path: (import.meta.env.VITE_PEER_PATH as string | undefined) ?? '/',
    secure: import.meta.env.VITE_PEER_SECURE !== 'false',
  };
}

/**
 * Which servers help the browsers find a path to each other. Always PeerJS's
 * own defaults (Google and Twilio STUN plus its free shared TURN relay) and
 * one more public STUN host on the standard port — no-account infrastructure
 * that costs nothing to carry and gives a network that filters one server
 * another to try.
 *
 * WebRTC needs a TURN relay when a player's network refuses direct
 * connections (symmetric NAT, strict firewalls), and the free shared relay
 * is best-effort — often the reason joining feels flaky. A deployment that
 * wants dependable joins brings its own: set VITE_TURN_URL (comma-separated
 * turn:/turns: urls) plus VITE_TURN_USERNAME and VITE_TURN_CREDENTIAL at
 * build time — a managed relay's free tier works as well as a self-hosted
 * coturn, and infra/README.md walks through both. The configured relay
 * joins the list rather than replacing it, so an outage — or a spent
 * free-tier quota — on it degrades to the default behavior instead of
 * breaking connections outright.
 */
function iceConfig(): RTCConfiguration {
  const iceServers: RTCIceServer[] = [
    ...util.defaultConfig.iceServers,
    { urls: 'stun:stun.cloudflare.com:3478' },
  ];
  const urls = ((import.meta.env.VITE_TURN_URL as string | undefined) ?? '')
    .split(',')
    .map((url) => url.trim())
    .filter(Boolean);
  if (urls.length > 0) {
    iceServers.push({
      urls,
      username: (import.meta.env.VITE_TURN_USERNAME as string | undefined) ?? '',
      credential: (import.meta.env.VITE_TURN_CREDENTIAL as string | undefined) ?? '',
    });
  }
  return { iceServers };
}

function newPeer(id?: string): Peer {
  const options: PeerJSOption = { ...(brokerOptions() ?? {}), config: iceConfig() };
  return id !== undefined ? new Peer(id, options) : new Peer(options);
}

type ClientMessage =
  | { t: 'hello'; name: string; key: string; proto: number }
  | { t: 'progress'; score: number; buried: boolean; tiles: number }
  | { t: 'attack'; count: number }
  | { t: 'pong' }
  | { t: 'leave' };

type HostMessage =
  | { t: 'state'; state: BattleState }
  | { t: 'start'; seed: string }
  | { t: 'stop' }
  | { t: 'reject'; reason: string }
  | { t: 'attack'; count: number }
  | { t: 'ping' };

/** What a battle tells the app as it goes. All calls arrive after the
 * host/join promise has resolved. */
export interface BattleEvents {
  /** The shared truth changed: roster, scores, phase, pauses. */
  onState(state: BattleState): void;
  /** A game is starting (or restarting); grow the deal from this seed. */
  onStart(seed: string): void;
  /** The host sent everyone back to the lobby. */
  onStop(): void;
  /** The battle is gone for good — connection lost past saving, or the
   * lobby closed. */
  onEnded(message: string): void;
  /** A rival's word just sent this many tiles our way. */
  onAttack(count: number): void;
  /** This client's own link dropped; it's redialing in the background. */
  onReconnecting(): void;
  /** The redial worked — same seat inside the host's grace; back as a
   * spectator dealt into the next game after it. */
  onReconnected(): void;
}

/** A live battle, hosted or joined. One method surface for both, so the app
 * doesn't fork on which side of the connection it is. */
export interface BattleHandle {
  readonly code: string;
  /** This player's stable id — the same one their roster entry carries. */
  readonly selfId: string;
  readonly isHost: boolean;
  /** The latest shared state; safe to read immediately after connecting. */
  snapshot(): BattleState;
  /** Host only: start the game, or restart it mid-game or after a finish. */
  start(): void;
  /** Host only: send every player back to the lobby. */
  stop(): void;
  /** Report this player's own game as it moves. No-op outside a game. */
  reportProgress(score: number, buried: boolean, tiles: number): void;
  /** Send an attack of `count` tiles, split across the rivals standing. */
  sendAttack(count: number): void;
  /** Leave for good. Hosts take the whole lobby down with them. */
  leave(): void;
}

function sanitizeName(raw: unknown): string {
  const name = String(raw ?? '')
    .replace(/\s+/g, ' ')
    .trim()
    .slice(0, 24);
  return name || 'Player';
}

function connectionFailureMessage(err: unknown): string {
  const type = (err as { type?: string } | null)?.type;
  switch (type) {
    case 'peer-unavailable':
      return 'No game found with that code. Check it with your host and try again.';
    case 'browser-incompatible':
      return 'This browser can’t make the player-to-player connection multiplayer needs.';
    default:
      return 'Couldn’t reach the connection service. Check your network and try again.';
  }
}

/** A failed dial, marked with whether a fresh dial stands a chance. */
class DialError extends Error {
  constructor(
    message: string,
    readonly retryable: boolean,
  ) {
    super(message);
  }
}

function retryableFailure(err: unknown): boolean {
  const type = (err as { type?: string } | null)?.type;
  // A missing code or an incapable browser won't improve on a redial;
  // anything else is the broker or the network having a moment.
  return type !== 'peer-unavailable' && type !== 'browser-incompatible';
}

function clone(state: BattleState): BattleState {
  return { ...state, players: state.players.map((player) => ({ ...player })) };
}

/* --------------------------------- hosting -------------------------------- */

class HostSession implements BattleHandle {
  readonly isHost = true;
  readonly selfId: string;
  /** Live connections by player id (the stable key, not the peer id). */
  private readonly conns = new Map<string, DataConnection>();
  /** When each player was last heard from, for the staleness sweep. */
  private readonly lastSeen = new Map<string, number>();
  /** Grace timers for players who dropped and may still come back. */
  private readonly graceTimers = new Map<string, number>();
  private readonly state: BattleState;
  private pingTimer: number | undefined;
  private left = false;
  /** How many contestants have fallen this game — the next outOrder. */
  private outCounter = 0;
  /** Where a battle attack's remainder starts landing next, so the odd tile
   * rotates round the field instead of always hitting the same seat. */
  private attackSpread = 0;

  private readonly onVisible = () => {
    // Coming back from a phone's app switch: make sure the broker link is
    // up so new joiners (and reconnecting players) can still find us.
    if (!this.left && this.peer.disconnected && !this.peer.destroyed) this.peer.reconnect();
  };

  constructor(
    private readonly peer: Peer,
    readonly code: string,
    hostName: string,
    private readonly events: BattleEvents,
  ) {
    this.selfId = playerKey();
    this.state = {
      phase: 'lobby',
      game: 0,
      winnerId: null,
      players: [
        {
          id: this.selfId,
          name: sanitizeName(hostName),
          host: true,
          score: 0,
          buried: false,
          connected: true,
          left: false,
          waiting: false,
          tiles: 0,
          outOrder: null,
        },
      ],
    };

    peer.on('connection', (conn) => this.accept(conn));
    // The broker connection only matters for new joiners; get it back quietly
    // so a blip doesn't stop later players from finding the lobby.
    peer.on('disconnected', () => {
      if (!this.left && !peer.destroyed) peer.reconnect();
    });
    peer.on('error', (err) => {
      const type = (err as { type?: string }).type;
      // Losing the broker only blocks new joiners — the live player
      // connections don't run through it, so the game itself plays on.
      if (type === 'peer-unavailable' || type === 'network') return;
      this.shutdown(connectionFailureMessage(err));
    });

    document.addEventListener('visibilitychange', this.onVisible);

    // The heartbeat: keeps every link warm, and notices the ones that died
    // without saying so (a phone that fell asleep mid-game).
    this.pingTimer = window.setInterval(() => this.sweep(), PING_INTERVAL_MS);
  }

  snapshot(): BattleState {
    return clone(this.state);
  }

  private sweep(): void {
    const now = Date.now();
    this.broadcast({ t: 'ping' });
    for (const [id, conn] of this.conns) {
      const seen = this.lastSeen.get(id) ?? now;
      if (now - seen > STALE_LINK_MS) {
        // Close it ourselves; the close handler runs the normal drop path,
        // which holds the player's seat while the game plays on.
        this.conns.delete(id);
        try {
          conn.close();
        } catch {
          // A connection too dead to close is exactly the case in point.
        }
        this.dropPlayer(id);
      }
    }
  }

  private accept(conn: DataConnection): void {
    /** Which seat this connection belongs to — known once it says hello. */
    let playerId: string | null = null;
    const gone = () => {
      if (playerId !== null && this.conns.get(playerId) === conn) {
        this.conns.delete(playerId);
        this.dropPlayer(playerId);
      }
    };
    conn.on('data', (raw) => {
      if (playerId !== null) this.lastSeen.set(playerId, Date.now());
      const claimed = this.onMessage(conn, playerId, raw);
      if (claimed !== null) playerId = claimed;
    });
    conn.on('close', gone);
    conn.on('error', gone);
    // A crashed peer often never says close — but the transport notices.
    watchTransport(conn, gone);
  }

  /** Handle one message; returns the player id a hello claims, if any. */
  private onMessage(conn: DataConnection, playerId: string | null, raw: unknown): string | null {
    const msg = raw as ClientMessage | null;
    if (!msg || typeof msg !== 'object') return null;

    if (msg.t === 'hello') {
      if (msg.proto !== PROTOCOL) {
        const reject: HostMessage = {
          t: 'reject',
          reason: 'Your game is a different version than the host’s — refresh and rejoin.',
        };
        conn.send(reject);
        window.setTimeout(() => conn.close(), 250);
        return null;
      }

      const key = String(msg.key || conn.peer);
      const existing = this.state.players.find((p) => p.id === key);

      if (!existing) {
        // A battle seats up to eight. Anyone past the limit is politely
        // turned away.
        const seated = this.state.players.filter((p) => !p.left).length;
        if (seated >= BATTLE_MAX_PLAYERS) {
          const reject: HostMessage = {
            t: 'reject',
            reason: `This battle is full — ${BATTLE_MAX_PLAYERS} players are already in.`,
          };
          conn.send(reject);
          window.setTimeout(() => conn.close(), 250);
          return null;
        }
        this.state.players.push({
          id: key,
          name: sanitizeName(msg.name),
          host: false,
          score: 0,
          buried: false,
          connected: true,
          left: false,
          waiting: this.state.phase !== 'lobby',
          tiles: 0,
          outOrder: null,
        });
      } else {
        // The same seat dialing back in — from a drop, or a fresh tab that
        // kept its key. Re-attach and cancel any countdown on their seat.
        existing.connected = true;
        existing.name = sanitizeName(msg.name);
        if (existing.left) {
          // They were counted out while away; they're back as a spectator
          // and deal into the next game like any newcomer.
          existing.left = false;
          existing.waiting = this.state.phase !== 'lobby';
        }
        const timer = this.graceTimers.get(key);
        if (timer !== undefined) {
          window.clearTimeout(timer);
          this.graceTimers.delete(key);
        }
      }

      // One live connection per seat: a replaced link gets closed quietly.
      const old = this.conns.get(key);
      if (old && old !== conn) {
        try {
          old.close();
        } catch {
          // Already dead — which is why it's being replaced.
        }
      }
      this.conns.set(key, conn);
      this.lastSeen.set(key, Date.now());
      this.publish();
      return key;
    }

    if (playerId === null) return null;

    if (msg.t === 'pong') return null;

    if (msg.t === 'leave') {
      // A deliberate exit: no grace, no pause — the game moves on without
      // them right away.
      this.conns.delete(playerId);
      this.removePlayer(playerId);
      return null;
    }

    if (msg.t === 'progress') {
      const player = this.state.players.find((p) => p.id === playerId);
      if (!player || player.waiting || this.state.phase !== 'playing') return null;
      player.score = Math.max(0, Math.floor(Number(msg.score))) || 0;
      const buried = Boolean(msg.buried);
      if (buried && !player.buried) this.markOut(player);
      player.buried = buried;
      player.tiles = Math.max(0, Math.floor(Number(msg.tiles))) || 0;
      this.checkOver();
      this.publish();
      return null;
    }

    if (msg.t === 'attack') {
      this.relayAttack(playerId, Number(msg.count));
      return null;
    }

    return null;
  }

  /**
   * Fan an attack out from `fromId` — or take our share ourselves. The total
   * is split across every rival still standing (splitAttackTiles), with the
   * remainder rotating round the field so no seat is always the one taking
   * the odd tile; one rival left takes the lot. Each target still only ever
   * hears a count — the letters come from their own attack stream.
   */
  private relayAttack(fromId: string, count: number): void {
    if (this.state.phase !== 'playing') return;
    if (!Number.isFinite(count) || count <= 0) return;
    const sender = this.state.players.find((p) => p.id === fromId);
    if (!sender || sender.waiting || sender.buried || sender.left) return;
    const targets = this.state.players.filter(
      (p) => p.id !== fromId && !p.waiting && !p.left && !p.buried,
    );
    if (targets.length === 0) return;
    const clamped = Math.min(50, Math.floor(count));
    const shares = splitAttackTiles(clamped, targets.length, this.attackSpread);
    // Next attack's remainder starts where this one's left off.
    this.attackSpread = (this.attackSpread + (clamped % targets.length)) % targets.length;
    targets.forEach((target, i) => {
      const share = shares[i];
      if (share <= 0) return;
      if (target.id === this.selfId) {
        this.events.onAttack(share);
        return;
      }
      const conn = this.conns.get(target.id);
      if (conn?.open) {
        const msg: HostMessage = { t: 'attack', count: share };
        conn.send(msg);
      }
    });
  }

  /** Note the moment a contestant fell — first out is 1, counting up. It's
   * written once and never rewritten, so a Battle's standings can be read
   * straight off it however the game ends. */
  private markOut(player: BattlePlayer): void {
    if (player.outOrder !== null) return;
    player.outOrder = ++this.outCounter;
  }

  /**
   * A player's link died. Mid-game their seat is held while they redial —
   * the game plays on for everyone else meanwhile; in the lobby (or as a
   * spectator) they just leave.
   */
  private dropPlayer(id: string): void {
    const player = this.state.players.find((p) => p.id === id);
    if (!player || !player.connected) return;

    const midGame = this.state.phase === 'playing' && !player.waiting;
    if (!midGame) {
      this.removePlayer(id);
      return;
    }

    player.connected = false;
    this.publish();

    // The grace clock: come back before it runs out and the seat is still
    // theirs; miss it and they're out — the game has moved on without them.
    const timer = window.setTimeout(() => {
      this.graceTimers.delete(id);
      const p = this.state.players.find((entry) => entry.id === id);
      if (!p || p.connected) return;
      p.left = true;
      // Out of the running the moment the grace runs out — that's their
      // place in the standings.
      this.markOut(p);
      this.checkOver();
      this.publish();
    }, RECONNECT_GRACE_MS);
    this.graceTimers.set(id, timer);
  }

  /** Remove a player entirely — deliberate leave, or a drop outside a game. */
  private removePlayer(id: string): void {
    const player = this.state.players.find((p) => p.id === id);
    if (!player) return;
    const timer = this.graceTimers.get(id);
    if (timer !== undefined) {
      window.clearTimeout(timer);
      this.graceTimers.delete(id);
    }
    if (this.state.phase === 'playing' && !player.waiting) {
      // Keep their entry: the score they left behind still places in the
      // standings, and the referee treats them as out of the running.
      player.connected = false;
      player.left = true;
      this.markOut(player);
      this.checkOver();
    } else {
      this.state.players = this.state.players.filter((p) => p.id !== id);
    }
    this.publish();
  }

  private checkOver(): void {
    if (this.state.phase !== 'playing') return;
    // A survival game: over on the last player standing, whatever the size
    // of the field.
    if (battleOver(this.state.players)) {
      this.state.winnerId = battleWinner(this.state.players)?.id ?? null;
      this.state.phase = 'finished';
    }
  }

  private broadcast(msg: HostMessage): void {
    for (const conn of this.conns.values()) {
      if (conn.open) conn.send(msg);
    }
  }

  /** Send the state to every player, the host's own screen included. */
  private publish(): void {
    const state = this.snapshot();
    this.broadcast({ t: 'state', state });
    this.events.onState(clone(state));
  }

  start(): void {
    // Anyone gone (or still mid-drop) doesn't deal in; a fresh game starts
    // with who's actually here.
    for (const timer of this.graceTimers.values()) window.clearTimeout(timer);
    this.graceTimers.clear();
    this.state.players = this.state.players.filter((p) => p.connected && !p.left);
    for (const player of this.state.players) {
      player.score = 0;
      player.buried = false;
      player.waiting = false;
      player.tiles = 0;
      player.outOrder = null;
    }
    this.outCounter = 0;
    this.attackSpread = 0;
    this.state.phase = 'playing';
    this.state.game += 1;
    this.state.winnerId = null;
    const seed = randomSeed();
    this.broadcast({ t: 'start', seed });
    this.publish();
    this.events.onStart(seed);
  }

  stop(): void {
    for (const timer of this.graceTimers.values()) window.clearTimeout(timer);
    this.graceTimers.clear();
    this.state.players = this.state.players.filter((p) => p.connected && !p.left);
    for (const player of this.state.players) {
      player.score = 0;
      player.buried = false;
      player.waiting = false;
      player.tiles = 0;
      player.outOrder = null;
    }
    this.outCounter = 0;
    this.attackSpread = 0;
    this.state.phase = 'lobby';
    this.state.winnerId = null;
    this.broadcast({ t: 'stop' });
    this.publish();
    this.events.onStop();
  }

  reportProgress(score: number, buried: boolean, tiles: number): void {
    if (this.state.phase !== 'playing') return;
    const self = this.state.players.find((p) => p.id === this.selfId);
    if (!self || (self.score === score && self.buried === buried && self.tiles === tiles)) {
      return;
    }
    self.score = score;
    if (buried && !self.buried) this.markOut(self);
    self.buried = buried;
    self.tiles = tiles;
    this.checkOver();
    this.publish();
  }

  sendAttack(count: number): void {
    this.relayAttack(this.selfId, count);
  }

  leave(): void {
    this.left = true;
    this.dispose();
    this.peer.destroy();
  }

  private dispose(): void {
    window.clearInterval(this.pingTimer);
    for (const timer of this.graceTimers.values()) window.clearTimeout(timer);
    this.graceTimers.clear();
    document.removeEventListener('visibilitychange', this.onVisible);
  }

  private shutdown(message: string): void {
    if (this.left) return;
    this.left = true;
    this.dispose();
    this.peer.destroy();
    this.events.onEnded(message);
  }
}

/**
 * Open a lobby. Resolves once the join code is claimed with the broker and
 * other players could dial it; rejects with a human-readable Error otherwise.
 */
export function hostBattle(name: string, events: BattleEvents): Promise<BattleHandle> {
  return new Promise((resolve, reject) => {
    let attempts = 0;

    const tryCode = () => {
      const code = newBattleCode();
      const peer = newPeer(peerIdFor(code));
      let settled = false;

      const timeout = window.setTimeout(() => {
        if (settled) return;
        settled = true;
        peer.destroy();
        reject(new Error(connectionFailureMessage(null)));
      }, CONNECT_TIMEOUT_MS);

      peer.on('open', () => {
        if (settled) return;
        settled = true;
        window.clearTimeout(timeout);
        resolve(new HostSession(peer, code, name, events));
      });

      peer.on('error', (err) => {
        if (settled) return;
        settled = true;
        window.clearTimeout(timeout);
        peer.destroy();
        // Someone else holds this code — extraordinarily unlikely, so a
        // couple of fresh draws is all it should ever take.
        if ((err as { type?: string }).type === 'unavailable-id' && attempts < 3) {
          attempts += 1;
          tryCode();
          return;
        }
        reject(new Error(connectionFailureMessage(err)));
      });
    };

    tryCode();
  });
}

/* --------------------------------- joining -------------------------------- */

class ClientSession implements BattleHandle {
  readonly isHost = false;
  readonly selfId: string;
  private last: BattleState;
  private left = false;
  private reconnecting = false;
  private lastHeard = Date.now();
  private readonly staleTimer: number;

  private readonly onVisible = () => {
    if (this.left || this.reconnecting) return;
    if (document.visibilityState !== 'visible') return;
    // Back from an app switch: if the link went quiet (or outright closed)
    // while the phone was away, start healing it now rather than waiting to
    // notice mid-move.
    if (!this.conn.open || Date.now() - this.lastHeard > STALE_LINK_MS) {
      this.linkDown();
    }
  };

  constructor(
    private peer: Peer,
    private conn: DataConnection,
    readonly code: string,
    private readonly name: string,
    private readonly key: string,
    firstState: BattleState,
    private readonly events: BattleEvents,
  ) {
    this.selfId = key;
    this.last = firstState;
    this.attach(peer, conn);
    document.addEventListener('visibilitychange', this.onVisible);
    // The host pings every few seconds; too long without hearing anything
    // means the link is dead even if nothing ever said so.
    this.staleTimer = window.setInterval(() => {
      if (this.left || this.reconnecting) return;
      if (Date.now() - this.lastHeard > STALE_LINK_MS) this.linkDown();
    }, PING_INTERVAL_MS);
  }

  snapshot(): BattleState {
    return clone(this.last);
  }

  private attach(peer: Peer, conn: DataConnection): void {
    conn.on('data', (raw) => this.onMessage(raw));
    conn.on('close', () => this.linkDown(peer, conn));
    conn.on('error', () => this.linkDown(peer, conn));
    // A host that vanished mid-call often never says close — but the
    // transport notices.
    watchTransport(conn, () => this.linkDown(peer, conn));
    peer.on('error', (err) => {
      // A broker blip doesn't touch the open connection to the host;
      // anything fatal destroys the peer, which closes the connection and
      // lands in linkDown by itself.
      const type = (err as { type?: string }).type;
      if (type === 'network' || type === 'peer-unavailable') return;
      this.linkDown(peer, conn);
    });
  }

  private onMessage(raw: unknown): void {
    this.lastHeard = Date.now();
    const msg = raw as HostMessage | null;
    if (!msg || typeof msg !== 'object') return;
    switch (msg.t) {
      case 'state':
        this.last = msg.state;
        this.events.onState(clone(msg.state));
        break;
      case 'start':
        this.events.onStart(String(msg.seed));
        break;
      case 'stop':
        this.events.onStop();
        break;
      case 'ping': {
        if (this.conn.open) {
          const pong: ClientMessage = { t: 'pong' };
          this.conn.send(pong);
        }
        break;
      }
      case 'attack':
        this.events.onAttack(Math.max(0, Math.floor(Number(msg.count))));
        break;
      case 'reject':
        this.fail(String(msg.reason));
        break;
    }
  }

  /**
   * The link to the host is down (or too stale to trust). Not the end: dial
   * back in with the same identity, backing off between tries, until the
   * reconnect budget is spent. The game plays on meanwhile — land inside
   * the host's grace and the seat is still ours, board and all; later, and
   * it's a spectator's seat until the next game deals us in.
   */
  private linkDown(fromPeer?: Peer, fromConn?: DataConnection): void {
    if (this.left || this.reconnecting) return;
    // Stale handlers from an already-replaced connection don't get a say.
    if (fromConn !== undefined && fromConn !== this.conn) return;
    if (fromPeer !== undefined && fromPeer !== this.peer) return;

    this.reconnecting = true;
    this.events.onReconnecting();
    try {
      this.peer.destroy();
    } catch {
      // It was likely dead already.
    }

    const deadline = Date.now() + RECONNECT_BUDGET_MS;
    let attempt = 0;

    const tryOnce = () => {
      if (this.left) return;
      if (Date.now() >= deadline) {
        this.fail('Couldn’t reconnect to the game — the connection is gone.');
        return;
      }
      attempt += 1;

      dial(this.code, this.name, this.key, RECONNECT_ATTEMPT_MS)
        .then(({ peer, conn, state }) => {
          if (this.left) {
            peer.destroy();
            return;
          }
          this.peer = peer;
          this.conn = conn;
          this.lastHeard = Date.now();
          this.attach(peer, conn);
          this.reconnecting = false;
          this.last = state;
          this.events.onReconnected();
          this.events.onState(clone(state));
        })
        .catch(() => {
          if (this.left) return;
          // Back off a little more each round: 2s, 4s, 8s, then 10s forever.
          const wait = Math.min(10_000, 1000 * 2 ** attempt);
          window.setTimeout(tryOnce, wait);
        });
    };

    tryOnce();
  }

  private fail(message: string): void {
    if (this.left) return;
    this.left = true;
    window.clearInterval(this.staleTimer);
    document.removeEventListener('visibilitychange', this.onVisible);
    try {
      this.peer.destroy();
    } catch {
      // Nothing left to tear down.
    }
    this.events.onEnded(message);
  }

  start(): void {
    // Host only; nothing for a guest to do.
  }

  stop(): void {
    // Host only; nothing for a guest to do.
  }

  reportProgress(score: number, buried: boolean, tiles: number): void {
    if (this.reconnecting || !this.conn.open) return;
    const msg: ClientMessage = { t: 'progress', score, buried, tiles };
    this.conn.send(msg);
  }

  sendAttack(count: number): void {
    if (this.reconnecting || !this.conn.open) return;
    const msg: ClientMessage = { t: 'attack', count };
    this.conn.send(msg);
  }

  leave(): void {
    if (this.left) return;
    this.left = true;
    window.clearInterval(this.staleTimer);
    document.removeEventListener('visibilitychange', this.onVisible);
    // Tell the host it's on purpose, so nobody waits out a grace period.
    try {
      if (this.conn.open) {
        const bye: ClientMessage = { t: 'leave' };
        this.conn.send(bye);
      }
    } catch {
      // Leaving is best-effort; destroying the peer says it anyway.
    }
    window.setTimeout(() => this.peer.destroy(), 150);
  }
}

/**
 * One dial to a host: fresh peer, connect, say hello, wait for the first
 * state. Resolves with all three or rejects — used by both the first join
 * and every reconnect attempt.
 */
function dial(
  code: string,
  name: string,
  key: string,
  timeoutMs: number,
): Promise<{ peer: Peer; conn: DataConnection; state: BattleState }> {
  return new Promise((resolve, reject) => {
    const peer = newPeer();
    let settled = false;
    let iceWatch: number | undefined;

    const settle = () => {
      settled = true;
      window.clearTimeout(timeout);
      window.clearInterval(iceWatch);
    };

    const fail = (message: string, retryable: boolean) => {
      if (settled) return;
      settle();
      peer.destroy();
      reject(new DialError(message, retryable));
    };

    const timeout = window.setTimeout(
      () =>
        fail('Couldn’t reach that game. Check the code and your network, then try again.', true),
      timeoutMs,
    );

    peer.on('error', (err) => fail(connectionFailureMessage(err), retryableFailure(err)));

    peer.on('open', () => {
      const conn = peer.connect(peerIdFor(code), { reliable: true, serialization: 'json' });

      // The transport's own verdict beats waiting out the timeout: ICE
      // landing on failed means this network refuses the direct connection.
      // (Polled, not listened for — the RTCPeerConnection appears mid-dial.)
      iceWatch = window.setInterval(() => {
        const pc = (conn as unknown as { peerConnection?: RTCPeerConnection }).peerConnection;
        if (pc?.iceConnectionState === 'failed') {
          fail(
            'This network won’t allow the player-to-player connection. Try another network — a phone hotspot usually works.',
            true,
          );
        }
      }, 1_000);

      conn.on('open', () => {
        const hello: ClientMessage = { t: 'hello', name: sanitizeName(name), key, proto: PROTOCOL };
        conn.send(hello);
      });

      conn.on('close', () => fail('The host closed the connection.', false));

      conn.on('data', (raw) => {
        const msg = raw as HostMessage | null;
        if (!msg || typeof msg !== 'object' || settled) return;
        if (msg.t === 'reject') {
          fail(String(msg.reason), false);
          return;
        }
        if (msg.t === 'state') {
          settle();
          // The session re-registers 'data'; both handlers run, so hand it
          // the state we consumed and let it take over from the next message.
          resolve({ peer, conn, state: msg.state });
        }
      });
    });
  });
}

/**
 * Join a lobby by its code. Resolves once the host has answered with the
 * current state — so the lobby renders complete on arrival — and rejects
 * with a human-readable Error if the code finds nothing or the network
 * won't cooperate. A dial that merely stalls isn't taken as the answer:
 * fresh dials replace it until the budget runs out, because a new broker
 * socket and a new negotiation often succeed where a jammed one never will.
 */
export async function joinBattle(
  code: string,
  name: string,
  events: BattleEvents,
): Promise<BattleHandle> {
  const key = playerKey();
  const deadline = Date.now() + JOIN_BUDGET_MS;

  for (;;) {
    const remaining = deadline - Date.now();
    const attempt = Math.min(JOIN_ATTEMPT_MS, Math.max(remaining, 4_000));
    try {
      const { peer, conn, state } = await dial(code, name, key, attempt);
      return new ClientSession(peer, conn, code, name, key, state, events);
    } catch (err) {
      const definitive = !(err instanceof DialError) || !err.retryable;
      // A real answer, or out of time: the last failure is the verdict.
      if (definitive || Date.now() + 4_000 > deadline) throw err;
      // A beat between dials, so a broker mid-hiccup isn't hammered.
      await new Promise((tick) => window.setTimeout(tick, 500));
    }
  }
}
