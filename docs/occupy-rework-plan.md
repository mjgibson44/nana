# Occupy, reworked: your own ground, and zones worth fighting for

Two rule changes to the Apple-only Occupy mode
(`apple/Packages/WordCore/Sources/WordCore/Occupy.swift` and everything that
reads it), written down before anything was built — and **built on this
branch since**, protocol v10. Where the code and this page disagree, the code
is the truth; the numbers here are the ones it uses.

## What changes, in one breath

1. **You play your own words only.** Capture-by-crossing is gone. A word
   borrows a letter *you* already own; it may not borrow, or run through, a
   rival's tile. Two players' tiles may sit flush against each other — the
   board is allowed to look like one crossword — but each side's run is read,
   judged and valued on its own, so a shared line is two words, not one.
2. **Zones are contests with a whistle.** A zone opens, stays open for a
   minute, and closes: whoever owns the most tiles inside it at the whistle
   banks a flat bonus. Fifteen seconds later the next one opens. The first
   opens a minute into the game. Zones no longer double anything.

Together they turn the mode from *steal your rival's letters* into *hold your
own ground and race for the flag*, which is what "Occupy" should have meant
all along.

---

## 1. Your own ground

### The rule

- Every tile's owner is stamped when it lands and **never changes again**.
- A placement may borrow only cells the placer owns.
- A placement may not *span* a cell it doesn't own: the line between its
  furthest two squares must be made entirely of its own new tiles and its own
  borrowed ones.
- Contact is legal and unpoliced. If your word ends up flush against a
  rival's, no combined run is validated, and neither of you is credited for
  the other's letters. (Per the design call: a physically joined line that
  reads as nonsense across the seam is accepted — the seam is a border, not a
  word.)

### Why it works

The mode's value rule already carries the weight: a tile is worth the length
of the longest word it sits in. Once "the longest word it sits in" means *the
longest word of yours*, everything else follows — a rival's letters are scenery,
their runs are theirs, and the only two things you can do to them are get
somewhere first and take a zone off them.

It also removes the mode's one confusing moment: watching your score fall
because someone crossed a word you'd finished.

### Core changes (`Occupy.swift`)

| Piece | Today | After |
| --- | --- | --- |
| `occupyApply` borrow check | borrowed cell just has to hold a letter | must hold a letter **owned by `seat`** — new `OccupyRefusal.notYours(CellKey)`, "That letter isn't yours to borrow." |
| `occupyApply` line check | walks `next.board` and passes as long as nothing between the extremes is empty | every intermediate cell must be in `placement.tiles ∪ placement.borrowed`; anything else in the way is `OccupyRefusal.throughRival(CellKey)`, "You can't build through a rival's letter." |
| Word validation | `runsTouching(touched, in: next.board)` — every physical run | new `occupyOwnedRunsTouching(touched, board:, owners:, seat:)`, which walks only cells owned by `seat`, so a run stops dead at a rival tile |
| `occupyTileValues` | longest physical run through the cell, doubled in a zone | `occupyTileValues(board:owners:)` — longest **same-owner** run through the cell; no zone multiplier |
| Capture | `for key in placement.borrowed { next.owners[key] = seat }` | deleted (borrowed cells are already the placer's) |
| `settledAt` | stamped for every seat whose score moved | only your own score can move on your own word, so only your seat is stamped |
| `OCCUPY_ZONE_MULTIPLIER` | 2 | deleted |
| `.mustBorrow` message | "Borrow a letter that's already down." | "Borrow one of your own letters." |

Note the value change is the same idea as the validation change: **a run is a
maximal same-owner line of 2+ cells**. One helper — say
`occupyOwnedRuns(board:owners:)` and the `…Touching` variant beside it — feeds
both `occupyApply` and `occupyTileValues`, so what a word has to be to land and
what it is worth can never drift apart.

### Client changes (`Word/Game/GameModel.swift`, `WordCore/Staging.swift`)

- `canAddGap` (GameModel:430): in Occupy the test becomes "my opener is down"
  (`view.opened[seat]`) rather than "the board isn't empty" — there is nothing
  to borrow until you own something.
- Tapping a placed letter to aim a gap (`tapPlacedLetter` /
  `anchorForGapTarget`, GameModel:1127–1220): rival cells are not aim targets.
  Tapping one says "That's not your letter." rather than planning a word that
  the host would refuse.
- The drag-and-drop road: `judgeStaged` gains an `ownedByPlayer: (CellKey) ->
  Bool` (default `{ _ in true }`, so Solo and the tutorial are untouched). A
  rival tile is a **wall**: the run-through scan stops at it (`.throughRival`),
  `borrowed` only ever collects own cells, and cross-runs are read as
  same-owner segments.
- `commitOccupy` (GameModel:1509): the `captured` count and its "Captured 3
  tiles!" toast go.
- Board drawing: rival tiles get the "not yours" treatment (they already draw
  in the rival's seat colour; they should also stop being tap targets).

### Consequences worth knowing before building

- **No comeback mechanic survives except zones.** Scores only ever go up, and
  nobody can take value off you. That makes the zone bonus the single knob
  that decides how much of a game is still live at minute eight — see §2.
- The "a long word is defended by crossing its own letters" line in the
  `Occupy.swift` header doc is obsolete; defence is now purely spatial (be
  there first).
- Two rival words flush together each score their own length. A test should
  pin this: my 3-run against their 3-run is 9 and 9, never 36.
- The stall rule gets *less* likely to fire, not more: your own frontier is
  always playable, since nobody can seal you in without also being unable to
  build through you.

---

## 2. Zones with a whistle

### The shape

```
0:00 ─────────────── 1:00 ─────── 2:00 ─── 2:15 ─────── 3:15 ─── 3:30 …
     opening grace        zone 1 open       zone 2 open
     (no zone)            (60s)        gap  (60s)       gap
                                       15s              15s
```

| Constant | Value | Note |
| --- | --- | --- |
| `OCCUPY_ZONE_FIRST_SECONDS` | 60 | opening grace before zone 1 |
| `OCCUPY_ZONE_OPEN_SECONDS` | 60 | how long a zone is contested |
| `OCCUPY_ZONE_GAP_SECONDS` | 15 | breather between one closing and the next opening |
| `OCCUPY_ZONE_SIZE` | **5** (was 3) | 25 cells has room for two crosswords to fight inside it |
| `OCCUPY_ZONE_BONUS` | **25** | flat, to the seat holding the most tiles at the whistle |
| `OCCUPY_ZONE_MIN_WINDOW` | 30 | a zone is not opened with less than this left on the match clock |
| `OCCUPY_ZONE_REACH` | 6 (was 5) | measured centre-to-frontier; the zone's half-width grew by 1, so this grows with it |

Cycle length is 75s, so a ten-minute game runs **seven zones**, opening at
1:00, 2:15, 3:30, 4:45, 6:00, 7:15 and 8:30, the last closing at 9:30. The
slot that would open at 9:45 fails the `MIN_WINDOW` test and is skipped,
leaving a zone-free final thirty seconds — the endgame is about finishing the
words you have down.

`OCCUPY_GRACE_SECONDS` (30) is the *stall* grace and is unrelated; rename it
`OCCUPY_STALL_GRACE_SECONDS` while in here, because two graces of different
lengths under similar names is a bug waiting to happen.

### Resolution

At the whistle, count the tiles each seat owns inside the 25 cells:

- most tiles wins, and banks `OCCUPY_ZONE_BONUS`;
- a tie wins nothing (the same rule quadrants already use);
- an empty zone wins nothing.

**Tiles, not value** — it reads live in the HUD as "you 4 – them 2", and word
length is already paid for by ordinary scoring.

A zone that is still open when the game ends — on the clock, on the stall
rule, or because the field emptied — is resolved at that moment by the same
rule. That is one line in `finishOccupy` and it means there is no such thing as
an unresolved zone in a finished game.

### State

`OccupyZone` grows a lifecycle:

```swift
public struct OccupyZone: Codable, Equatable, Hashable {
    public var slot: Int          // which scheduled zone this is
    public var centre: Cell
    public var opensAt: Double    // seconds since the deal, not a wall clock
    public var closesAt: Double
    public var winner: Int?       // nil until resolved, or resolved by nobody
    public var counts: [Int]      // per-seat tiles held at the whistle
    public var resolved: Bool
}
```

Times are **elapsed seconds since the deal**, so every screen can run the
countdown off its own `run.startedAt` exactly as it already runs the match
clock — no clock sync, nothing new on the wire per tick.

`OccupyState` grows `bonuses: [Int]`, and `scores` stays what it is today: the
**total**, tile value plus banked bonuses. That is deliberate — `OccupyBarView`,
`occupyRanking`, `syncOccupyScores`, the results screen and the leaderboard all
read `scores` and none of them need to change.

### The referee (`HostSession`)

- `spawnOccupyZones(elapsed:)` keeps its shape: slots are handed out in order,
  each rolled off `"\(seed)/zones/\(slot)"` so a replay grows the same zones in
  the same places. It gains the `MIN_WINDOW` cut-off, and stamps `opensAt` /
  `closesAt` from the slot rather than from `now`.
- A slot that finds nowhere to go is skipped today. With only seven zones in a
  game that is a real loss, so: **retry the slot for up to 10 seconds** before
  giving up on it (the board changes every few seconds; a patch usually opens).
- New `resolveOccupyZones(elapsed:)`, called from the same `tick` block: any
  unresolved zone whose `closesAt` has passed is tallied, `winner`/`counts`
  filled in, `bonuses[winner] += OCCUPY_ZONE_BONUS`, `scores` recomputed,
  `settledAt[winner]` stamped, then `syncOccupyScores()` and `publish()`.
- `finishOccupy` resolves whatever is still open before freezing the board.

Resolution is the host's alone. Clients never resolve a zone — they only *read*
one, which keeps the one-referee property the mode is built on.

### Ranking

Zones are the headline now, so the tiebreak follows them:

`score → zones won → quadrants held → who got there first (settledAt)`

(today it is score → quadrants → settledAt).

### What the player sees

- **Board** (`BoardContentView`): an open zone keeps today's lighter fill and
  bright edge, with the seconds left drawn at its centre in place of the "2×"
  glyph. A resolved zone drops to the winner's seat colour at low opacity with
  a "+25" badge; nobody's zone goes grey with a dash.
- **Header** (`GameChrome`): one line beside the match clock — `Zone · you 4 –
  them 2 · 0:41` while open, `Next zone 0:12` in the gap, nothing during the
  opening grace beyond the match clock. The live tally is derived client-side
  from `view.owners`, so it moves the instant your word lands.
- **Toasts** (`adoptOccupy` already diffs the zone list): "Zone open — one
  minute", then "You took the zone! +25" / "They took the zone, 6–4" /
  "Nobody held the zone".
- **Sound**: borrowed rather than new. The quiet `.tick` when a zone opens,
  the pile's rising `.deal` chime for one taken, the `.attack` growl for one
  lost. Not `.win` / `.lose`: those two are the end-of-game fanfares, and a
  lost zone should never sound like a lost game.
- **Mode card** (`OCCUPY_INFO` in `Modes.swift`) needs rewriting — it currently
  sells capture-by-crossing:

  > - Everyone plays on the same board, from opposite corners
  > - Your words are yours — you can't build on a rival's letters
  > - Hold the most tiles in a zone when its minute runs out for a bonus

### Fairness of the spawn

With capture gone, a zone nobody but the leader can reach is a gift rather
than a contest. Two refinements to `occupyZoneCandidates`, in order of value:

1. Prefer centres within `OCCUPY_ZONE_REACH` of **two or more** seats'
   frontiers; fall back to the current single-anchor rule only when no such
   patch exists.
2. Keep the "all 25 cells empty, clear of starts and other zones" requirement —
   including resolved zones, so the fight moves around the board rather than
   settling on one patch.

---

## 3. The wire: protocol v10

Both changes ride the existing `state` snapshot; no new message types. Bump
`PROTO` to 10 and add the appendix entry to
`docs/apple-port-notes/protocol.md`:

- `OccupyState.bonuses` (`[Int]`, per seat, decoded as zeros when absent).
- `OccupyZone` gains `slot`, `opensAt`, `closesAt`, `winner`, `counts`,
  `resolved`; a v9 zone decodes as a 3×3 permanent multiplier, which no longer
  exists — hence the version bump rather than a tolerant decode. A v9 board
  must not meet a v10 one in the random-match pool.
- `occupyApply`'s refusal set gains `notYours` and `throughRival`; both travel
  as their message text in `refused`, so nothing structural changes there.

Clients still judge locally with the same `occupyApply` before showing a word,
so a `refused` remains reachable only when someone genuinely got there first.

---

## 4. Work, in the order it should land

1. **Core rules** — `Occupy.swift`: owned runs, the borrow/span checks, value
   without the multiplier, capture deleted. Tests first; this is the half that
   can be proved without a screen.
2. **Zone lifecycle** — schedule and resolution as pure functions in
   `Occupy.swift`, plus `bonuses` and the new `OccupyZone` fields.
3. **Referee** — `HostSession`: spawn with the cut-off and the retry, resolve
   on tick, resolve at the whistle, `PROTO` to 10.
4. **Client** — `GameModel` / `Staging`: aim and staging restricted to your own
   letters, capture toast out, zone clock and live tally in, zone toasts.
5. **Chrome** — `BoardContentView` zone drawing, `GameChrome` zone line,
   `OCCUPY_INFO` rewrite.
6. **Docs** — protocol v10 entry, `core.md`'s value note,
   `apple-port-plan.md`'s Occupy line, the header doc at the top of
   `Occupy.swift` (it is the mode's real specification and currently describes
   the old rules in full).

### Tests

Changed or new, roughly the shape of the existing suites:

- `OccupyTests` — `captureByCrossing` becomes
  `borrowingARivalsLetterIsRefused`; new `aWordCantRunThroughARivalsTile`,
  `flushRivalWordsAreReadAndValuedApart`, `valueIsTheLongestWordOfYourOwn`.
- `OccupyTests / zones` — the 5×5 shape; the open/close schedule and the
  `MIN_WINDOW` cut-off; resolution by tile count with the tie going to nobody;
  the bonus landing in `scores`; an open zone resolving at the whistle;
  candidates under the two-seat preference.
- `OccupySessionTests` — a full cycle over a `MemoryMesh`: zone opens in a
  snapshot, both seats play into it, the host resolves at 60s and the winner
  and bonus ride the next snapshot.
- `OccupyPlayTests` / `StagingPlayTests` — aiming a gap at a rival letter is
  refused; a staged word dragged through a rival tile is refused; a word flush
  against a rival's lands.
- Snapshot tests (`BoardSnapshotTests`, `ScreenSnapshotTests`) need
  re-recording for 5×5 zones and the header's zone line.

---

## 5. Decisions still open

- **The bonus number.** 25 points is one good five-letter word (5 tiles × 5).
  Seven zones is therefore up to 175 points of swing in a game where a busy
  seat scores a few hundred — enough to matter, not enough to be the whole
  game. It is the one dial that decides whether minute eight is still live, so
  it wants a playtest before it is settled; the constant exists so it can move
  (`OCCUPY_ZONE_BONUS`).
- **Do zone tiles still read as special after the whistle?** The plan says no —
  a resolved zone is a scoreboard mark, not terrain. The alternative (a
  resolved zone keeps paying its holder a trickle) adds a snowball to a mode
  that no longer has a comeback mechanic, so it is a deliberate no.
- **Zone size against a two-player game.** 5×5 with two seats starting 8 cells
  apart is generous; if two-player games turn into a single scrum, the spawn's
  reach — not the zone's size — is the thing to tighten.
