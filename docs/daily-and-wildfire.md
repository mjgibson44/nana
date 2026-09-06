# Two new modes: the Daily, and Wildfire

*Written 2026-09-06 against `a02d5a5`. Design, not yet a build plan — the
options rejected along the way are in `daily-mode-ideas.md`.*

Two things came out of the brainstorm worth building, and they're deliberately
opposite. The **Daily** is quiet, finite and comparable: one board a day,
everyone starting from the same position, scored on how few words you needed.
**Wildfire** is loud: a Solo variant where the board fights back. One is for
thinking, the other for reflexes, and they share almost no code — which is a
feature, since it means they can be built and shipped independently.

---

## Part 1 — The Daily: a seed word and three targets

### Why these two ideas are really one

Target cells and a seed word looked like two modifiers that happened to
combine. They aren't: **the seed word is what makes target cells possible at
all.**

The board has no origin. `boardBounds` grows the playable rectangle around
whatever has been played, cell keys run negative quite happily, and the
generator `normalize`s its hidden solution before dealing. On an empty board
"the target is at row 3, column 7" means nothing — you build your crossword
wherever you like, so any single target is covered trivially by starting on top
of it, and a set of targets is only a statement about the *shape* between them.

Put a word down first and the coordinate system is pinned. Now a target is a
real place: *four to the left of the seed word and two down*. Reaching it means
building in a direction you didn't choose, with letters you were given. That is
the spatial pressure Solo has never had, and it costs one already-placed word to
create.

It buys a second thing too. Today every daily player gets the same letters but
their boards diverge on the first move, because that move can go anywhere. With
a seed word, two players' boards are the *same position* — comparable the way
two chess games from the same opening are comparable, and worth looking at
side by side after the fact.

### The construction

The generator already does the hard part. Everything below falls out of one
call:

1. `generatePuzzle(commonWords, tileCount, seededRng(daily.seed))` returns a
   hidden `solution` (a `TileMap`) and the `sourceWords` it was built from.
2. **The seed word** is one of `sourceWords` — pick a longer, central one — laid
   on the board at the position it occupies in the solution.
3. **The deal** is the solution's remaining letters, shuffled: exactly the tiles
   needed to finish the crossword that's been started for you.
4. **The targets** are three cells of the solution the seed word doesn't cover,
   chosen far apart (Chebyshev distance, and ideally one near / one mid / one
   far) so the puzzle spans the board rather than huddling.
5. **Par** is `sourceWords.length` — the hidden solution's word count.

Every guarantee the game already makes survives, and two new ones come free:

- The targets are **reachable**, because they're cells of a crossword the deal
  is known to build.
- Par is **achievable**, because the hidden solution achieves it — and
  **beatable**, because the letters come from several ordinary overlapping
  words and there are normally many other arrangements, some of them tighter.

Par isn't a tuned constant, in other words. It's derived from the puzzle, which
means it's honest on every deal and needs no balancing pass.

**One trap.** `Puzzle.solution` is `null` when the builder gives up and falls
back to disjoint word sampling. Everything above depends on the solution
existing, so the daily must reject that deal and re-roll (a counter mixed into
the seed, kept in the daily's own derivation so every client re-rolls
identically) rather than deal a board it can't place targets on.

### Scoring: fewest words, and the tension that makes it interesting

Score the finished board on **how many words it took**, low is good, against
par. Golf.

What makes this better than it sounds is that it fights the scoring already in
the game. `wordScore` is triangular in length, and every valid run pays — so
points reward a densely interlocked board with *many* runs, while golf rewards
*few* commits. Those pull against each other productively: the best move is one
commit that creates several runs at once. A word laid across three existing
words is four new runs for one stroke. "Fewest words, most points" is a real
optimization with a real skill ceiling, and it's the first time this game has
had one.

**The decision to make is what a take-back costs**, and it decides what kind of
mode this is:

- **A take-back costs a stroke.** True move-limited golf. Tense, and it
  punishes exploring — which on a one-attempt, no-clock daily is punishing the
  exact behaviour a daily should reward.
- **A take-back refunds its stroke** — so the counter is just the number of
  words standing on your final board. Fiddling is free; the player who thinks
  harder wins, not the one who commits faster. Sudoku with an eraser.

**Recommend the second.** The score becomes a property of the artifact you
finished rather than of the journey you took, which is easier to explain,
impossible to game, and calm — and calm is what distinguishes this from Solo.
Then give the purists their version for free: a **"no take-backs" star** on the
share card, tracked but not scored. It costs a boolean and it settles the
argument without imposing either answer on everyone.

### Finishing, and the two-tier result

**The puzzle is complete when all three targets are covered.** Leftover tiles
are allowed — you simply haven't used them.

Placing every tile as well pays the `ALL_TILES_BONUS` that already exists, and
earns the second tier of the result. That keeps the game's signature
satisfaction (get every tile down) as an ambition rather than a requirement,
and it means **the daily cannot be failed** — only taken slowly, or finished
untidily. For one attempt a day with no clock, that's the right shape: the
tension lives in your number against par and against your friends', not in a
loss you can't retry.

The share card writes itself:

```
Time Tiles · Sep 6
🎯🎯🎯 in 7  (par 9)  ⭐ every tile
```

…plus, optionally, an emoji minimap of the board's shape, which is the part
people actually paste.

### The leaderboard has to be one number

Game Center recurring leaderboards take a single `Int64`, and this score is
two-dimensional. Either:

- **Composite, commits first**: `(cap − commits) × 100000 + points`, with `cap`
  a fixed ceiling well above any plausible word count. Sorts by the thing the
  mode is actually about, and uses points as a natural tiebreak.
- **Points, with commits as a badge.** Simpler, but then the leaderboard isn't
  measuring the mode.

Recommend the composite. Whichever is chosen must be pinned before the first
submission — a leaderboard's scores can't be reinterpreted later.

---

## Part 2 — Wildfire: a Solo variant where the board fights back

Endless, plus fire. The letters keep coming exactly as they do now; the
difference is that the board itself starts costing you something.

### The simplification that makes it work: no health bar

The original sketch had fire draining health. It doesn't need to, and the mode
is much better without it.

**A burnt tile comes back to your pile.** Fire destroys a tile, the word it was
part of breaks, and the letter returns loose. Loose tiles are already the thing
that kills you in Solo — the gauge in the header, the alarm in `sounds.ts`, the
verdict at the end of the round. So fire kills you *through a rule players
already know*, with no second failure state, no new gauge, and nothing new to
explain on the card.

It also makes fire's cost legible in the currency the player is already
watching. "Three tiles burned" doesn't need a number; it's three more on the
gauge, and they can feel it.

### One heartbeat

Fire runs on the round clock that already exists (`endlessDripSeconds`). At each
round boundary, in order:

1. Tiles land.
2. Fire spreads, and anything that's been burning a full round burns away.
3. The loose-tile verdict is checked.

Everything therefore gets **exactly one round of grace**: a cell that ignites
this round burns at the end of the next one. Predictable, learnable, and no new
timer — the mode has one pulse with three consequences instead of two clocks
players have to track separately.

Escalation comes for free too: ignitions per round grow the way
`endlessDripTiles` grows the batch. Same curve, one more small function.

### The rules

**Ignition** picks cells adjacent to tiles already on the board. This isn't
flavour — it's the fairness rule. A fire in open space has no legal answer,
because the board must stay connected and there's nothing to build off; every
fire must start somewhere you could actually reach. Uniform choice among
eligible cells is enough, and it naturally concentrates fire where your board
is dense, which is where the interesting decisions are.

**Extinguishing** is placing a tile on the burning cell *or next to it*.
Requiring exact coverage means dying to letters you don't hold; adjacency is
forgiving, and it still tells you where to play, which is the whole point.

**Burning** does one of two things after its round of grace:

- On an **occupied** cell, the tile is destroyed and returns to your pile. Its
  word breaks and its points go with it.
- On an **empty** cell, it leaves a **scar** — a dead square nothing may ever
  occupy again.

**Firebreaks.** Fire can't spread into occupied cells or scars. So there are
always two answers — smother it, or wall it off — costing different things, and
choosing between them under time pressure is a decision. Solo has never had one.

It also produces the nicest emergent texture in the design: **scars are
firebreaks**, so the patches where you lost tiles earlier are the ground fire
can't cross later. Your old wounds become your armour.

**Smothering pays.** A word that covers a burning cell scores a bonus. This is
the difference between a mechanic that feels like an opportunity and one that
feels like a tax, and it's the single line most likely to decide whether people
enjoy the mode.

### What it fixes

Late Wildfire looks nothing like early Wildfire. The board becomes swiss cheese,
the open plain closes up, and words have to thread between scars. That's the
"no shape to a run" complaint answered directly — not by making round 40 harder
than round 4, but by making it a *different board*.

### Where it lives

The Solo setup sheet, as a second row. `SetupSetting` already documents
"Game style", "Grid size", "Speed" as its example labels, so a sheet with more
than one row is what it was built for; `SoloSetup` grows a `hazard` field, and
`setups.ts`'s `oneOf` means a stored setup from before the change reads as the
default with no migration code at all.

The alternative is a third door on the home screen, which is more discoverable
and more work, and pushes the two-doors-side-by-side layout into something else.
Start with the sheet; a mode that earns it can be promoted later.

**Sound is nearly free.** Solo has no rivals, so the falling growl that means
"a rival sent you tiles" never plays there — leaving it available for "a tile
burned and came back to your pile". The meanings match exactly: trouble arrived
in your pile through no choice of yours. Ignition wants a new crackle; nothing
else does.

**Purity holds.** Fire is `Record<CellKey, 'burning' | 'scar'>` and spreading is
a pure function of board, fire and rng — `src/game/hazard.ts`, unit-tested
alongside everything else, no DOM in sight. `Grid` already takes a
`cellStatus: Map<CellKey, CellStatus>`, so rendering is new status values and
some CSS.

### Two things to watch

**The pile limit is now attacked from two sides.** Burnt tiles feed the gauge
that the drip is already feeding, so `ENDLESS_LOOSE_LIMIT` at 20 may be too
tight once fire is on. Expect to raise it for Wildfire, or shave the batch —
a playtest question, not a design one.

**Being told where to play might read as nagging.** Solo's freedom is boring,
but freedom is also why the game is calm. Wildfire trades calm for tension, and
that trade must stay a *choice* on the setup sheet rather than becoming what
Solo is.

### Why fire isn't on the daily

Because a one-attempt puzzle is exactly where a loss you couldn't have played
around hurts most, and fire — however carefully fenced — can still hand you a
board you can't answer. Endless is the right home: when it goes wrong, the
answer is to play again immediately, which is the whole point of Solo.

---

## Build order

The two are independent, so this is a preference rather than a dependency chain.

**The Daily** wants doing in this order, because each step is checkable:

1. Seed-word placement and the derived par, with no targets. Already a better
   daily than today's, and it proves the generator surgery (picking a source
   word, splitting the solution, re-rolling on a null solution).
2. Targets, the completion condition, and commit counting.
3. The result card, the star, and whatever the leaderboard encoding turns out
   to be.

**Wildfire**:

1. `hazard.ts` — ignite, spread, burn, scar — as pure functions with tests, and
   nothing wired up. The whole mode's risk is in these rules, and they can be
   argued about in a test file before a pixel exists.
2. The round-boundary wiring and the burnt-tiles-return path.
3. The setup sheet row, the explainer card, the cell styling, the crackle.
4. Playtest the loose limit.

## Still open

- **Take-backs**: refund or cost a stroke. Recommended above, but it's the one
  choice that changes what the Daily *is*, so it's worth playing both.
- **Leaderboard encoding**, which must be pinned before the first submission.
- **Web or Apple first.** Apple has the daily chassis, the streak and the
  leaderboard; the web has none of it but is where changes are cheapest to try.
  If both ship, the seed word, the target cells and the par must be derived from
  the shared seed by identical logic, or the two platforms will play different
  puzzles from the same date.
- **Three targets?** Two may be enough to force a spanning board; four may make
  every day feel the same. Cheap to try once targets exist.
