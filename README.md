# Word

A crossword tile race for the web. You're dealt a pile of letters and race to
arrange **all** of them into a single connected crossword of valid words.

The UI is a clean black-and-white theme with light, dark, and follow-the-system
modes — pick yours on the Settings screen (from the home page, or the menu in
the top-right corner of any game), which is also where **Game sound** is
switched on and off.

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
  pile (double-click/double-tap a placed tile to send it back instantly —
  except a word's first letter, which turns the whole word instead).
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
    modes.ts            #   the rules: Blitz pacing (regular/fast), Puzzle boards and variants, Duel rounds
    battle.ts           #   multiplayer brain: codes, shared deal, referees
    dictionary.ts       #   word list loading/parsing
    commonWords.ts      #   generation word pool (subset of the dictionary)
    sounds.ts           #   the four game sounds, synthesized; the on/off pref
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

- **Blitz** (Endless) — no levels, at a pace picked on the way in. **Regular**:
  2:00 to work the starting 20 tiles, then batches land on a tightening clock —
  five rounds of 5 tiles every 45 seconds, five rounds of 5 tiles every 30
  seconds, then 7 tiles every 30 seconds forever after. **Fast**: the same game
  on a much shorter fuse — 1:00 for the starting 20 tiles, then a 15-second
  round forever: 3 tiles a round to begin with, growing by one every 8 rounds
  until batches top out at 10. At either pace, clearing the pile pays a
  25-point bonus and 5 more tiles, and loose tiles — unplaced or not validly
  connected — are counted against the limit of 20 in the header: green while
  comfortable, orange near the limit, red once you're over. Going over doesn't
  end the game by itself; still being over when the round's clock runs out is
  what buries you.
- **Puzzle** — no clock and no losing. Played on a fixed board with real edges,
  chosen on the way in: 9×9, 13×13 or 19×19. You get 20 tiles, the header keeps
  score and counts the time elapsed, and the **Finish** button in the top right
  ends the game whenever you decide you're done. Two puzzles, picked before the
  board is:
  - **Puzzle Solve** — nothing is settled. Tiles move, words come apart, and
    weaving every last tile into one connected crossword pays the 25-point
    clear bonus and deals 20 more, for as long as you like.
  - **Puzzle Flow** — every word you place is **locked** where it lands, so —
    exactly as in a Duel — only real words are allowed down, there's no undo,
    and nothing can be dragged, turned or taken back. In exchange the tiles the
    word spent come straight back, so the pile stands at 20 for as long as the
    board has room. The new letters are grown off the board as it now stands
    (`extendPuzzle`), so each one is known to have a home somewhere on a board
    that can't be rearranged; once the board is too congested to grow off, they
    fall back to a plain draw. A pile that always refills is never cleared, so
    the clear bonus simply isn't one of Flow's rewards — the score is the words
    on the board when you press Finish.
- **Survival** (Endless Battle) — Blitz Regular, against your friends. Every
  player shares one deal, so Survival always runs at the regular pace. One player hosts a
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
  per letter past three (4 letters → 1 tile, 5 → 2, …). Extending a word
  already on the board sends only the difference — what the longer word is
  worth minus what the old one already was. Three rounds turn
  the screw: rounds one and two last 3:00, with attacks at ×1 then ×1.5 and
  a drip of 1 then 2 tiles every 20 seconds; the final round has no clock,
  ×2 attacks, and 4 tiles every 20 seconds. Let your pile exceed 25 tiles —
  for any reason, at any moment — and you lose. Last one standing wins.
- **Tutorial** — a guided three-step walkthrough, scripted in
  `src/game/tutorial.ts`: SOLAR spelled out in the pile to place, then ORBIT
  dealt an R short so it has to cross the one already down, then POLE dealt two
  short so it has to borrow the board's O with a gap tile — that last step won't
  accept the word played any other way. Each step deals only its own tiles and
  waits for its own word, calling it out over the board as it lands; "Skip" (in
  the header, beside the way out) plays a step's word for you. There is no clock
  and no score. With all three words down, the pile and its tools give their
  room over to a single "Finish Tutorial" button, leaving the finished crossword
  on screen to be looked at.

### Meeting the game for the first time

Two things front a first game, each shown once and never again (remembered in
`src/game/onboarding.ts`):

- The **tutorial**, before anybody's very first game. Pick any mode on the home
  screen and the tutorial is offered first — on its own card, so nobody is
  dropped into a lesson unannounced — with that mode waiting behind it.
  *Continue* starts it; *Skip* goes straight to the game. Being offered it is
  what counts as having seen it, so skipping means never being asked again.
  Finishing it, skipping every step, or shutting it with the X all lead the same
  way: on to the game you picked. Pressing **Tutorial** on the home screen
  deliberately skips the card and starts the lesson — a card asking whether
  you'd like the tutorial you just asked for would only be reading the button
  back to you — and it counts as the offer, so your first game won't raise it.
- A one-card **explainer** for each mode — what it is and its three headline
  rules — the first time you open that door. It's the last thing between the
  choice and the game, which is why there's no ⓘ on the mode buttons: the
  details arrive when they're wanted, unasked.

The fuller "How to play" reference never interrupts; it waits on the home screen
and in the in-game menu.

### Sound

Seven cues, in `src/game/sounds.ts`. Nothing is loaded from disk: each one is a
handful of oscillators drawn on the fly through the Web Audio API, so the whole
soundtrack costs no bytes and no requests.

Five play while a game runs, all of them short enough that a fast player never
hears one land on top of the last:

- A quiet **tick** for each of the last three seconds of an Endless round, so the
  tiles about to land are heard coming without watching the clock. It follows
  the clock rather than a timer of its own, so a paused round (a splash is up)
  goes quiet.
- A rising **three-note chime** whenever tiles land in your own pile, in any
  mode — a timed batch, a board-clear reward, a tutorial step's letters.
- A low, **falling growl** for tiles a Duel opponent sends you: incoming trouble
  should never sound like the arrival of tiles you earned.
- A two-note **click** as a word goes down on the board. Every road to a landing
  runs through `commit`, so a dragged tile and a typed word sound alike.
- A two-tone **alarm** the moment the loose pile goes over the limit, along with
  the header's gauge turning red. It's a warning rather than a verdict — the
  round's remaining seconds are the deadline to dig back under — and digging
  under re-arms it, so a player riding the limit is warned every time they cross
  it. (A Duel pile over *its* limit isn't a warning at all: it's the loss, and it
  sounds like one.)

Two end a game, and may take their time since nothing follows them:

- Four notes **falling away** whenever a game ends against you — buried, or out
  of time. It lives in `finishGame`, the one way any game ends, so every road to
  a loss sounds the same.
- The same shape **climbing** for the player who takes a multiplayer game.
  `battleWinners` in `src/game/battle.ts` decides who that is — top score in a
  Survival (all of them, on a tie), the surviving duellist in a Duel — and the
  results screen names the winner from the same function, so the fanfare and the
  headline can never disagree.

**Game sound** on the Settings screen silences the lot, remembered in
`localStorage`. While it's off no audio context is ever built at all; switching
it on plays a sound, both to demonstrate the switch and because that click is
the user gesture browsers want before they will let audio start.

## Multiplayer (Survival & Duel)

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
- [x] Blitz — endless ("peel"-style) play at a regular and a fast pace
- [x] Puzzle — untimed play on a fixed 9×9/13×13/19×19 board, two ways: Solve
      (+20 tiles per clear) and Flow (locked words, pile refilled to 20)
- [x] Multiplayer: Survival (Endless Battle) — shared deal from one seed, lobbies with
      codes/invite links, live standings, host controls, final rankings
- [x] Duel mode: permanent words, attack tiles, escalating rounds
- [x] Light/dark/system theme and a settings screen
- [x] Game sounds — synthesized cues for ticks, tiles, attacks, words and endings
- [x] Reconnection grace, auto-redial, and pause-on-disconnect
- [ ] Hints powered by the generator's known solution
- [ ] Live opponent boards (spectate other players' crosswords mid-battle)
