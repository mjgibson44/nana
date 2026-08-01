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
plain serializable data. When multiplayer arrives, the same modules can run
on the server: deal one shared pile, validate each player's board
authoritatively, and sync boards as plain `TileMap` objects over a socket.

## Game modes

Picked from the splash screen (`src/components/HomeScreen.tsx`); the rules live
in `src/game/modes.ts`.

- **Solo Puzzle** — the classic five-level climb, no clock.
- **Solo Timed** — the same climb against the clock: 3:00 for level 1, 2:00
  for level 2, and 15 seconds less for each level after. Out of time is game
  over.
- **Endless** — no levels. 2:00 to work the starting 20 tiles, then 3 more
  tiles arrive every minute. Clearing the pile pays a 25-point bonus and more
  tiles (10 the first time, 3 after). Loose tiles — unplaced or not validly
  connected — are your health bar: reach 20 and you're buried.

A first-run "How to play" tutorial pops up on entering a game and then stays
out of the way (a localStorage flag remembers it's been seen).

## Roadmap

- [x] Single-player: 20-tile solvable deal, drag & drop, live validation
- [x] Timed and endless ("peel"-style) modes
- [ ] Hints powered by the generator's known solution
- [ ] Multiplayer: shared pile, live opponent boards, first-to-finish wins
