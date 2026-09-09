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

---

## As built — the WordCore layer

*Added 2026-09-06. This section is what actually shipped, and where it differs
from the design above.*

The pure layer for both modes is written and tested:
`WordCore/DailyBoard.swift`, `WordCore/Wildfire.swift`, their two test suites,
`SoloHazard` and the mode cards in `Modes.swift`, and `hazard` on `SoloSetup`.
The app layer — the setup-sheet row, the Daily's screen, cell rendering, the
round wiring — is not.

**The design targets the app, not the web.** The old auto-generated Daily Deal
mode is disregarded; only its calendar survives (`DailyDeal.swift` — which day
is live, when it rolls over, the salted seed, the streak), which is the part
worth keeping. Web parity is not a constraint on any of this.

### The numbers were measured, not guessed

The construction was prototyped against the canonical TypeScript generator and
swept over 500 seeds before a line of Swift was written, then the Swift
algorithm was transliterated back and swept again to check it as written. What
came out, at 30 tiles:

| | |
|---|---|
| Built successfully | 500 / 500, one rejected deal in total |
| Par (the hidden crossword's words) | 5–8, median 6 |
| Seed word | 5–8 letters, median 6 |
| Tiles dealt to the player | 22–25, median 24 |
| Gap between targets | 4–9, median 6 |
| Solution span | ≤ 17, so it always fits the 33×33 opening board |
| Null solutions (the generator's fallback) | 0 |
| Solutions with a 2-letter or non-dictionary run | 0 |

That last row is what lets par be honest: every hidden crossword is a strictly
legal board, so counting its runs counts its words.

### What changed from the design

**Wildfire's fires carry no age.** The first cut gave each fire an age field
and resolved it once it had lived a round — which quietly gave every fire *two*
player-rounds of grace, since a fire lit at the end of round N isn't seen by
round N's own resolve pass. Dropping the field fixes the bug and states the
rule better: everything alight when the round ends was lit by the previous
round, so **every fire you can see burns at the end of this round unless you
put it out**. No bookkeeping, and one sentence to teach.

**Fire scars its own cell and eats a neighbour, rather than sitting on a tile.**
Fires only ever occupy empty cells, which keeps one invariant doing a lot of
work: "play on it" is always a legal move, so a fire always has an answer. An
unanswered one scars where it sat, takes one tile from beside it back to the
pile, and steps to a neighbouring cell — preferring one next to a tile, so it
walks toward the board rather than off into nothing. Ringed by dead ground or
tiles, it goes out.

**Fire kills through the pile, not a loose-tile gauge.** The app's Solo has no
loose-tile rule — the pile is the only pressure, and reaching `PILE_LIMIT`
ends the game on the spot. That suits fire better than the web's rule did:
burnt tiles land straight in the pile, so an ignored fire can end a game
outright. `hazardPileLimit(base:hazard:)` hands Wildfire `WILDFIRE_PILE_RELIEF`
more room, taking the base limit as an argument because the limit is the app's
to set and the relief is the rule's.

**The take-back question answered itself.** The design called it the one choice
that changes what the Daily is. The app settles it: words are permanent in
every mode, so a stroke is a word played and there is no undo to refund. What
softens it is staging — tiles sit ghosted and can be rearranged or cleared
freely until the ✓ — so the thinking happens before the stroke is spent.
`DailyResult` therefore has no "clean" flag; there is nothing for it to record.

**`DailyBoard` keeps the hidden solution.** For the same reason `Puzzle` does:
it is the proof that the targets can be reached and that par can be made, it is
what a hint would read, and it is what lets the tests check both rather than
take them on trust.

### As built — the app layer

Both modes are wired into the app.

**Wildfire** is a second row on the Solo setup screen (`SoloHazard` on `SoloSetup`, so
the screen opens on the whole of the last game). Fire advances on the drip's expiry in
`GameModel.advanceFire`; burnt tiles go back through `appendDealtTiles` like any other
arrival, including the burial check, and sound like a rival's attack because they mean
the same thing. Dousing and the dead-ground refusal both hang off `land()`, so every
road to a landing answers the same way. Burning and burnt squares are painted in the
existing Canvas lattice pass, in cell terms rather than keys so the 1,100-square pass
allocates nothing.

**The Daily** is its own mode (`GameMode.daily`) behind a home-screen door that shows
the streak and dims once the day is played. It has no clock and cannot be buried — its
deal arrives at once and fills most of the pile, so the rule that ends a Solo game would
end a Daily before the first word, and nothing is arriving to make it worse. A landing
spends a stroke and, if it covered the last ring, ends the day as a win. The header
carries targets and strokes against par where the clock would be; the leaderboard gets
the packed pair through the funnel every other mode already uses.

**Two numbers moved.** The day's crossword is 28 tiles, not 30: the app draws the pile as
three rows of eight and buries a player who fills it, so a deal has to fit inside 24, and
28 puts every deal between 20 and 23 with par unchanged at a median of 6. A `maxDeal`
guard now enforces that rather than leaving it to arithmetic.

### Not yet done

- **None of it is compiled.** There is no Swift toolchain in the environment
  this was written in and `download.swift.org` is blocked by its network
  policy, so `swift test` has never run against any of it. The algorithm is
  validated (twice, in TypeScript); the Swift is reviewed but unbuilt, and the
  first `swift test` should be treated as the real first run.
- **App wiring**: the Solo setup sheet's hazard row, the Daily's own screen and
  entry, target and scar rendering on the board, the round-boundary call into
  `wildfireAdvance`, the douse call on commit, `SavedSoloGame` carrying the
  fire, and the result card.
- **One decision worth making before the Daily's screen is built:** whether
  permanence is right for a one-attempt-a-day puzzle. It means a wrong early
  word can put a target out of reach with no way back — which contradicts the
  design's "the daily cannot be failed". Allowing a word to be taken back in
  the Daily alone would fix it, at the cost of the app's one consistent rule
  and some `GameModel` work.


---

## Postscript — Wildfire retired, September 2026

*Added 2026-09-08. Everything above about Wildfire is now history; the Daily is
unaffected and still plays as described.*

Wildfire shipped, was played, and was replaced by **prize cells**
(`WordCore/Prizes.swift`, and the "Solo modifiers" section of `apple/README.md`).
Keeping the record of why, because the diagnosis is more reusable than the mode:

**The good idea survived. The sign was wrong.** Fire's real contribution was that Solo's
board had nowhere to *go* — freedom is what makes the mode calm, and it is also why a
long run has no shape. Fire fixed that by making one square matter. But it made it matter
as a punishment, and that turned the feedback loop upside down: playing well produced
nothing, playing badly closed the board in. So the rational line was to ignore a fire for
exactly as long as you could afford to, and the mode's most interesting decision was one
players were incentivised not to engage with. The design above even predicted the shape
of this — *"being told where to play might read as nagging"* — and then priced the
douse bonus as the fix. A bonus for answering a threat is still a tax with a discount.

A prize keeps the geometry and inverts the sign. Same "one square matters", same "it is
on a clock", same "it is near your board so you can reach it" — but claiming it pays, and
ignoring it costs only what you could have had. Players chase opportunities and resent
taxes, and that is the whole difference.

**Two mechanics collapsed into one.** Fire needed ignition, spread, scarring, dousing,
a firebreak rule and a pile relief constant to be the mode it was. A prize needs a spawn
rule, a clock and a claim; what it *pays* is one enum (`PrizeKind`), which is how Gold
Rush and Salvage are the same mechanic taught once rather than two modes. Scars went with
it — dead ground was the one thing on the board that could make a position unwinnable
through no decision the player made.

**The decay is the mechanic.** Fire's clock only ever answered "have you dealt with this
yet". A prize's clock sets its price continuously, so the square is not points waiting for
you — it is a bid to change what you were going to play *right now*, falling while you
think about it. That is a decision on every tick rather than a deadline on one.

**What it cost.** Prizes cannot ride the drip's round boundary the way fire did, so they
carry a real clock and the UI heartbeat drives them. That is the one place this design is
more expensive than the one it replaced, and the reasoning is in `Prizes.swift`.


---

## Postscript — the Daily reworked, September 2026

*Added 2026-09-08. The construction above is unchanged — same hidden crossword, same seed
word, same three rings, same derived par. What changed is what you do with them, and why
is set out at length in `daily-depth.md`.*

The Daily shipped as designed, was played, and came back with two complaints: solving it
quickly ended it too soon, and you could fail it. Both were true, and both were the same
class of mistake the Wildfire postscript above already names — *the good idea survived,
the sign was wrong* — this time in two places at once.

**The rings ended the game, and the rings are the minimum bar.** So playing well bought
you *less* game: three rings inside four words and the day was over with fifteen tiles in
hand. Worse, the second tier was unreachable by construction — `allTilesPlaced` was read
at the instant of the last ring, so the ⭐ needed one final word that covered the last ring
*and* emptied the pile. The mode's stated ambition was a coincidence.

**Permanence made the day strandable.** The design above worried at this question and the
"as built" section settled it by inheritance, flagging the risk in its own last line: *a
wrong early word can put a target out of reach with no way back — which contradicts the
design's "the daily cannot be failed".* It did. Not through bad letters, either: a ring
takes any tile, so the failure was arithmetic — spend twenty tiles building dense on one
side and the far ring is eight cells away with six tiles left. The killing move is word
three and you find out on word eleven.

The fix, in the order it was built:

1. **The scoring first**, because everything else is wrong without it. One number
   (`dailyScore`): points, plus a ring bonus, plus a par bonus gated on all three rings,
   plus ten a tile for every tile off the pile. Strokes stopped being the sort key —
   under the old `(cap − strokes, points)` packing, a voluntary ending would have made
   "three rings in four words, then stop" the *optimal* line, and the shortness would
   have come back as correct strategy. `LeaderboardID.daily` moved to `.v2` with it.
2. **Rings pay, they don't stop the game.** The day ends on an empty pile or on FINISH
   DAY. The ⭐ became reachable; the back half of the deal became worth playing.
3. **The eraser.** `undoLastWord`, a stack, the Daily only — the take-back the design
   above recommended before app-wide permanence overruled it. Permanence protects a
   clock; this mode hasn't got one. Strokes are now words *standing*, so the score is a
   property of the artifact rather than of the route.

What was deliberately not built, and is written up in `daily-depth.md`: progressively
revealed rings, gold squares on the day's board, and the visible-queue deal. Each is a
change to how the mode *feels* rather than a fix to how it fails, and they deserve a week
of the fixed version being played before any of them lands.
