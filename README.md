# Word

A crossword tile race for the web. You're dealt a pile of letters and race to
arrange **all** of them into a single connected crossword of valid words.

The UI is a clean black-and-white theme with light, dark, and follow-the-system
modes — pick yours on the Settings screen (from the home page, or the menu in
the top-right corner of any game).

## Playing

```bash
npm install
npm run dev     # start the dev server
npm test        # run unit tests
npm run build   # type-check + production build
```

- **Type** a word (or tap tiles in the pile), then tap an empty square to
  place it — on a phone you can also press and hold the board to drag the
  word's preview around, and let go where it should land.
- **Drag** individual tiles from the pile onto the board to build words by
  hand, drag them between cells to rearrange, or drag them back down to the
  pile (double-click/double-tap a placed tile to send it back instantly).
- Every horizontal and vertical run of 2+ letters is checked live against a
  ~173k-word dictionary (ENABLE). Invalid words turn **red**, loose tiles turn
  **amber**, valid words go **green**.

## How the letters are dealt (solvability guarantee)

Random letters make miserable hands, so the generator
(`src/game/generator.ts`) works backwards: it **builds a real hidden
crossword** from a pool of ~5,000 common English words — each new word
crossing an existing one, exactly like a finished board — until it uses
exactly the tile count wanted. You're dealt those letters, shuffled.

That means every deal is solvable *by construction*: at least one fully
valid, fully connected arrangement is known to exist (the generator holds on
to it as `puzzle.solution`, which can later power hints). And because the
letters come from several ordinary overlapping words, there are typically
many other solutions too.

## Architecture

```
src/
  game/                 # pure TypeScript, no DOM/React — unit tested
    types.ts            #   board = plain serializable Record<"row,col", letter>
    board.ts            #   word extraction, dictionary + connectivity validation
    generator.ts        #   crossword-construction letter dealing
    modes.ts            #   the rules: Endless pacing, Duel rounds and attacks
    battle.ts           #   multiplayer brain: codes, shared deal, referees
    dictionary.ts       #   word list loading/parsing
    commonWords.ts      #   generation word pool (subset of the dictionary)
  net/battleSession.ts  # WebRTC plumbing, reconnection failsafes
  components/           # Grid, Rack (pile), lobby screens, overlays
  theme.ts              # light / dark / system preference
  App.tsx               # game state + pointer-based drag & drop
public/dictionary.txt   # ENABLE word list, fetched at runtime
```

Everything under `src/game/` is deliberately framework-free and operates on
plain serializable data — which is exactly what lets multiplayer run with
**no game server at all**.

## Game modes

Picked from the home screen (`src/components/HomeScreen.tsx`); the rules live
in `src/game/modes.ts`.

- **Endless** — no levels. 2:00 to work the starting 20 tiles, then batches
  land on a tightening clock: five rounds of 5 tiles every 45 seconds, five
  rounds of 5 tiles every 30 seconds, then 7 tiles every 30 seconds forever
  after. Clearing the pile pays a 25-point bonus and 5 more
  tiles. Loose tiles — unplaced or not validly connected — are counted
  against the limit of 20 in the header: green while comfortable, orange
  near the limit, red once you're over. Going over doesn't end the game by
  itself; still being over when the round's clock runs out is what buries
  you.
- **Endless Battle** — Endless, against your friends. One player hosts a
  lobby and shares a 5-letter code (or an invite link that carries it);
  everyone enters a name to join. Every player fights the identical game:
  the same starting tiles, and the same letters in every batch after —
  however they earn them. Your live position sits in the header beside the
  clock, and between rounds a five-second scoreboard shows the whole field.
  Being buried knocks you out but the race runs on; the battle ends when
  everyone is buried — or the moment the last player standing is already
  strictly ahead. Highest score wins.
- **Duel** — head-to-head for exactly two players, through the same
  host/join lobby flow. Both duellists draw the identical letters. A placed
  word is **permanent** — no moving, no taking back — and only real words
  are allowed down. Every word you place sends tiles to your opponent: one
  per letter past three (4 letters → 1 tile, 5 → 2, …). Three rounds turn
  the screw: rounds one and two last 3:00, with attacks at ×1 then ×1.5 and
  a drip of 1 then 2 tiles every 20 seconds; the final round has no clock,
  ×2 attacks, and 4 tiles every 20 seconds. Let your pile exceed 25 tiles —
  for any reason, at any moment — and you lose. Last one standing wins.
- **Tutorial** — a guided two-step walkthrough: place your first word, then
  cross a placed word using the gap tile. No clock, no pressure.

A "How to play" reference pops up before the first game and stays available
from the menu afterwards.

## Multiplayer (Endless Battle & Duel)

- `src/game/rng.ts` — a tiny seeded PRNG (xmur3 + mulberry32) that slots into
  the generator's injectable `rng` parameter.
- `src/game/battle.ts` — the pure multiplayer brain: join codes, the shared
  tile stream, rankings, and the referees that decide when a battle or duel
  is over.
- `src/net/battleSession.ts` — WebRTC plumbing via PeerJS. The host's browser
  is the authority: it owns the roster, starts/stops games, aggregates
  scores, relays duel attacks, and broadcasts state. The join code doubles as
  the host's peer id, so joining is just dialing it.

Tiles are never sent over the wire. The host shares one random seed per game
and every client grows the identical deal from it: the generator builds the
same hidden crossword batch by batch because its RNG, word pool, and call
sequence match everywhere. Even duel attacks travel as a count — the receiver
draws the letters from a stream seeded off the shared seed and their own id.

### Connection failsafes

Multiplayer assumes phones will be phones:

- Every player carries a **stable identity** (a per-tab key), so a dropped
  WebRTC link can be re-attached to the same seat — score, board and all.
- The **host forgives drops**: a player who vanishes mid-game is
  "reconnecting" for a two-minute grace period while the game **pauses for
  everyone**, with an overlay naming who it's waiting for. Only when the
  grace runs out (or they deliberately left) does the game move on.
- **Clients heal themselves**: on any loss — or on returning from an app
  switch to find the link stale — the client redials with backoff until the
  grace period is spent. A heartbeat tells live links from dead ones, so a
  quick app switch doesn't disconnect you at all.

Signaling defaults to PeerJS's free public cloud; only introductions run
through it — gameplay flows peer to peer. To use your own broker (e.g.
`npx peer --port 9000`), set `VITE_PEER_HOST` (and optionally
`VITE_PEER_PORT`, `VITE_PEER_PATH`, `VITE_PEER_SECURE=false`) at build time.

## Roadmap

- [x] Single-player: solvable deals, drag & drop, live validation
- [x] Endless ("peel"-style) mode
- [x] Multiplayer: Endless Battle — shared deal from one seed, lobbies with
      codes/invite links, live standings, host controls, final rankings
- [x] Duel mode: permanent words, attack tiles, escalating rounds
- [x] Light/dark/system theme and a settings screen
- [x] Reconnection grace, auto-redial, and pause-on-disconnect
- [ ] Hints powered by the generator's known solution
- [ ] Live opponent boards (spectate other players' crosswords mid-battle)
