> Research appendix to [`docs/apple-port-plan.md`](../apple-port-plan.md).
> Generated 2026-08-18 against commit `2b8f271`; file:line references are to that tree.

# Multiplayer Protocol & Networking Specification — nana (React+TS word game)

Source files: `/home/user/nana/src/net/battleSession.ts` (transport + sessions), `/home/user/nana/src/game/battle.ts` (pure multiplayer brain), `/home/user/nana/src/game/modes.ts` (battle tuning constants), `/home/user/nana/src/game/rng.ts` (seeded PRNG), `/home/user/nana/src/App.tsx` (driver), `/home/user/nana/src/components/{BattleLobby,BattleMenu,ConnectionOverlay,BattleSpectator,BattleResults}.tsx` (UI), `/home/user/nana/infra/*` + `.env.example`/`.env.production` (infra). PeerJS ^1.5.5 (package.json:13).

## 0. Topology overview

- Pure host-authoritative star: no game server. The host's browser is the authority; every non-host client holds exactly ONE DataConnection to the host (battleSession.ts:14–20). Clients never talk to each other.
- The join code doubles as the host's PeerJS peer id: hosting claims `nana-battle-<code lowercased>` (battleSession.ts:103–107, 729); joining dials exactly that id (battleSession.ts:1008).
- Protocol version constant `PROTOCOL = 5` (battleSession.ts:48), carried in every `hello`; mismatch is rejected loudly (battleSession.ts:408–417).
- Connections opened with `{ reliable: true, serialization: 'json' }` (battleSession.ts:1008) — reliable ordered SCTP data channel, JSON-serialized plain objects.

## 1. Wire protocol — exhaustive message list

All messages are plain JSON objects with discriminant field `t`. Two union types define the entire protocol.

### Client → Host (`ClientMessage`, battleSession.ts:188–193)

1. **`{ t: 'hello', name: string, key: string, proto: number }`** (battleSession.ts:189)
   - Sent: once, immediately when the DataConnection opens on any dial — first join and every reconnect (battleSession.ts:1023–1026). `name` is the display name (sanitized again host-side, battleSession.ts:245–251: whitespace-collapsed, trimmed, max 24 chars, fallback 'Player'); `key` is the tab-stable identity (battleSession.ts:114–125); `proto` is PROTOCOL.
   - Host handling (battleSession.ts:408–477): rejects on proto mismatch; rejects if lobby full (>= BATTLE_MAX_PLAYERS seated non-left, battleSession.ts:424–434); otherwise creates a seat (waiting=true if a game is running, battleSession.ts:443) or re-attaches the existing seat with the same key (battleSession.ts:447–463, cancels grace timer, clears `left` back to waiting-spectator). Replaces any old connection for that key (battleSession.ts:465–474), then `publish()`es a full state broadcast (battleSession.ts:476).

2. **`{ t: 'progress', score: number, buried: boolean, tiles: number }`** (battleSession.ts:190)
   - Sent: from a React effect on every change of running score / completion / pile size, whenever `battlePhase === 'playing'` and the game screen is up (App.tsx:1710–1717). Also self-reports `buried: true` the moment the local board freezes. Client send guarded by not-reconnecting and conn.open (battleSession.ts:940–944).
   - Host handling (battleSession.ts:492–503): ignored unless the seat exists, isn't waiting, and phase is 'playing'. Score/tiles are clamped to non-negative integers. A false→true `buried` transition calls `markOut` (elimination order stamp, battleSession.ts:497, 551–554), then `checkOver()` + `publish()`.

3. **`{ t: 'attack', count: number }`** (battleSession.ts:191)
   - Sent: when a placed word earns attack tiles — count computed locally from word length/round/growth (App.tsx:2098–2122 → `battleRef.current.sendAttack(attack)` at App.tsx:2113; client send at battleSession.ts:946–949).
   - Host handling: `relayAttack` (battleSession.ts:505–508, 520–546). Ignored unless phase==='playing', count finite and >0, sender exists and is not waiting/buried/left. Count clamped to max 50 (battleSession.ts:529). Split across all standing rivals (see §2/§3), fanned out as host→client `attack` messages, host's own share delivered locally via `events.onAttack` (battleSession.ts:536–539).

4. **`{ t: 'pong' }`** (battleSession.ts:192)
   - Sent: in reply to every host `ping` (battleSession.ts:845–851). Host consumes it only as a lastSeen refresh (any data refreshes lastSeen, battleSession.ts:392–393; pong itself is a no-op, battleSession.ts:482).

5. **`{ t: 'leave' }`** (battleSession.ts:193)
   - Sent: on deliberate exit (battleSession.ts:952–967) — best-effort, followed by peer.destroy after 150ms. Host handling (battleSession.ts:484–490): no grace period; `removePlayer` immediately. Mid-game a leaver's entry is kept, marked connected=false/left=true, `markOut` stamped, so they still place in the standings (battleSession.ts:599–605); in lobby/finished/waiting they are deleted from the roster (battleSession.ts:606–608).

### Host → Client (`HostMessage`, battleSession.ts:195–201)

6. **`{ t: 'state', state: BattleState }`** (battleSession.ts:196)
   - Sent: full-state broadcast to every open connection on EVERY state change — `publish()` (battleSession.ts:629–633) fires after: hello/seat change (476), progress (502), drop (572), grace expiry (585), removePlayer (609), start (655), stop (675), host's own progress (690). Also sent as the first message answering a successful hello (the dial resolves only after receiving the first `state`, battleSession.ts:1037–1042). There are no deltas; state is snapshot-cloned before send (battleSession.ts:282–284, 360–362).
   - `BattleState` shape (battle.ts:59–66): `{ phase: 'lobby'|'playing'|'finished', players: BattlePlayer[], game: number, winnerId: string|null }`. `BattlePlayer` (battle.ts:23–56): `{ id, name, host, score, buried, connected, left, waiting, tiles, outOrder }`.

7. **`{ t: 'start', seed: string }`** (battleSession.ts:197)
   - Sent: broadcast by host `start()` (battleSession.ts:635–657) — for the first game, restarts mid-game, and play-again after a finish (same code path; App.tsx:3024, 3435, 3466). Carries the 12-char base-36 seed minted via `randomSeed()` (rng.ts:40–46, battleSession.ts:653). Host resets all seats (scores/buried/waiting/tiles/outOrder), drops disconnected/left players from the roster, clears grace timers, resets outCounter and attackSpread, sets phase='playing', increments `game`, then broadcasts `start` followed by a `state` publish, and fires its own `onStart` (battleSession.ts:654–656). Client handling: `events.onStart(String(msg.seed))` (battleSession.ts:839–841) → App builds tile streams and starts the local game (App.tsx:751–766).

8. **`{ t: 'stop' }`** (battleSession.ts:198)
   - Sent: broadcast by host `stop()` (battleSession.ts:659–677) — "everyone to the lobby". Same roster reset as start but phase='lobby', no seed. Client handling: `onStop` (battleSession.ts:842–844) → App tears down streams and returns to lobby screen (App.tsx:768–779).

9. **`{ t: 'reject', reason: string }`** (battleSession.ts:199)
   - Sent: point-to-point (not broadcast) on a hello with wrong proto (battleSession.ts:409–417) or a full lobby (battleSession.ts:426–434); host closes the connection 250ms later. Client handling: during dial it fails the join non-retryably (battleSession.ts:1033–1036); on an established session it terminates via `fail(reason)` → onEnded (battleSession.ts:855–857).

10. **`{ t: 'attack', count: number }`** (battleSession.ts:200)
    - Sent: point-to-point to each target of a split attack, only their share (battleSession.ts:540–545). Client handling: `onAttack(Math.max(0, floor(count)))` (battleSession.ts:852–854) → App draws `count` letters from its local per-player attack stream and adds them to the rack (App.tsx:803–819).

11. **`{ t: 'ping' }`** (battleSession.ts:201)
    - Sent: broadcast every PING_INTERVAL_MS = 10s from the host's sweep timer (battleSession.ts:78, 357, 364–366). Client handling: replies `pong` and refreshes `lastHeard` (any message refreshes it, battleSession.ts:831).

There are no other message types. Unknown/malformed messages are ignored on both sides (battleSession.ts:405–406, 832–833).

## 2. Host-authority model

Host decides (all in HostSession, battleSession.ts:288–717):
- **Roster**: seat creation, seat capacity (8), name sanitization, seat re-attachment by key, waiting flag for mid-game joiners, removal (battleSession.ts:408–477, 561–610).
- **Start/stop/restart**: only the host's `start()`/`stop()` do anything; client versions are explicit no-ops (battleSession.ts:932–938). Host mints the seed (battleSession.ts:653).
- **Attack splitting & routing**: total clamped to 50, divided by `splitAttackTiles` (modes.ts:293–302: fair floor per target + remainder distributed one-each starting at rotating offset `attackSpread`, battleSession.ts:530–532), targets = standing, non-waiting, non-left, non-buried rivals (battleSession.ts:525–527). The sender never learns the split; each target only hears its own count.
- **Elimination order / standings**: `outOrder` stamped once, monotonically (outCounter, battleSession.ts:306, 551–554), on: self-reported burial (497, 686), grace expiry (583), deliberate/forced leave mid-game (604). Standings are derived purely from outOrder by `rankByElimination` (battle.ts:225–241) on every screen — the host never sends a rank, only the stamps.
- **Game over & winner**: `checkOver` (battleSession.ts:612–620) runs `battleOver`/`battleWinner` (battle.ts:194–207): decided when ≥2 non-waiting contestants and ≤1 alive (`!waiting && !buried && !left`); winner = sole survivor, `winnerId=null` on a simultaneous draw. Host flips phase to 'finished' and broadcasts.
- **Liveness**: staleness sweep, grace timers, forced drops (battleSession.ts:364–381, 561–588).

Clients decide locally (App.tsx):
- **Their own board entirely** — placement legality, dictionary checks, scoring (App.tsx:2025–2130). The host never sees a board; there is no move validation across the wire (trust-the-client model).
- **Their own elimination**: pile > BATTLE_PILE_LIMIT (25, modes.ts:203) is detected locally (App.tsx:1635–1638) and self-reported via `progress.buried` (App.tsx:1710–1717). The host merely records it.
- **Their own drips**: the 20s drip clock and batch sizes run entirely locally (App.tsx:1617–1628) — no drip message exists on the wire.
- **Attack magnitude**: attack size per placed word is computed locally (`battleAttackTiles`, modes.ts:268–277: max(0, len−3) minus absorbed-word growth, × round multiplier 1/1.5/2, App.tsx:2098–2111); the host only clamps (≤50) and splits.
- **Round progression**: each client advances its own round 1→2→3 off its own 180s clocks (App.tsx:1495–1507) — see §7.

## 3. Deterministic shared deal — zero tiles on the wire

- Seeded PRNG: xmur3 string hash → mulberry32 (rng.ts:12–36). Same seed ⇒ identical [0,1) sequence (verified battle.test.ts:21–43).
- `createTileStream(seed)` (battle.ts:146–169): a hidden crossword solution board grown word-by-word by the shared generator, always in fixed STREAM_CHUNK=5 increments (battle.ts:129, 162), with requests just draining the resulting letter sequence. Determinism contract: same seed ⇒ same opening batch and then the identical letter sequence regardless of how requests are sized (battle.ts:139–144; tests battle.test.ts:45–89 including differently-interleaved request sizes 64–75 and 1-tile attack requests 83–89).
- Per game, each client builds TWO streams from the one `start` seed (App.tsx:752–762):
  - **Main deal stream**: `createTileStream(seed)` — opening deal `stream.next(BATTLE_START_TILES)` (15 tiles, modes.ts:200; App.tsx:762) and every timed drip draws from it (`dealBonusTiles` App.tsx:1444–1466, branch at 1447–1450).
  - **Attack stream**: `createTileStream(`${seed}/attacks/${selfId}`)` (App.tsx:757–759) — seeded off the shared seed AND the receiving player's stable id, so each player has a private deterministic attack-letter sequence. An incoming attack is only a count; the receiver draws that many letters locally (App.tsx:803–807). No other party ever needs to know the letters, so no re-sync is needed.
- Drip determinism across drifting clocks: batch size is pure in the drip index — `battleDripTilesAt(dripIndex)` (modes.ts:252–255) maps index k → the round in force at (k+1)×20s → 1/2/4 tiles (modes.ts:222, 231–233) — so "drip k is drip k on every screen" and every player drains the shared stream identically, whatever the wall-clock skew (comment modes.ts:249–251; consumption App.tsx:1623–1626). NOTE: this holds because every live player takes every drip; a spectator's dead board takes no drips (App.tsx:1614–1618), which is safe only because a spectator never draws from the shared stream again.

## 4. Join codes and invite links

- Format: 5 letters from a 23-letter alphabet `ABCDEFGHJKMNPQRSTUVWXYZ` (no digits; I/L/O excluded as 1/0 lookalikes) — 6.4M codes (battle.ts:76–85). Generated with Math.random (host only).
- Normalization: trim, uppercase, strip non-letters (battle.ts:93–95); validation checks length 5 + alphabet membership (battle.ts:97–103). Tests battle.test.ts:92–118.
- Code = address: peer id `nana-battle-<code.toLowerCase()>` (battleSession.ts:103–107). Hosting claims it with the broker (battleSession.ts:729); on `unavailable-id` collision the host redraws a fresh code up to 3 retries (battleSession.ts:753–757). Joining dials that exact id (battleSession.ts:1008); the broker error `peer-unavailable` becomes "No game found with that code" and is non-retryable (battleSession.ts:256–257, 275–280).
- Invite link: `${origin}${pathname}#battle=<CODE>` (battle.ts:105–109); parsed by `codeFromHash` (battle.ts:112–117). On app load a matching hash prefills the join form, opens the battle screen, and strips the hash via history.replaceState so refreshes don't replay it (App.tsx:739–749). Lobby offers "Copy code" and "Copy invite link" buttons (BattleLobby.tsx:85–88).

## 5. Reconnection design

**Stable identity**: `playerKey()` (battleSession.ts:114–125) — `p-` + two 12-char random seeds, stored in sessionStorage key `nana.playerKey.v1` (per-tab, survives reloads; two tabs = two players). This key, not the peer id, is the seat identity (`BattlePlayer.id`, battle.ts:24–29); peer ids are throwaway (a fresh anonymous Peer per dial, battleSession.ts:982).

**Host-side seat holding**:
- Drop detection: connection `close`/`error` handlers (battleSession.ts:397–398), ICE transport watch for failed/closed (battleSession.ts:93–101, 400), and staleness sweep (silence > STALE_LINK_MS=25s ⇒ host force-closes and drops, battleSession.ts:86, 364–381).
- `dropPlayer` (battleSession.ts:561–588): mid-game (phase==='playing' and not waiting) the seat is held — `connected=false`, broadcast, and a grace timer of RECONNECT_GRACE_MS = 30s (battleSession.ts:66, 576–587). Game NEVER pauses for a drop. Grace expiry ⇒ `left=true`, `markOut` (their standing is fixed at that moment), checkOver, broadcast. Outside a game (lobby/finished/waiting) a drop just removes the player (battleSession.ts:565–569).
- Re-attach: a hello with a known key restores `connected=true`, cancels the grace timer, and — if they'd been counted out (`left`) — returns them as a waiting spectator dealt into the next game (battleSession.ts:447–463). One live connection per seat; a replaced link is closed (battleSession.ts:465–474).
- `start()`/`stop()` purge anyone disconnected or left (battleSession.ts:640, 662) — a fresh game deals in only who's actually present.

**Client-side self-healing** (`ClientSession.linkDown`, battleSession.ts:868–917):
- Triggers: conn close/error, ICE failed/closed, fatal peer error (network / peer-unavailable are tolerated as broker-only blips, battleSession.ts:820–827), staleness (no host message for >25s, checked every 10s, battleSession.ts:803–806), and visibilitychange wake-up check (stale or closed link on returning to foreground, battleSession.ts:777–786).
- Procedure: set reconnecting, fire `onReconnecting`, destroy the old peer, then loop fresh `dial()`s (each with RECONNECT_ATTEMPT_MS = 12s timeout, battleSession.ts:75, 893) with exponential backoff 2s, 4s, 8s, then 10s cap (battleSession.ts:910–911), until RECONNECT_BUDGET_MS = 115s deadline (battleSession.ts:72, 882) — deliberately far past the host's 30s grace so a late landing rejoins as spectator rather than failing. Budget exhausted ⇒ `fail('Couldn't reconnect…')` → onEnded → app goes home with a notice (App.tsx:783–798).
- Success: re-hello with the same key, new peer/conn attached, `onReconnected` + fresh state delivered (battleSession.ts:894–907). While reconnecting, the LOCAL clocks pause (only for this player — battlePaused, App.tsx:1396–1399) and progress/attack sends are silently dropped (battleSession.ts:941, 947); the ConnectionOverlay modal covers the screen (ConnectionOverlay.tsx:16–37).
- Rejoin-as-spectator: a player whose grace expired comes back `waiting=true`; the spectator view explains it and they deal into the next game (App.tsx:1592–1608; BattleSpectator.tsx:64–90).

**Initial join retry**: `joinBattle` (battleSession.ts:1056–1078) loops `dial()` attempts (JOIN_ATTEMPT_MS=12s each, min 4s) within JOIN_BUDGET_MS=30s total, 500ms between attempts; only definitive failures (`peer-unavailable`, `browser-incompatible`, host `reject`, host closed) abort immediately (battleSession.ts:275–280, 1028, 1033–1036, 1071–1073). A dial also polls the ICE state every 1s and fails fast on `failed` with a "try another network / phone hotspot" message (battleSession.ts:1013–1021). Host lobby claim has CONNECT_TIMEOUT_MS = 20s (battleSession.ts:51, 732–737).

**Host disappearance — NO host migration**: there is none. The lobby dies with the host. `leave()` on the host destroys the peer, which closes every client connection (battleSession.ts:697–701); the BattleHandle contract says "Hosts take the whole lobby down with them" (battleSession.ts:242). Clients can't distinguish a dead host from their own link failure, so they redial for up to 115s; every dial hits `peer-unavailable` (retryable, so they keep trying) or the budget expires, ending with onEnded. A host that merely backgrounds its tab keeps the lobby: it auto-reconnects to the broker on visibilitychange and on broker 'disconnected' (battleSession.ts:307–310, 341–344), and broker loss alone doesn't kill live games (only new joins), per battleSession.ts:345–351. UI-side, host leave/restart/stop prompt confirmation dialogs since they hit everyone (App.tsx:900–933, 3443–3470).

## 6. Ordering/reliability assumptions

- The protocol assumes **reliable, ordered, exactly-once** delivery per connection: PeerJS is invoked with `reliable: true` (battleSession.ts:1008) and JSON serialization; WebRTC data channels default to reliable+ordered SCTP.
- Where it matters:
  - **hello → first state handshake**: the dial resolves only when the first `state` arrives after hello (battleSession.ts:1030–1042); a reject must not be reordered after it.
  - **`start` (seed) before subsequent `state`/`attack`**: clients build tile streams on `start`; an `attack` arriving before its game's `start` would draw from the previous game's stream or be dropped (attackStream null guard, App.tsx:804–805). Ordering guarantees `start` precedes any attack of that game. Note `start` and the following `state` are separate messages relying on channel order (battleSession.ts:654–655).
  - **Monotonic state**: full-state broadcasts carry no sequence number and no acks; clients blindly adopt the latest received `state` (battleSession.ts:835–838). Correct only under ordered delivery. (GameKit port: GKMatch .reliable mode preserves order per sender, so this maps; but if any message were sent .unreliable, states could regress — add a `game`/revision check or keep everything reliable.)
  - **attack counts are fire-and-forget, no ack, no idempotency key**: a duplicated or lost `attack` silently changes the game. Loss during a client's reconnect window is accepted by design (sends while `reconnecting` are dropped, battleSession.ts:946–948; likewise progress, 941).
  - **Progress reports are stateful-latest**: only the newest matters (full values, not deltas), so loss is tolerated but reordering would resurrect old scores/unbury players — again leaning on ordering. `buried` regression is possible in principle (host tracks transitions at battleSession.ts:497) but outOrder is write-once so standings can't be corrupted (battleSession.ts:551–554).
- No message fragmentation/size concerns: the largest message is `state` with ≤8 small player records.

## 7. Timing/clock assumptions

- **There is no shared clock and no drift correction.** Every client (host included) runs its own round clock (3 rounds: 180s, 180s, then untimed final — modes.ts:213–216; App.tsx:584–590, 1495–1507) and its own 20s drip clock (modes.ts:219; App.tsx:573, 1617–1628), all off local `Date.now()` with a 250ms tick (App.tsx:1421–1428). Rounds advance independently per client; the round multiplies attack sizes (modes.ts:225, App.tsx:2110), so two drifted clients can briefly disagree on the multiplier — accepted.
- Determinism across drift is preserved only where it must be: drip letter identity is index-pure (modes.ts:249–255; §3).
- Clock pausing is local-only and only for the affected player: overlays never pause a multiplayer clock except one's own reconnection (App.tsx:1388–1399, 1405–1418). While reconnecting, that player's clocks freeze (drip + round), meaning a long reconnect skews their drip schedule relative to others — tolerated since drips are index-keyed.
- Host timers: 10s ping/sweep interval (battleSession.ts:78, 357), 25s staleness cutoff (86), 30s seat grace (66). Client: 25s staleness on host pings checked every 10s (battleSession.ts:803–806).
- The splash system holds new round clocks while announcement cards are up in solo, but in battle splashes do NOT pause clocks (App.tsx:1390–1392).

## 8. Player count limits & lobby rules

- BATTLE_MIN_PLAYERS = 2, BATTLE_MAX_PLAYERS = 8 (modes.ts:196–197). Enforcement: host turns away the 9th hello with `reject` (seated = players not `left`, battleSession.ts:424–434); Start button disabled until ≥2 seated (BattleLobby.tsx:68–69, 136–143).
- Mid-game joiners are seated `waiting: true` and spectate until the next `start` (battleSession.ts:443; battle.ts:45–46; BattleLobby.tsx:102–104 "next game").
- Lobby roster shows host chip, You chip, connection status ("reconnecting…"), and per-player game status (BattleLobby.tsx:91–116).
- Restart from results requires ≥2 present (connected, not left) (BattleResults.tsx:70–72). Host-only controls throughout: start/restart/stop (battleSession.ts:234–237, 932–938; BattleResults.tsx:82–98; BattleSpectator.tsx:126–136 — an eliminated host keeps refereeing).
- Names: client-proposed, host-sanitized to 24 chars (battleSession.ts:245–251); remembered per device in localStorage (App.tsx:342–348, 834–841).
- Elimination rule the seats enforce: pile > BATTLE_PILE_LIMIT = 25 ⇒ out (modes.ts:203, App.tsx:1635–1638); game over on last-one-standing among ≥2 contestants, draw possible (battle.ts:194–207); standings purely by reverse elimination order with competition ranking for ties (battle.ts:225–241).

## 9. Infrastructure that exists ONLY to make WebRTC work (retired by GameKit)

All of the following exists solely for signaling/NAT traversal and would be deleted outright if GKMatch/GameKit relay carried the traffic:

1. **PeerJS broker (signaling)** — default: PeerJS's free public cloud; optional self-hosted `peerjs/peerjs-server` container on port 9000 (infra/docker-compose.yml:26–33), addressed via build-time `VITE_PEER_HOST/PORT/PATH/SECURE` (battleSession.ts:135–144, .env.example:10–15). Only introductions flow through it (battleSession.ts:127–133; docker-compose.yml:6–8).
2. **Caddy** — HTTPS termination + Let's Encrypt automation in front of the broker only (infra/Caddyfile:1–10; docker-compose.yml:12–24).
3. **STUN/TURN (ICE)** — `iceConfig()` (battleSession.ts:164–181): PeerJS defaults (Google/Twilio STUN + free shared TURN) + `stun:stun.cloudflare.com:3478` + optional build-time TURN relay via `VITE_TURN_URL/USERNAME/CREDENTIAL` (additive, so quota exhaustion degrades rather than breaks — battleSession.ts:158–162). Production currently ships Metered Open Relay free-tier credentials verbatim in the JS bundle, deliberately committed (.env.production:1–14). Self-hosted alternative: coturn container with host networking, lt-cred-mech static user, ports 3478 TCP/UDP + UDP 49152–49400, quotas total-quota=100/user-quota=50/max-bps=500000, RFC1918 peer denies (docker-compose.yml:35–66; infra/README.md:51–58).
4. **Related client code retired with them**: broker option plumbing (battleSession.ts:135–186), ICE config (164–181), ICE transport watching (93–101, 1013–1021), broker-blip tolerance in error handlers (345–351, 820–827), host broker auto-reconnect (307–310, 341–344), dial/redial machinery specific to broker addressing (975–1046), unavailable-id code-collision retry (753–757). What must be REBUILT on GameKit equivalents rather than deleted: liveness (ping/pong/staleness — GKMatch has player-state callbacks but the 25s app-level staleness may still be wanted), the seat-grace/rejoin design (GameKit reconnection semantics differ; the stable playerKey maps naturally to GKPlayer.gamePlayerID/teamPlayerID), and join codes (GameKit uses invites/matchmaking instead of typed codes — the code-as-address trick has no direct analog; keep codes only if using a custom rendezvous).
5. **What stays regardless**: the entire message protocol (§1), host-authority logic (§2), seed/stream determinism (§3), referee functions (battle.ts:194–255), and the game itself remain transport-agnostic — HostSession/ClientSession are the only transport-aware classes, and BattleHandle/BattleEvents (battleSession.ts:205–243) is the clean seam to re-implement over GKMatch (host = one designated GKPlayer; clients send only to host; host sends state broadcasts to all and attack shares point-to-point via `send(to:players:dataMode:)`).

## KEY FACTS
- Protocol version PROTOCOL=5 carried in every hello; mismatch => host sends {t:'reject'} and closes (battleSession.ts:48, 408-417)
- Entire wire protocol is 11 JSON message types: client->host hello/progress/attack/pong/leave (battleSession.ts:188-193), host->client state/start/stop/reject/attack/ping (battleSession.ts:195-201)
- Star topology, host-authoritative, no server: each client holds exactly one PeerJS DataConnection to the host, opened {reliable:true, serialization:'json'} (battleSession.ts:14-20, 1008)
- Join code = host address: 5 letters from 23-letter alphabet (no digits, no I/L/O), peer id 'nana-battle-<code lowercase>'; invite link is '#battle=<CODE>' hash (battle.ts:76-117, battleSession.ts:103-107)
- Tiles never cross the wire: host broadcasts one seed per game ({t:'start',seed}); every client grows the identical deal via createTileStream(seed) — xmur3+mulberry32 PRNG, hidden crossword grown in fixed 5-tile chunks, request-size independent (rng.ts:12-36, battle.ts:129-169)
- Attacks travel as counts only: sender computes size locally (len-3 minus absorbed growth, x round multiplier 1/1.5/2, modes.ts:268-277), host clamps to 50 and splits via splitAttackTiles across standing rivals with rotating remainder (battleSession.ts:520-546, modes.ts:293-302), receiver draws letters from private stream seeded `${seed}/attacks/${selfId}` (App.tsx:757-759, 803-807)
- State sync is full-snapshot broadcast of BattleState on every change, no deltas, no seq numbers, no acks — relies entirely on reliable ordered delivery (battleSession.ts:629-633, 835-838)
- Stable per-tab identity playerKey in sessionStorage 'nana.playerKey.v1' is the seat key; peer ids are throwaway per dial (battleSession.ts:114-125)
- Reconnect budgets: host holds a dropped mid-game seat for RECONNECT_GRACE_MS=30s (then left=true + outOrder stamped); client redials with 2/4/8/10s backoff for RECONNECT_BUDGET_MS=115s — deliberately past the grace so late rejoiners land as waiting spectators for the next game (battleSession.ts:66-75, 561-588, 868-917)
- Heartbeat: host broadcasts {t:'ping'} every 10s, clients reply pong; either side treats >25s silence (STALE_LINK_MS) as a dead link; host also watches ICE failed/closed states (battleSession.ts:78-101, 357-381, 803-806)
- NO host migration: host leave/crash destroys the peer and takes the lobby down; clients burn their 115s redial budget against 'peer-unavailable' then get onEnded (battleSession.ts:242, 697-701)
- Clients self-report elimination: pile > BATTLE_PILE_LIMIT=25 detected locally, sent as progress.buried; host stamps write-once outOrder (1,2,3...) and standings are pure reverse elimination order (App.tsx:1635-1638, battleSession.ts:551-554, battle.ts:225-241)
- Game over = >=2 non-waiting contestants and <=1 alive (!waiting && !buried && !left); winnerId null on draw; host flips phase to 'finished' and broadcasts (battle.ts:194-207, battleSession.ts:612-620)
- No shared clock, no drift handling: each client runs its own 180s round clocks and 20s drip clock off local Date.now(); drip letter batches stay identical across drift because size is pure in drip index (modes.ts:249-255, App.tsx:1489-1507, 1617-1628)
- Player limits: 2-8 (BATTLE_MIN/MAX_PLAYERS, modes.ts:196-197); 9th hello rejected host-side; mid-game joiners seated waiting:true until next start (battleSession.ts:424-443)
- Host start()/stop() purge disconnected/left players, reset all seats, reset outCounter+attackSpread; start increments state.game and mints a fresh 12-char base-36 seed (battleSession.ts:635-677, rng.ts:40-46)
- Join flow: dial resolves only after hello answered by first {t:'state'}; joinBattle retries stalled dials (12s each) within a 30s budget, failing fast only on peer-unavailable/browser-incompatible/reject (battleSession.ts:975-1078)
- While a client is reconnecting its progress/attack sends are silently dropped and only its own local clocks pause; the battle never pauses for anyone (battleSession.ts:940-949, App.tsx:1388-1399)
- Infra retired by GameKit: PeerJS public/self-hosted broker + Caddy HTTPS + STUN/TURN (PeerJS defaults + Cloudflare STUN + Metered free-tier TURN creds shipped in .env.production, or self-hosted coturn per infra/docker-compose.yml) — all exist solely for WebRTC introductions and NAT traversal (battleSession.ts:127-186, infra/*)
- Clean porting seam: BattleHandle/BattleEvents interfaces (battleSession.ts:205-243) are the only surface App.tsx touches; HostSession/ClientSession are the only transport-aware code; battle.ts is pure and transport-agnostic

## RISKS
- Ordering dependency: 'start' (seed) then 'state' are sent as two separate messages relying on channel order (battleSession.ts:654-655); on GameKit, send everything GKMatch .reliable (per-sender ordered) or add a game/revision counter — any .unreliable use could regress full-state snapshots or deliver attacks before their game's seed
- GameKit has no analog for code-as-address: the join code doubling as the PeerJS peer id (battleSession.ts:103-107) disappears; typed codes/invite links must be replaced by GKMatchmaker invites or a custom rendezvous, and BattleMenu/BattleLobby UI assumes typable codes
- Stable identity mapping: sessionStorage playerKey is per-tab; GameKit's gamePlayerID is per-Apple-ID, so 'two tabs = two players' (battleSession.ts:109-113) and rejoin-with-same-key semantics need rethinking — GKMatch also auto-handles reconnects differently, and the 30s-grace/115s-budget machinery would need to be rebuilt around GKMatchDelegate player state changes rather than deleted
- Trust-the-client model: scores, burial, and attack sizes are all client-computed and unvalidated by the host (App.tsx:1710-1717, 2098-2113; host only clamps attacks to 50 at battleSession.ts:529) — fine among friends, but a GameKit port to a wider audience inherits the cheatability
- No host migration: host death ends the lobby for everyone (battleSession.ts:697-701); clients spend up to 115s redialing a gone host before giving up — a GameKit port should detect host departure via GKMatch player-state callbacks and fail fast (or add migration, which the current protocol has no support for)
- Determinism must be preserved bit-for-bit if any platform mixes clients: the deal depends on xmur3/mulberry32 float arithmetic and the exact generator word order (rng.ts:12-36, battle.ts:146-169, plus generator.ts/commonWords) — a Swift reimplementation must replicate Math.imul/uint32 semantics and the identical word pool, or web and iOS clients can never share a game
- Attack messages are fire-and-forget with no idempotency key; drops during reconnect windows silently lose attacks by design (battleSession.ts:946-948) — acceptable today, but worth noting before adding any retry layer that could duplicate them
- Round multiplier divergence: rounds advance on each client's local clock (App.tsx:1495-1507), so drifted clients apply different attack multipliers near round boundaries — accepted in the current design; do not 'fix' by trusting one clock without also re-keying drip sizing
- State broadcasts include every player's data to everyone (full BattleState, battleSession.ts:629-633); harmless here, but note names are the only user content and are sanitized host-side only (battleSession.ts:245-251)
- The visibilitychange/wake healing paths (battleSession.ts:307-310, 777-786) are browser-specific; iOS backgrounding suspends GKMatch sessions entirely — the resume-from-background story must be redesigned, not ported
- TURN credentials are deliberately committed in .env.production (Metered free tier) and ship in the JS bundle; if any web build remains alongside the GameKit port, rotating/retiring them is a manual dashboard task (.env.production:1-14, infra/README.md:96-100)
## 10. Apple-only additions (protocol v6 and v7)

Documented in `apple/Packages/WordNet/Sources/WordNet/Protocol.swift`; summarised here so
this appendix stays the one place the whole wire is described.

- **v6 — `host`.** `{ t: 'host', proto }`, host → client. A GKMatch formed from a party
  code is a mesh with no marked owner, so the lobby's creator announces itself on match
  formation and again to every later connection; a client that hears nothing for 3s falls
  back to the lowest player id.
- **v7 — Occupy.** A second game the same lobby can play (`BattleState.mode`, defaulting
  to `battle` when absent), with the shared board riding in every `state` snapshot as
  `BattleState.occupy` (`OccupyState`: size, seats, board, owners, opened, scores,
  settledAt, end). Three messages:
  - `{ t: 'place', serial, placement }` client → host. `placement` is the outcome —
    `tiles` (new cell → letter) and `borrowed` (the gap squares) — not the picks. The
    host runs `occupyApply` (WordCore) against its board and dictionary.
  - `{ t: 'placed', serial }` host → sender, sent **after** the `state` that carries the
    word, so a sender's optimistic copy is never taken back between the two.
  - `{ t: 'refused', serial, reason }` host → sender. The sender takes the word back off
    its board and returns the letters.

  Scores are the board's, so no `progress` reports travel in this mode. The clock and the
  stall rule are the host's alone (`occupyEnd`); each screen shows its own reading of
  them from the moment `start` arrived. Seats are capped at four; `hello` past that is
  rejected with "That game is full."
