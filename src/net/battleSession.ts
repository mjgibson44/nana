import { Peer } from 'peerjs';
import type { DataConnection } from 'peerjs';
import { battleOver, newBattleCode, type BattleState } from '../game/battle';
import { randomSeed } from '../game/rng';

/**
 * Endless Battle's plumbing: browser-to-browser connections over WebRTC, with
 * PeerJS's public broker doing the introductions. There is no game server —
 * the host's browser is the authority. It owns the roster, starts and stops
 * games, collects everyone's scores, and decides when the battle is over; the
 * other players hold one data connection to the host and follow its
 * broadcasts. The join code doubles as the host's address: hosting claims the
 * peer id `nana-battle-<code>`, and joining dials exactly that id.
 *
 * Tiles never travel over these connections. The host shares one seed per
 * game and every client grows the identical deal from it — see
 * src/game/battle.ts.
 */

/** Bumped when messages change shape, so a stale tab fails loud, not weird. */
const PROTOCOL = 1;

/** How long connecting may take before it's called a failure. */
const CONNECT_TIMEOUT_MS = 20_000;

const PEER_ID_PREFIX = 'nana-battle-';

function peerIdFor(code: string): string {
  return `${PEER_ID_PREFIX}${code.toLowerCase()}`;
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

function newPeer(id?: string): Peer {
  const broker = brokerOptions();
  if (id !== undefined) return broker ? new Peer(id, broker) : new Peer(id);
  return broker ? new Peer(broker) : new Peer();
}

type ClientMessage =
  | { t: 'hello'; name: string; proto: number }
  | { t: 'progress'; score: number; buried: boolean };

type HostMessage =
  | { t: 'state'; state: BattleState }
  | { t: 'start'; seed: string }
  | { t: 'stop' }
  | { t: 'reject'; reason: string };

/** What a battle tells the app as it goes. All calls arrive after the
 * host/join promise has resolved. */
export interface BattleEvents {
  /** The shared truth changed: roster, scores, phase. */
  onState(state: BattleState): void;
  /** A game is starting (or restarting); grow the deal from this seed. */
  onStart(seed: string): void;
  /** The host sent everyone back to the lobby. */
  onStop(): void;
  /** The battle is gone for good — connection lost or the lobby closed. */
  onEnded(message: string): void;
}

/** A live battle, hosted or joined. One method surface for both, so the app
 * doesn't fork on which side of the connection it is. */
export interface BattleHandle {
  readonly code: string;
  readonly selfId: string;
  readonly isHost: boolean;
  /** The latest shared state; safe to read immediately after connecting. */
  snapshot(): BattleState;
  /** Host only: start the game, or restart it mid-game or after a finish. */
  start(): void;
  /** Host only: send every player back to the lobby. */
  stop(): void;
  /** Report this player's own game as it moves. No-op outside a game. */
  reportProgress(score: number, buried: boolean): void;
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
      return 'This browser can’t make the player-to-player connection battles need.';
    default:
      return 'Couldn’t reach the connection service. Check your network and try again.';
  }
}

function clone(state: BattleState): BattleState {
  return { ...state, players: state.players.map((player) => ({ ...player })) };
}

/* --------------------------------- hosting -------------------------------- */

class HostSession implements BattleHandle {
  readonly isHost = true;
  readonly selfId: string;
  private readonly conns = new Map<string, DataConnection>();
  private readonly state: BattleState;
  private left = false;

  constructor(
    private readonly peer: Peer,
    readonly code: string,
    hostName: string,
    private readonly events: BattleEvents,
  ) {
    this.selfId = peer.id;
    this.state = {
      phase: 'lobby',
      game: 0,
      players: [
        {
          id: peer.id,
          name: sanitizeName(hostName),
          host: true,
          score: 0,
          buried: false,
          connected: true,
          waiting: false,
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
  }

  snapshot(): BattleState {
    return clone(this.state);
  }

  private accept(conn: DataConnection): void {
    conn.on('data', (raw) => this.onMessage(conn, raw));
    conn.on('close', () => this.dropPlayer(conn.peer));
    conn.on('error', () => this.dropPlayer(conn.peer));
  }

  private onMessage(conn: DataConnection, raw: unknown): void {
    const msg = raw as ClientMessage | null;
    if (!msg || typeof msg !== 'object') return;

    if (msg.t === 'hello') {
      if (msg.proto !== PROTOCOL) {
        const reject: HostMessage = {
          t: 'reject',
          reason: 'Your game is a different version than the host’s — refresh and rejoin.',
        };
        conn.send(reject);
        window.setTimeout(() => conn.close(), 250);
        return;
      }
      this.conns.set(conn.peer, conn);
      const existing = this.state.players.find((p) => p.id === conn.peer);
      if (existing) {
        existing.connected = true;
        existing.name = sanitizeName(msg.name);
      } else {
        this.state.players.push({
          id: conn.peer,
          name: sanitizeName(msg.name),
          host: false,
          score: 0,
          buried: false,
          connected: true,
          // Mid-game joiners watch from the lobby and play the next game.
          waiting: this.state.phase !== 'lobby',
        });
      }
      this.publish();
      return;
    }

    if (msg.t === 'progress') {
      const player = this.state.players.find((p) => p.id === conn.peer);
      if (!player || player.waiting || this.state.phase !== 'playing') return;
      player.score = Math.max(0, Math.floor(Number(msg.score))) || 0;
      player.buried = Boolean(msg.buried);
      this.checkOver();
      this.publish();
    }
  }

  private dropPlayer(id: string): void {
    this.conns.delete(id);
    const player = this.state.players.find((p) => p.id === id);
    if (!player || !player.connected) return;
    if (this.state.phase === 'playing' && !player.waiting) {
      // Keep their entry: the score they left behind still places in the
      // standings, and battleOver treats them as out of the running.
      player.connected = false;
      this.checkOver();
    } else {
      this.state.players = this.state.players.filter((p) => p.id !== id);
    }
    this.publish();
  }

  private checkOver(): void {
    if (this.state.phase !== 'playing') return;
    if (battleOver(this.state.players)) this.state.phase = 'finished';
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
    // Anyone who dropped stays dropped; a fresh game starts with who's here.
    this.state.players = this.state.players.filter((p) => p.connected);
    for (const player of this.state.players) {
      player.score = 0;
      player.buried = false;
      player.waiting = false;
    }
    this.state.phase = 'playing';
    this.state.game += 1;
    const seed = randomSeed();
    this.broadcast({ t: 'start', seed });
    this.publish();
    this.events.onStart(seed);
  }

  stop(): void {
    this.state.players = this.state.players.filter((p) => p.connected);
    for (const player of this.state.players) {
      player.score = 0;
      player.buried = false;
      player.waiting = false;
    }
    this.state.phase = 'lobby';
    this.broadcast({ t: 'stop' });
    this.publish();
    this.events.onStop();
  }

  reportProgress(score: number, buried: boolean): void {
    if (this.state.phase !== 'playing') return;
    const self = this.state.players.find((p) => p.id === this.selfId);
    if (!self || (self.score === score && self.buried === buried)) return;
    self.score = score;
    self.buried = buried;
    this.checkOver();
    this.publish();
  }

  leave(): void {
    this.left = true;
    this.peer.destroy();
  }

  private shutdown(message: string): void {
    if (this.left) return;
    this.left = true;
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

  constructor(
    private readonly peer: Peer,
    private readonly conn: DataConnection,
    readonly code: string,
    firstState: BattleState,
    private readonly events: BattleEvents,
  ) {
    this.selfId = peer.id;
    this.last = firstState;

    conn.on('data', (raw) => this.onMessage(raw));
    conn.on('close', () => this.lost());
    conn.on('error', () => this.lost());
    peer.on('error', (err) => {
      // A broker blip doesn't touch the open connection to the host; anything
      // fatal destroys the peer, which closes the connection and lands in
      // lost() by itself.
      const type = (err as { type?: string }).type;
      if (type === 'network' || type === 'peer-unavailable') return;
      this.lost();
    });
  }

  snapshot(): BattleState {
    return clone(this.last);
  }

  private onMessage(raw: unknown): void {
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
      case 'reject':
        this.left = true;
        this.peer.destroy();
        this.events.onEnded(String(msg.reason));
        break;
    }
  }

  private lost(): void {
    if (this.left) return;
    this.left = true;
    this.peer.destroy();
    this.events.onEnded('Lost the connection to the host — the battle is over.');
  }

  start(): void {
    // Host only; nothing for a guest to do.
  }

  stop(): void {
    // Host only; nothing for a guest to do.
  }

  reportProgress(score: number, buried: boolean): void {
    if (!this.conn.open) return;
    const msg: ClientMessage = { t: 'progress', score, buried };
    this.conn.send(msg);
  }

  leave(): void {
    this.left = true;
    this.peer.destroy();
  }
}

/**
 * Join a lobby by its code. Resolves once the host has answered with the
 * current state — so the lobby renders complete on arrival — and rejects
 * with a human-readable Error if the code finds nothing or the network
 * won't cooperate.
 */
export function joinBattle(
  code: string,
  name: string,
  events: BattleEvents,
): Promise<BattleHandle> {
  return new Promise((resolve, reject) => {
    const peer = newPeer();
    let settled = false;

    const fail = (message: string) => {
      if (settled) return;
      settled = true;
      window.clearTimeout(timeout);
      peer.destroy();
      reject(new Error(message));
    };

    const timeout = window.setTimeout(
      () => fail('Couldn’t reach that game. Check the code and your network, then try again.'),
      CONNECT_TIMEOUT_MS,
    );

    peer.on('error', (err) => fail(connectionFailureMessage(err)));

    peer.on('open', () => {
      const conn = peer.connect(peerIdFor(code), { reliable: true, serialization: 'json' });

      conn.on('open', () => {
        const hello: ClientMessage = { t: 'hello', name: sanitizeName(name), proto: PROTOCOL };
        conn.send(hello);
      });

      conn.on('close', () => fail('The host closed the connection.'));

      conn.on('data', (raw) => {
        const msg = raw as HostMessage | null;
        if (!msg || typeof msg !== 'object' || settled) return;
        if (msg.t === 'reject') {
          fail(String(msg.reason));
          return;
        }
        if (msg.t === 'state') {
          settled = true;
          window.clearTimeout(timeout);
          // The session re-registers 'data'; both handlers run, so hand it
          // the state we consumed and let it take over from the next message.
          resolve(new ClientSession(peer, conn, code, msg.state, events));
        }
      });
    });
  });
}
