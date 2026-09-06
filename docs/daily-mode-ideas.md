# A daily mode with a rule that changes — brainstorm

*Written 2026-09-06, against `229c82d`. Nothing here is decided; it's a menu
and an argument for how to pick from it.*

## Where things stand

- **Web** (`src/game/modes.ts`) has Solo (Endless, two paces), Battle, and the
  tutorial. No daily.
- **Apple** (`apple/Packages/WordCore/Sources/WordCore/DailyDeal.swift`) already
  ships a **Daily Deal**: 30 tiles, no clock, one go per day, dealt from
  `TileStream(seed:)` off a salted date seed so every player in the world gets
  the same letters. Streaks, rollover semantics and a recurring Game Center
  leaderboard are all wired.
- The port plan's §16.3 leaves the *rules* open on purpose — "fixed deal vs
  timed run… decide in phase 3."

So the plumbing a daily needs — a shared seed, a deal identical for everybody,
one attempt, a streak — is done on Apple and cheap on the web (`seededRng` +
the generator's injectable `rng`). What isn't decided is the part this document
is about: **what you actually do with the day's letters**.

## The problem, stated precisely

Solo feels similar every time for three separable reasons. Worth pulling them
apart, because each suggests a different fix and only one of them is about
difficulty:

1. **No spatial pressure.** Every empty cell is as good as every other. Nothing
   in the game ever says *play here, now*. The board is a place to put things,
   not a thing to reason about.
2. **No decisions, only execution.** You are handed letters and you place them.
   The skill measured is speed of arrangement — never judgment, never a
   trade-off, never a choice you can regret.
3. **No shape to a run.** Round 40 is round 4 with a bigger batch. There is
   escalation but no change of kind: the last minute of a Solo game asks the
   same question as the first.

The Daily Deal as it stands fixes none of these — it removes the clock, which
takes away the one pressure Solo had. It's a pleasant arrangement puzzle, and
it will be the same pleasant arrangement puzzle on Thursday.

## The proposal: the day's rule

Make the daily **one fixed deal plus one modifier, drawn from a pool by the
same seed that deals the letters**. Monday is Wildfire. Tuesday the board has
holes in it. Wednesday a word is already down and everything must hang off it.
The chassis is written once; each modifier is small, and the mode stops being
the same game two days running.

This also answers §16.3's "fixed deal vs timed run" without choosing: some
modifiers want a clock, some don't. The pool can hold both.

Three properties make this worth the build:

- **Variety is compounding, not additive.** Six modifiers over a 30-tile deal
  is six different puzzles a week, and each new one is a day's work rather than
  a mode's.
- **It's a reason to come back specifically today.** "Same letters as everyone"
  is a reason to compare; "today is the fire one" is a reason to show up.
- **It's one line of copy.** The day's card already exists (`DAILY_DEAL_INFO`);
  it grows a line naming the rule.

### What a modifier must respect

Not every good idea survives contact with a leaderboard. A modifier is only
admissible if:

- **Everyone gets the same one.** Seeded from the day, never from the player.
  Two people playing different rules into one leaderboard occurrence is the
  same bug as two people playing different letters.
- **It cannot make the deal unsolvable.** The generator's promise — every deal
  is playable by construction — is the game's foundation. A modifier that
  blocks cells or forces coverage has to be built *around* the known solution,
  or verified against it, not sprinkled on afterward.
- **It kills you for judgment, never for luck.** A rule you can lose to while
  playing well is fine once (Solo's clock). A rule you lose to because the
  letters you happened to hold couldn't answer it is a rule players will
  correctly resent — and on a daily, with one attempt, they can't shake it off
  by replaying.
- **It lives in the pure core.** `src/game/` and `WordCore` have no DOM and no
  UIKit, which is what lets battle run without a server and lets everything be
  unit-tested. A modifier that needs a view to adjudicate it is the wrong shape.
- **It reads in one sentence.** If the card can't say what today's rule is in a
  line, it's a mode, not a modifier.

## The catalogue

### Spatial pressure — fixes problem 1

The richest family, because it attacks the deepest flaw: it gives the board a
geometry you have to think about.

**Wildfire.** Cells ignite and spread; cover or contain them. Detailed below —
it's the marquee one and the one most likely to need tuning.

**Target cells.** Three marked cells scattered around the board. The puzzle
isn't finished until your crossword reaches and covers all three. Everything
Wildfire does to your build order, with no health, no timer and no way to lose
to bad letters — you simply haven't finished yet. Different targets each day
make a genuinely different puzzle out of identical code, and "how few words did
it take you to reach all three" is a better score than raw points. *Cheapest
high-variance idea in this document.* Place the targets on cells the generator's
own hidden solution occupies and reachability is guaranteed for free.

**Blocked stencil.** A pattern of dead squares no tile may occupy — symmetric,
like a real crossword grid. One `Set<CellKey>` consulted in `planPlacement`, and
the board you're building on stops being an open plain. Needs generating against
the stencil (or picking a stencil the known solution clears) to keep the
solvability promise.

**Seed word.** The board starts with the day's word already down, and everything
must connect to it. Almost no code — the deal is already grown off a hidden
board, so seeding the visible one is the same operation. CRANE and XYLEM are
very different anchors for the same 30 tiles, and it gives the day an identity
players can talk about.

**Rising tide.** The board floods from one edge, a row every N seconds; tiles in
a flooded row are lost and those cells die permanently. Build inward, finish the
low ground first. Wants a clock, so it's the "timed run" branch of §16.3 — a
good one, because unlike Solo's clock it tells you *where* to hurry.

### Decisions — fixes problem 2

**Draft.** Each wave shows eight tiles; you keep five. Discards cost points.
Suddenly there is judgment in a game that has never had any, and two players
with the same deal end up with different letters — which is either the best
thing here or a leaderboard problem, depending on taste.

**Bonus squares.** Gold cells multiply the word crossing them. You stop placing
words *somewhere* and start aiming them. Composes with everything else in this
list, which is unusual.

**Move budget instead of a clock.** Solve the fixed deal in at most N commits.
Converts speed-skill into planning-skill and makes the daily something you can
play calmly on a sofa — which is what a daily should be. Also the single
easiest modifier to implement: count commits.

### Constraints — cheapest variety per line of code

Each of these is one predicate over a word or a board, and each makes the day
feel different out of all proportion to its cost:

- No words shorter than five letters.
- Every word must contain today's letter.
- Finish in exactly twelve words.
- No word may be extended once it's down (battle's permanence, solo's pace).
- A vowel-starved or Q-heavy deal — steer the generator's word pool and the
  solvability promise still holds by construction.

### Shape — fixes problem 3

**Three acts.** The deal arrives in three waves with different rules: a quiet
opening puzzle, a timed scramble, then one large final dump. Same tiles, three
different feelings, one run.

**Chain scoring.** Points only count when each word crosses the word you played
immediately before. Rewards a snaking, deliberate build over scattered islands,
and makes order-of-play matter for the first time.

## Wildfire, in detail

The instinct — random cells catch fire, cover them or the fire spreads and
health runs out — is the strongest one on the list, because it's the only idea
here that makes the *board* the thing you're playing against. The details
decide whether it lands as tense or as unfair.

**Ignite only near your tiles.** Fire on an empty cell in open space can't be
answered: the board must stay connected, so there is no legal move that reaches
it. Restrict ignition to cells adjacent to (or a short hop from) tiles already
down. Every fire should have at least one legal answer at the moment it starts.

**Burn the board, not a health bar.** Far more interesting than abstract HP:

- Fire on an **occupied** cell destroys that tile after a round. The word breaks,
  its score goes with it, and the letter comes back to your pile as an ash tile.
- Fire on an **empty** cell leaves a permanent scar — a dead square, as in the
  stencil modifier.

The board visibly degrades and its geometry keeps changing, which is exactly the
within-a-run variation Solo lacks. A number ticking down in the header is not.

**Extinguish by adjacency, not exact coverage.** Requiring a tile on the precise
burning cell means dying to letters you don't hold — the bad-luck failure the
admissibility rules above forbid. Placing a tile *next to* the fire is forgiving,
still directs where you play, and keeps the pressure legible.

**Firebreaks.** Surrounding a fire contains it. This is the mechanic that turns
fire from a tax into a puzzle: there are two answers (smother it, or wall it
off), they cost differently, and choosing between them is a decision — which is
problem 2, solved in passing.

**Losing.** Scars past a threshold, or fire count over a limit when a round
ends. Mirror Solo's loose-tile rule: over the line is a warning, still over when
the round ends is the verdict. Players already know that shape, and the alarm
cue in `sounds.ts` already exists to say it.

**Rendering is nearly free.** `Grid` already takes
`cellStatus: Map<CellKey, CellStatus>`; ember, burning and scarred are new
status values and some CSS. No new plumbing.

**The one thing to playtest first:** whether being told where to play is
*relief* or *nagging*. Solo's freedom is boring, but freedom is also why the
game is calm. Fire trades calm for tension, and a daily may want calm.

## Suggested build order

1. **The rule slot.** Teach the daily to carry a modifier chosen by the day's
   seed, show it on the card, and record it with the result. One modifier in the
   pool at first: `none` — today's daily, unchanged. Nothing user-visible
   changes; everything afterwards gets cheap.
2. **Seed Word** and **Target Cells.** Both nearly free, both leaning on the
   generator's hidden solution for their guarantees. Two modifiers is enough to
   prove the rotation actually feels different, which is the real question and
   worth answering before building anything expensive.
3. **Wildfire.** The marquee rule, and the one that will take iteration. Ship it
   once the rotation is proven, not before.
4. **A constraint or two.** Cheap filler that keeps the pool from repeating.

If the web adopts the same date seed (§16.3 q5), the modifier choice must be
derived from the seed by shared logic, or web and Apple will play different
rules on the same letters — which is worse than not sharing the puzzle at all.

## Open questions

- **Does the daily keep its clock-free calm?** Some modifiers here (tide,
  wildfire, three acts) need a clock. Deciding the daily is the *quiet* mode
  rules out about a third of this list — a legitimate choice, and one worth
  making deliberately rather than by accident.
- **Comparable scores across different rules.** Points under Wildfire and points
  under a bare deal aren't the same currency. Either the leaderboard is per-day
  (fine — it already is, being a recurring occurrence) or scores need
  normalising, which is more trouble than it's worth.
- **Is the modifier announced in advance?** A visible week ahead lets players
  plan and gives each day an identity; a surprise is a better hook.
- **Where does this get built first?** Apple has the chassis, the leaderboard
  and the streak. The web has neither, and would need a daily of its own before
  it could carry a rule.
