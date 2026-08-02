# 🍌 Nana

A Bananagrams-style word game for the web. You're dealt a pile of letters and
race to arrange **all** of them into a single connected crossword of valid
words.

## Playing

```bash
npm install
npm run dev     # start the dev server
npm test        # run unit tests
npm run build   # type-check + production build
```

- **Drag** tiles from the pile at the bottom onto the board to build words.
- Drag tiles between board cells to rearrange, or drag them back down to the
  pile (double-click/double-tap a placed tile to send it back instantly).
- Every horizontal and vertical run of 2+ letters is checked live against a
  ~173k-word dictionary (ENABLE). Invalid words turn **red**, loose tiles turn
  **amber**, valid words get a **green** edge.
- To win, place all 20 tiles so that every word is valid and everything
  connects into one group — the status bar goes full banana. 🍌

## How the letters are dealt (solvability guarantee)

Random letters make miserable Bananagrams hands, so the generator
(`src/game/generator.ts`) works backwards: it **builds a real hidden
crossword** from a pool of ~5,000 common English words — each new word
crossing an existing one, exactly like a finished board — until it uses
exactly 20 tiles. You're dealt those letters, shuffled.

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
    dictionary.ts       #   word list loading/parsing
    commonWords.ts      #   generation word pool (subset of the dictionary)
  components/           # Grid, Rack (pile), StatusBar
  App.tsx               # game state + pointer-based drag & drop
public/dictionary.txt   # ENABLE word list, fetched at runtime
```

Everything under `src/game/` is deliberately framework-free and operates on
plain serializable data — which is exactly what lets Endless Battle run with
**no game server at all**.

## Multiplayer (Endless Battle)

- `src/game/rng.ts` — a tiny seeded PRNG (xmur3 + mulberry32) that slots into
  the generator's injectable `rng` parameter.
- `src/game/battle.ts` — the pure battle brain: join codes, the shared tile
  stream, rankings, and the referee that decides when a battle is over.
- `src/net/battleSession.ts` — WebRTC plumbing via PeerJS. The host's browser
  is the authority: it owns the roster, starts/stops games, aggregates
  scores, and broadcasts state. The join code doubles as the host's peer id,
  so joining is just dialing `nana-battle-<code>`.

Tiles are never sent over the wire. The host shares one random seed per game
and every client grows the identical deal from it: the generator builds the
same hidden crossword batch by batch because its RNG, word pool, and call
sequence match everywhere. Every batch after the opening one is the same
size (a timed drip and a pile-clear both deal 5), so player boards can
diverge freely while batch *N* stays identical for everyone.

Signaling defaults to PeerJS's free public cloud; only introductions run
through it — gameplay flows peer to peer. To use your own broker (e.g.
`npx peer --port 9000`), set `VITE_PEER_HOST` (and optionally
`VITE_PEER_PORT`, `VITE_PEER_PATH`, `VITE_PEER_SECURE=false`) at build time.

## Game modes

Picked from the splash screen (`src/components/HomeScreen.tsx`); the rules live
in `src/game/modes.ts`.

- **Solo Puzzle** — the classic five-level climb, no clock.
- **Solo Timed** — the same climb against the clock: 3:00 for level 1, 2:00
  for level 2, and 15 seconds less for each level after. Out of time is game
  over.
- **Endless** — no levels. 2:00 to work the starting 20 tiles, then 5 more
  tiles arrive on a clock that keeps tightening. Clearing the pile pays a
  25-point bonus and 5 more tiles. Loose tiles — unplaced or not validly
  connected — are counted against the limit in the header: green while
  comfortable, orange near 20, red once you're over. Going over the limit
  doesn't end the game by itself; still being over when the round's clock
  runs out is what buries you. The first move that takes you over gets a
  one-time warning spelling that out (solo stops the clock to read it).
- **Endless Battle** — Endless, against your friends. One player hosts a
  lobby and shares a 5-letter code (or an invite link that carries it);
  everyone enters a name to join. Every player fights the identical game:
  the same starting tiles, and the same letters in every batch after —
  however they earn them. Your live position sits in the header beside the
  clock, and between rounds a five-second scoreboard shows the whole field.
  Being buried knocks you out but the race runs on; the battle ends when
  everyone is buried — or the moment the last player standing is already
  strictly ahead, since nothing can change the outcome. Highest score wins,
  and the final standings name the champion. The host can restart the game
  or pull everyone back to the lobby at any time, and after a finish chooses
  between another game and the lobby. Nothing one player does pauses a
  battle (everyone's clock must run as one), so the limit warning shows with
  the clock still ticking.

A first-run "How to play" tutorial pops up on entering a game and then stays
out of the way (a localStorage flag remembers it's been seen).

## Roadmap

- [x] Single-player: 20-tile solvable deal, drag & drop, live validation
- [x] Timed and endless ("peel"-style) modes
- [x] Multiplayer: Endless Battle — shared deal from one seed, lobbies with
      codes/invite links, live standings, host controls, final rankings
- [ ] Hints powered by the generator's known solution
- [ ] Live opponent boards (spectate other players' crosswords mid-battle)
