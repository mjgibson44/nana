# The Daily, after playtesting: two sign errors

*Written 2026-09-08 against `76b499e`, from testing notes on the shipped Daily.
Exploration, not a build plan. The mode as designed is in
`daily-and-modifiers.md`; the options parked before it are in
`daily-mode-ideas.md`.*

> **Built (2026-09-08):** the recommended package — **D4** (the scoring), **E1** (rings
> pay, the day ends on an empty pile or a FINISH DAY) and **P1** (the eraser) — is in,
> with two changes to what is written below. See "As built" at the foot of this page.

Two complaints came out of testing:

1. **Solving it quickly ends it too soon.**
2. **You can't take anything back and the letters run out, so it's easy to
   fail — and the only defence is planning every move in advance, which is too
   much to ask of a casual daily.**

Both are true, and they're the same class of mistake the Wildfire postscript
already names: *the good idea survived, the sign was wrong.* Wildfire made one
square matter as a punishment, so the rational line was to ignore it. The Daily
has two more inverted signs, and they're worth stating precisely before picking
a fix, because they point at different code.

## Sign error 1: the objective terminates the session

`GameModel.spendStroke()` calls `finishGame(reason: .solved)` the moment the
third ring is covered. The rings are the *minimum* bar — three cells, 4–9 apart,
reachable with 20–23 tiles — and clearing the minimum bar ends the day. So:

- **Playing well buys you less game.** Reach all three in four words and the
  day is over in three minutes with fifteen tiles still in hand. The player who
  fumbles around gets more of the puzzle than the player who reads it.
- **The second tier is effectively unreachable.** `allTilesPlaced` needs
  `tilesLeft == 0` at the instant the game ends — so the ⭐ requires one final
  word that covers the last ring *and* empties the pile simultaneously. The
  "signature satisfaction" the design wanted as an ambition is a coincidence.
- **The interesting half of the deal is never played.** Two thirds of the
  letters exist only as a resource for reaching three cells. The dense
  interlocking that `wordScore` actually rewards never has to happen.

The design said the tension should live "in your number against par". It can't,
because the run stops before the number has anywhere to go.

## Sign error 2: irreversibility with no way to see the wall coming

Covering a ring needs *any* tile on that cell — the letter doesn't matter — so
the failure isn't holding the wrong letters. It's arithmetic and geometry:

- **You spend your way out of reach.** Twenty-two tiles, three rings spread 4–9
  apart. Build a fat dense board on one side (which is exactly what the points
  scoring tells you to do) and the far ring is eight cells away with six tiles
  left.
- **The mistake is made long before it's visible.** The move that killed the day
  was the third word, and you find out on the eleventh. Delayed detection,
  irreversible commitment, hard-bounded resource: that's the standard recipe
  for a puzzle players correctly call unfair — and `daily-mode-ideas.md`'s own
  admissibility rule ("it kills you for judgment, never for luck") is arguably
  violated, because judgment here means solving the whole board in your head on
  move one.
- **The mode's own contract says this shouldn't happen.** `DailyProgress` is
  documented "cannot be lost, only left unfinished", and the README says the
  same. But an unfinishable board *is* a loss; it just doesn't print a screen
  saying so, which is worse. The as-built section already flagged this as the
  one decision worth making before the screen was built. It was made by
  inheritance rather than on purpose.

**And permanence here is inherited, not justified.** Words are permanent in Solo
and Battle because those modes are races: undo would let you rewind a clock
you're supposed to be losing to. The Daily has no clock and no pile pressure. It
kept the rule and none of the reason for it.

---

## Fixing the ending

### E1 — Rings pay; they don't stop the game *(recommended)*

Covering the last ring completes the first tier, pays, and says so. The day ends
when the pile empties, or when the player taps **Finish**. One line moves out of
`spendStroke`, plus a finish action and a confirm.

Everything downstream gets better for free: ⭐ every tile becomes a real
ambition rather than a coincidence, the whole deal gets played, and the good
player gets *more* board rather than less. It also removes failure outright as a
side effect — a ring you can no longer reach costs you the tier, not the day,
and you can always take the score you've got.

**The trap this springs.** `dailyLeaderboardScore` sorts strokes first
(`(cap − strokes) × 100000 + points`). Make finishing voluntary under that
encoding and optimal play is: cover three rings in four words, stop, take the
enormous strokes bonus. The shortness comes straight back, now as the *correct*
strategy. So E1 requires the scoring change in D4 below — points primary, par as
a bonus inside it. If the recurring leaderboard is live, that's a new
leaderboard, not a re-reading of the old one.

### E2 — The route lengthens: rings revealed one at a time

The day has six rings, not three, taken from the same hidden solution and
ordered outward. Three are visible; covering one reveals the next. The day ends
on an empty pile or Finish, and "how far did you get" is a headline number that
means something ("🎯×5, 11 words, par 6").

Determinism holds — the ring *sequence* is a pure function of the seed, only
how far you walk it differs — and it turns the current perverse incentive
completely around: solve fast and the puzzle keeps giving you more. Pairs
naturally with E1 (it's E1 plus a reason to keep going that isn't just tidiness).

### E3 — Empty the pile to win; rings become waypoints

Flip the tiers: completion is placing every tile, and the rings are par markers
along the way. Longest by construction and it makes the game's best feeling the
win condition. But it re-arms the failure: leftover tiles are now a loss rather
than a shortfall, so it only works with a strong fix from the next section — and
even then "you failed by two tiles" on a one-attempt day is a bad evening.
Prefer E1's soft version: leftover tiles cost points, they don't fail you.

### E4 — Just deal more

More tiles, five rings, wider spread, same rules. Doesn't fix the sign, scales
it: a longer game that still ends on the minimum bar and still strands people,
now with more sunk time when it does. Listed to be rejected.

---

## Fixing the punishment

### P1 — The Daily gets an eraser *(recommended)*

Words can be lifted in the Daily. Strokes become **words standing on the final
board**, so exploring is free and the score is a property of the artifact rather
than of the journey — which is the option `daily-and-modifiers.md` recommended
before permanence overruled it.

The rule stays legible in one line, and the reason is honest: *permanence
protects a clock, and this mode hasn't got one.* Sudoku with an eraser.

Cheapest workable version: **lift the last word**, repeatedly, back to the
opening (never the seed word). That's a stack, not a general un-place, and it
avoids the connectivity question entirely — no removal can orphan the board if
removals happen in reverse order. General "lift any word whose removal keeps the
board connected" is nicer and can come later.

This single change dissolves both failure sources at once: exhausted your tiles
building the wrong way, or walled a ring off with an awkward crossing? Take it
back. Nothing else on the list does both.

### P2 — Mulligans: three erasers, or three blanks

Same idea, rationed. Keeps commitment tense and makes each take-back a real
decision, which is genuinely more interesting *as a game* — and still ends in a
wall for the player who spends them badly. The good version of this isn't
erasers but **blank tiles**: two wilds in the deal that can be any letter,
spendable to bridge the last two cells to a ring. Answers "I can't reach it"
without answering "I shouldn't have gone that way".

Reasonable compromise if unlimited undo feels like it gives the mode away.

### P3 — The reserve: more letters, priced

Never run out — a **Draw 3** button that adds tiles from the day's bag for a
points cost (25 a draw, say). Failure becomes an expense rather than a wall, and
the leaderboard still separates the player who didn't need it. Deterministic
(the reserve is generated from the same seed), and it composes with permanence,
so it's the fix to take if permanence is non-negotiable. Doesn't help the player
whose *geometry* is wrong, only the one whose supply is.

### P4 — Rings count as covered by adjacency

Cover the ring or a neighbour. Cheap, and it's the lesson Wildfire already
learned about exact coverage — but here the ring takes any letter, so exactness
isn't what's hurting. Halves the last inch of difficulty and leaves the real
failure untouched. Nice polish, not a fix.

### P5 — A hint, priced

`DailyBoard.solution` is retained for exactly this. Reveal one tile of the
hidden crossword for a stroke or a points hit. Every daily worth playing has a
release valve, and this one costs almost nothing to build. Not structural —
ship it alongside a structural fix, not instead of one.

---

## Depth, once the signs are the right way round

These are composable, and each is small. The first is the direct answer to "it's
unreasonable to expect people to plan every move".

### D1 — A visible queue instead of the whole hand

Today the entire deal lands at once (20–23 tiles), which is precisely what makes
the mode a single enormous planning problem you either solve up front or lose
slowly. Instead: hold eight, refill to eight after each word, with the next few
visible in a queue. Same letters, same order for everybody, same determinism —
but the puzzle becomes a rhythm of small readable decisions with a Tetris-style
preview, rather than one act of clairvoyance.

It also unbolts the deal size from the pile: the day can total thirty-five tiles
without ever threatening to bury anyone, which is more game for the fast solver
(E1's problem) at no cost to the slow one.

The one thing to check by playing it: a queue you can only partly see adds a
little luck back, and the whole point is to remove luck. Preview depth is the
knob — three visible is probably enough to plan a crossing.

### D2 — Gold squares, standing still

`Prizes.swift` exists and is the mode's best-tested new mechanic; the Daily is
the one place it can run **without a clock**. Fixed gold cells from the day's
seed, worth a multiplier to a word crossing them, placed off the hidden solution
so they're always reachable. Pure aiming, no decay, no pressure — and it gives
the back half of the day (the part E1 hands back) something to be *about*.

### D3 — Pay for the move the mode is already about

The design's whole claim is that the best stroke is one word crossing three
others. Nothing currently pays extra for it. A multi-run bonus (or a bonus for
reaching a ring with a word that makes two or more new runs) states the mode's
thesis in the scoring instead of just in the docs.

### D4 — Leftover tiles cost, and par becomes a bonus not a sort key

Required by E1, and worth having anyway. One number:

```
score = points + PAR_BONUS × (par − strokes)  −  LEFTOVER × tilesLeft
```

Golf still matters, stopping early is never optimal, tidiness is rewarded, and
the leaderboard becomes one honest quantity instead of a packed pair. The share
card keeps showing both halves — `🎯🎯🎯 in 7 (par 9) ⭐ every tile` — because
that's what people paste; the sort just stops disagreeing with what the mode is
for.

---

## What I'd build

**E1 + P1 + D4**, in that order, is the smallest change that fixes both
complaints and nothing else:

1. **D4 first**, because E1 is wrong without it and it's pure `WordCore`
   arithmetic with tests — no UI. Pin the encoding before anything submits.
2. **E1** — rings pay, Finish is a button, the ⭐ becomes reachable. This is the
   "too short" complaint, gone, in about twenty lines.
3. **P1** — lift-the-last-word, strokes counted off the final board. This is the
   "easy to fail" complaint, gone, and it's the only item here that touches
   `GameModel`'s placement path properly.

Then, once it's been played for a week and the shape is right:

4. **E2** (more rings, revealed outward) if the back half feels aimless, or
   **D2** (gold squares) if it feels aimless in a way that wants points rather
   than direction. Probably not both at once — they compete for the same
   attention.
5. **D1** (the queue) is the biggest idea on this page and the one most likely
   to change how the mode feels. It deserves to be tried on its own, after the
   two fixes above have settled, and judged on one question: does holding eight
   tiles make the day feel *lighter* or *blinder*?

## What I'd not do

- **Keep permanence and patch around it.** P2/P3/P4/P5 are all real
  improvements, and stacked they still leave a player who committed wrong on
  move three with a day they can't finish. The reason permanence exists doesn't
  apply here; the cheapest honest fix is to drop it in this one mode and say why.
- **Add a clock.** Every version of "make it last longer" that reaches for
  pressure turns the Daily into Solo, and the Daily's job is to be the calm one.
- **Make failure explicit** (a "no moves left" loss screen). Honest about what's
  happening today, and exactly the wrong direction for one attempt a day.

## Open questions

- **Does Finish need a confirm, and can you come back?** Suggested: Finish
  confirms, and the day stays open until you do — you can put the phone down at
  eleven rings and pick it up after lunch, which the save blob already supports.
- **Does the streak key off started or finished?** With no failure state the
  distinction stops mattering much; worth deciding out loud rather than
  inheriting.
- **Does unlimited undo make par meaningless?** It makes par *solvable* — a
  determined player converges on their best board. That's the same bargain
  Sudoku makes, and the leaderboard still separates people by points and by
  tidiness. But it's the one thing on this page worth playing before believing.


---

## As built

The three recommended items shipped together, in the order given: the scoring, then the
ending, then the eraser. Two things came out differently from the argument above, both
because building it made a better answer obvious.

**The leftover penalty became a tile bonus.** D4 charges `LEFTOVER × tilesLeft`. That
ranks correctly, but it makes the *live* number nonsense: on a fresh day it is
`points − 220`, floored at zero, so the header reads 0 for the first third of the day and
then jumps. Paying `DAILY_TILE_POINTS` (10) for every tile *placed* is the same ordering —
every player on a given day is dealt the same tiles, so the two differ by a constant — and
it climbs from the first word. Same maths, a number worth watching.

Concretely: `points + 40 × rings + (all rings ? 30 × under par : 0) + 10 × tiles placed`,
and nothing is ever subtracted. Going over par costs only the bonus you didn't earn, which
is the point — the whole correction was to stop charging people for playing more of the
mode.

**Two board-reading fixes came with the ending**, neither of them anticipated here, both
obvious the moment the day ran past the third ring:

- **The pile gauge was a danger meter** filling toward the limit that ends a Solo game —
  so a Daily opened solid red (the deal is 22 tiles against a limit of 24) and sounded the
  overflow alarm on the first word. In a mode where the pile only shrinks and an empty one
  is the finish line, that bar is a progress bar running backwards. It now fills with
  tiles placed, green, and the alarm is off.
- **A day opened on the start square**, which put one ring on screen and two off it. Now
  it opens on the whole day — seed word and all three rings — and the rings are part of
  the auto-fit box, because a ring you can't see is an instruction you can't follow.

**What was left alone**, and why it is still worth doing in this order: E2 (rings revealed
outward), D2 (gold squares standing still) and D1 (the visible queue). Each changes how
the mode *feels* rather than fixing how it fails, and the two fixes above should be played
for a week before anything competes with them for the same attention.
