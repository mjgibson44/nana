# Time Tiles — the Apple platforms port

The native iPhone/iPad/Mac port, built to [`docs/apple-port-plan.md`](../docs/apple-port-plan.md).

**Naming:** the game ships as **Time Tiles** (§16.2 — "Word" is unsearchable on the App
Store), under the bundle id `dev.nana.TimeTiles`. Only the store-facing name changed: the
repo, the Xcode target, and the `WordCore` / `WordBoard` / `WordNet` modules keep their
names, exactly as plan §13 anticipated. The web app carries the same name.

## State

**Phases 0–2 are complete; phase 3 is code-complete and signing against a real team;
phase 4 needs matchmaking and its spike.** What's left in both is behavior that can only
be exercised on hardware with a real Apple ID — there has been no Game Center sandbox
since 2016 (TN2417). What runs today: Solo (both paces) and Battle's lobby and board,
built phone-first. The Mac target still compiles and runs the test suite, but the layout
is the phone's and the Mac is not a release target for now.

### The redesign (September 2026)

The iPhone app was reworked around a much smaller rule set and a minimalist, tile-lettered
dark UI. The rules, in one breath:

- **Build a word from the pile** by tapping letters (or typing, on a hardware keyboard).
  They line up in the word row, always on one line — past eight letters the tiles narrow
  rather than wrap.
- **The word row says whether it's a word** as you build it: green when it reads, red
  when it doesn't. A word with a gap in it is judged against the whole board — green if
  *some* letter down there would make it a word, red if none would — so the colour is a
  promise about what landing it would do, not a guess about the letters.
- **The first word** lands from the start square heading across, with the ✓ button that
  takes the gap button's place until it's down. It is the only word placed by fiat, and
  the only one that previews on the board as it's typed.
- **Every later word borrows a letter** already on the board: put a gap tile where the
  borrowed letter goes and tap that letter. The word arranges itself around it, across
  or down, whichever spells real words. There is no tapping the board to choose a
  square, no typing onto the board, and no direction to pick.
- **Or press and hold that letter** to see the word on the board before it lands: green
  where it would go if it reads, red if it doesn't. Sliding the finger carries the aim
  from letter to letter; letting go lands a green word. A red one stays up for a second
  — long enough to read what you spelled — and is then taken back with the reason
  ("XYZZY isn’t a real word"), the word still in the row, ready to fix.
- **Or build the word on the board.** Drag a tile out of the pile onto a square and it
  waits there, ghosted like the opener's preview, its slot in the pile empty; drag more
  beside it, tap one to take it back, drag it to another square, or drop it back on the
  pile. The ✓ lands them all as one word (`GameModel.confirmStaged`), under the same
  rules the row plays by — one line, no holes, joined to a letter already down (or the
  first word, on its start square), every run a real word — checked after the fact by
  `WordCore.judgeStaged`, since dropping tiles puts the word somewhere before it says
  what it is. The ghosts turn red when what they spell isn't a word, and a ✓ that can't
  land says why. While tiles are on the board the row can't land anything: confirm or
  clear them first.
- **Words are permanent.** Nothing on the board moves, turns, comes back off, or undoes —
  so only real words are allowed down, in Solo as much as in Battle.
- **The pile is the only pressure.** Reach `PILE_LIMIT` (24) tiles in hand and the game
  ends on the spot, in either mode, under every modifier — only the Daily is exempt
  (see below). The gauge under the header fills toward it in green
  and turns amber at 17 and red at 20; the pile is drawn as three rows of eight whatever it holds,
  so a full pile looks like the end. Solo opens on `SOLO_START_TILES` (16) and Battle on
  `BATTLE_OPENING_TILES` (12) — the app's own numbers, kept apart from
  `WordCore.ENDLESS_START_TILES` / `BATTLE_START_TILES`, which are the web game's and are
  held byte-identical to it by the parity fixtures. Each keeps exactly the share of the
  pile it had at thirty, so neither mode opens closer to buried than it used to.
- **A battle shows the whole field.** Under your own gauge is one row of small bars, one
  per rival, on the same scale and the same colours; a player who's out reads as a full
  red bar.

Under the pile are the actions on the word — clear it, add a gap (or ✓ the opener),
backspace — while **shuffle stands on its own to the right of the pile**, as tall as it:
it rearranges the tiles rather than acting on the word, and as one icon in four a mis-tap
there cost a word.

The header reads the score (or the battle placing), then what the clock is about to hand
you — "5 tiles in 24s", the count and the countdown as one sentence — then the pause and
menu buttons. The menu is the game's own screen of tile words, not a platform context
menu, and speed is no longer in it: a Solo game's pace is chosen on the way in
(`Screens/SoloSetupScreen.swift`), because picking it from the menu silently threw the
game away and dealt another.

Retired with it: undo/redo, the selected-word controls, the loose-tile deadline, the
Daily Deal, the tutorial, the stats and settings pages, and — since the redesign owns
every corner of the screen — Game Center's floating access point and the achievement set
behind it. (Dragging tiles onto the board came back afterwards, as a way of building a
word rather than the web's loose tiles: what's dropped is judged and landed by the ✓.) Sound and
haptics stay on unless a stored preference says otherwise. Battle keeps its lobby,
codes and invites; its header shows the player's placing ("1st") instead of a score, and
the results screen carries the standings and the player's words — straight under the
buttons, on the first screenful, rather than a scroll below them.

Every screen is built from the same pieces (`Screens/TileText.swift`): words spelled in
tiles, one margin round the outside, one gap between sections, one gap between tiles.
The palette and spacing live in `Theme.swift`. Screens render offscreen in
`ScreenSnapshotTests` (PNGs in `/tmp/word-*.png`), and `WORD_AUTOSTART=solo` in the
launch environment opens straight onto a game so a simulator can be screenshotted.

| Package / target | What it is |
|---|---|
| `Packages/WordCore` | The game core in pure Swift — **bit-exact with the web game** via golden fixtures generated from the TypeScript core (`npm run gen:fixtures`), so the same seed deals the same letters on both platforms. |
| `Packages/WordBoard` | The board's interaction brain, kept pure so it tests without a simulator (plan §11): the **gesture disambiguation state machine** (6pt slop, 350ms double-press, 300ms hold — to drag, or to aim a gapped word through a placed letter — locked-board semantics, staged tiles that lift on any board, pointer-id filtering) and the **viewport math** (zoom clamps, pinch anchoring, shrink-only auto-fit, growth compensation, scroll-to-pan). |
| `Packages/WordNet` | The **battle wire protocol** over an injectable transport — roster and seat capacity, seat grace and re-entry, attack clamping/splitting, the referee, the v6 host-election handshake, the v7 Occupy board and its placement round trip (v9: unbounded, with zones; v10: each
player's own words, and zones that open, close and pay out), and the version gate. Tests run over an in-memory mesh, so only the GKMatch adapter will need devices (plan §7.5). |
| `Word/` (app) | SwiftUI: a custom pan/zoom board (owning its offset is what lets zoom and its scroll correction land in one frame), a Canvas cell lattice with views only for placed cells, one gesture pipeline for board taps and pans, the word-building loop, the paced Solo session, the battle session and its results, the tile-lettered home and battle screens, synthesized audio + haptics, and save/restore across process death. `Board/BoardInputBridge.swift` is the one place that reaches past SwiftUI into UIKit/AppKit, for the three things SwiftUI won't report: the live pinch midpoint, the pointer's actual device kind, and Mac scroll wheels. |

```bash
cd apple/Packages/WordCore  && swift test   # core + golden parity fixtures
cd apple/Packages/WordBoard && swift test   # gesture machine + board geometry
cd apple/Packages/WordNet   && swift test   # battle protocol over a mock mesh
xcodebuild test -project apple/Word.xcodeproj -scheme Word \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO   # app tests incl. the zoom-out perf gate
```

(`CODE_SIGNING_ALLOWED=NO` keeps the test run working on a machine with no team
configured — CI, or a fresh clone before `Local.xcconfig` is filled in. With a team set you
can drop it, and `xcodebuild build -allowProvisioningUpdates` produces a properly signed
app with the Game Center and iCloud entitlements.)

CI (`.github/workflows/ci.yml`) runs the web tests, all three Swift packages on Linux, a
fixture-drift check (TS core changed → fixtures must be regenerated in the same commit),
and a resource-sync check (the bundled word pool must stay byte-identical to the web's —
its file order is determinism-critical).

Conventions and the porting API contract live in [`PORTING.md`](PORTING.md).

### The Daily

One board a day, the same one for everybody — and the same *position*, not merely the
same letters. `WordCore/DailyBoard.swift` builds the day out of a single hidden
crossword grown from the day's seed: one of that crossword's own words is left on the
board as the **seed word**, the rest of its letters are dealt, three of its remaining
cells are ringed as **targets**, and **par** is how many words it used.

The seed word is what makes the targets mean anything. The board has no origin —
`boardBounds` grows around whatever is played and `normalize` slides every generated
solution back to (0, 0) — so before something is down, "the target is at row 3, column
7" says nothing, and any target is covered by starting on top of it. With a word down,
the coordinate system is pinned and reaching a ring means building in a direction you
did not choose with letters you were given.

Everything the mode promises falls out of that construction rather than being asserted:
the targets are reachable because they are cells of a crossword the deal is known to
build, and par is achievable because that crossword achieves it — and beatable, because
the letters come from several ordinary overlapping words and there are normally tighter
arrangements. Par is derived, not tuned, so it is honest on every deal.

- **Scored on words, low being good.** Which fights the points scoring productively:
  `wordScore` is triangular and every run pays, so points want a densely crossed board
  with many runs while par wants few words. The move that serves both is one word laid
  across three others — four new runs for one stroke. The leaderboard is ranked on the
  packed pair (`dailyLeaderboardScore`), strokes first and points as the tiebreak.
- **No undo, and none needed to explain.** Words are permanent here as everywhere else,
  so a stroke is a word played. Staging is what softens it: tiles sit ghosted on the
  board and can be moved or cleared freely until the ✓.
- **It cannot be lost.** No clock, and the pile explicitly cannot bury it — the whole
  deal arrives at once and fills most of the pile, and nothing more is coming. The
  tension is your number against par, not a loss you get no second go at.
- **One go a day, and a day is picked back up rather than dealt again.** The puzzle
  isn't stored in the save blob — it is a pure function of the day's seed, so it is
  rebuilt and the saved board, pile and strokes are laid back over it.

`DailyDeal.swift` next door owns the calendar rather than the puzzle: which day is live,
when it rolls over, the salted seed (§8.4), and the streak. The recurring leaderboard is
configured against it in App Store Connect and `Progression` files a day's result
through the same funnel every other mode uses.

### Progression and leaderboards

Phase 3's logic layer. `Services/GameCenter.swift` now sits on top of it with the real
GameKit calls — auth, `GameKitSubmitter`, and `UbiquitousSyncStore` putting the merge below
on iCloud:

- **`Progress.swift` — the cross-device merge (§9.1).** iCloud's key-value store is
  last-writer-wins *per key*, so one shared stats blob would eat itself: play on the phone
  Monday and the iPad Tuesday and whichever syncs last erases the other. Each device instead
  owns one blob and only ever writes its own; reading merges all of them. That turns a
  destructive race into arithmetic — counters sum, bests take the max, day sets union. It's
  why streaks are stored as *the days played* rather than a number: a length can't be
  merged, a set can.
- **`Leaderboards.swift` — the signed-out queue (§7.1).** Signed-out is a designed state,
  not an error: the web game needs no account and the port must not regress that. Scores
  earned signed out are held (best-per-board-occurrence only) and flush when auth arrives.
  Queueing happens *before* the send, so a crash mid-submission is lossless.
- **`GameReport.swift` — what a finished game saw.** One record covers Solo and Battle,
  which is what lets a single funnel (`GameModel.onFinish` → `Progression.record`) serve
  both.

There are no achievements: the launch set was cut along with Game Center's floating access
point, so the only thing the app posts is a score.

`Services/Progression.swift` binds them together and leaves the GameKit call site as one
small protocol, `ProgressionSubmitter`, so all of the above still tests without an account —
which is what kept the rules testable while the account was pending, and what keeps them
testable in CI now that it isn't. `UbiquitousSyncStore` supplies the real iCloud store;
`LocalSyncStore` remains for tests and for a device with no iCloud account.

### Battle

The protocol landed in #48; this is the rest of it — the parts that make a battle
actually play:

- **`BattleRun`** is battle's clock: a batch lands in the pile every
  `BATTLE_DRIP_SECONDS`, and the only losing condition is letting the pile past
  `BATTLE_PILE_LIMIT`. The load-bearing detail is that a drip's size is **pure in its
  index**, not the wall clock — players' clocks drift, so drip *k* has to be drip *k* on
  every screen for everyone to draw the same batch from the shared stream.
- **Battle in `GameModel`**: the locked board (words are permanent, so only real words
  land), the shared deal, and the attack a word owes. Attacks price only the *growth* —
  stretching HEART to HEARTS earns the S, not the whole word again — and travel as counts:
  the receiver draws its own letters from a private `<seed>/attacks/<id>` stream, so tiles
  never cross the wire.
- **`BattleSession`** binds `WordNet`'s host/client sessions to the board, and takes its
  transport rather than making one. That's what lets a `MemoryMesh` play a whole battle in
  tests — two sessions, two boards, one mesh — and it's why the GameKit adapter is a
  drop-in that changes nothing below it.
- **`BattleLobbyScreen`**: the roster from the host's snapshot, including seats being
  *held* for a dropped player. A battle plays on around a disconnect rather than pausing,
  so a held seat has to read as held, not gone.

### Solo modifiers: prize cells

A second row on the Solo setup screen — **Clear**, **Gold**, **Salvage** — rather than a
door of its own, because each is the same game offering you something different. The
rules are pure Swift in `WordCore/Prizes.swift`, and the two live modifiers are one
mechanic with two payouts (`SoloModifier.prize`), not two mechanics.

**These replaced Wildfire**, which is retired. Fire's good idea was that the board should
give you somewhere to *go* — Solo's freedom is calm, and calm is also why a long run has
no shape. Its bad idea was that the somewhere was a punishment: play well and nothing
happened, play badly and the board closed in, so the sensible line was to ignore the fire
for as long as you could afford to. A prize inverts the sign and keeps the geometry.

- **A square lights up every `PRIZE_SPAWN_SECONDS` (15)** on empty ground within
  `PRIZE_REACH` (2) of a tile already down, never more than `PRIZE_MAX_LIVE` (2) at once.
  Close enough to reach with one word; far enough that reaching it is a decision about
  where to build. The first comes sooner (`PRIZE_FIRST_SPAWN_SECONDS`, 8) so a game shows
  what the modifier does inside the opening phase.
- **It lives `PRIZE_SECONDS` (20) and then vanishes, costing nothing.** An ignored prize
  is an opportunity missed, never a punishment — there is no channel for one to hurt you.
- **Claim it by landing a tile on that exact square.** Exact, not adjacent, and
  deliberately the opposite of dousing a fire: a punishment had to be answerable with
  whatever you happened to hold or it was a coin flip, while a reward should be earned by
  putting a letter where you meant to.
- **What it pays decays with its own clock** — full price the instant it appears, sliding
  linearly to a floor as the timer runs out. Linear because the player has to price it at
  a glance: half the time left is half the prize. This is the whole mechanic. A gold
  square is not points waiting for you, it is a bid to change what you were about to play
  *right now*, and the longer you think the less it is worth.

| | pays | top | floor |
|---|---|---|---|
| **Gold Rush** (`.points`) | points, into the banked bonus | `GOLD_TOP_POINTS` (100) | `GOLD_FLOOR_POINTS` (10) |
| **Salvage** (`.relief`) | tiles off your pile | `SALVAGE_TOP_TILES` (10) | `SALVAGE_FLOOR_TILES` (1) |

The top price for gold is above what any word pays, on purpose: a square worth less than
the word already in your hand changes no decisions.

**Prizes run on wall time, not the drip's rounds.** Wildfire could ride the round boundary
because it *was* the round; twenty seconds rounded to the nearest fifteen would put every
deadline at an arbitrary point inside a round, with two counters drifting against each
other on screen. So each square carries its own seconds left and `prizeAdvance` takes the
elapsed time — which is also why the UI heartbeat drives it (`GameModel.advancePrizes`)
rather than the drip's expiry. Seconds left rather than deadlines, like the round clock in
`SavedSoloGame`: a game paused, or picked back up tomorrow, must not find its squares
expired on arrival, and time behind a card is never charged to a prize.

**The pile is the pile again.** Wildfire needed `WILDFIRE_PILE_RELIEF` because it fed the
gauge from a second source; nothing does now — gold never touches the pile and salvage
only ever takes off it — so `PILE_LIMIT` and its amber and red mean one thing everywhere.

Both the field and the spawn stream's position ride the save blob (`PrizeField.spawns`),
so a game restored across process death comes back to the squares that were lit, with the
seconds they had left, and goes on lighting the ones it would have lit.

### Battle's room settings

Two rules a room agrees on before it deals, both the host's to pick and everyone's to
play by. They ride the host's snapshot (`BattleState.boardView`, `BattleState.modifier`,
protocol v11) rather than each player's own settings, because a room where two people
are playing different games is not a room — a client's stored setup is never consulted,
and the lobby shows every player the rule they will actually play under. The host edits
it in the lobby and only in the lobby: a rule changed mid-game would leave each board on
a different one for the length of a broadcast.

- **Squares** — the same prize cells Solo's setup sheet offers, applied to every board in
  the room. On separate boards **the timing is shared and the square is local**, and that
  needs no wire at all: every player's clock starts at the same deal and counts the same
  seconds, so a gold square appears on every screen at the same moment and is worth the
  same to whoever reaches it first. Where it *sits* is necessarily each board's own
  business, since they are different boards. Gold's points feed `bankedBonus`, which is
  the score already reported to the room; Salvage clears the pile Battle eliminates you
  for overflowing. A spectator's board is never lit — they have nothing to claim with.
- **Board** — `separate` (Battle as it has always played) or `shared`, which is the one
  idea worth keeping out of Occupy now that its door is closed: everyone building on the
  same squares, where a rival's word is a wall.

**`shared` is not offered yet** (`BATTLE_SHARED_BOARD_ENABLED`), and the flag is there
because the referee is ready and the board is not. Everything the *protocol* needs is
done and tested — the host deals an `OccupyState` for a shared room, seats it four
(`HostSession.maxPlayers`; the layout starts each player in a corner and there are four
corners), referees placements against it with `occupyApply`, and keeps Occupy's zones,
ten-minute clock and stall rule out of it. What is missing is the app half: `GameModel`
still routes every Battle landing down its own path, which keeps a local board and knows
nothing about owners, seats or the host's answer.

Finishing it is one deliberate refactor rather than a patch. The model asks
`mode == .occupy` in about thirty places, and roughly two thirds of those are really
asking *"is this board shared?"* — whose letters may I cross, where does the opener go,
which runs are mine — while the rest are really asking *"is this Occupy?"* — tile-value
scoring, the zone clock, the whistle. Splitting that one question into two is the work,
plus a commit path that is Occupy's board round trip with Battle's scoring, attacks and
elimination on top. Shipping the switch before that would deal a room where the host has
a shared board and every client plays a private one, which is worse than no switch.

### Occupy

**The door is closed** (`OCCUPY_DOOR_ENABLED`) — the mode is not deleted, and its code,
protocol and tests all stay live and exercised, because its best idea is being folded
into Battle as the shared board above rather than kept behind a door of its own. What
follows describes the mode as built.

The third door: two to four players on **one shared board**, each opening from their own
corner of the middle ground (two players sit diagonal), fighting over the same squares
until the clock runs out. The rules are pure Swift in `WordCore/Occupy.swift`, and the
whole thing is designed around one function, `occupyApply`, which the host runs as the
referee and every client runs on its own words — so what a player sees the instant they
let go and what the host decides can only differ about a square someone else reached
first.

- **The board has no edge.** It is laid out in the solo board's own square
  (`OCCUPY_FRAME`, 33) and grows past it exactly as a solo board does; the frame only
  fixes where the start squares are and what the board turns about. Two players open
  eight cells apart on the diagonal either side of the middle, three or four ten
  (`occupyStartCell`, `occupyStartSpread`) — the same distances the old fixed boards
  had — and the opening view is centred on the middle with every seat's corner in it
  (`BoardCamera.Opening.centred`). **Every seat sees the board turned so its own start
  square is top-left of the middle** (`occupyRotation`, quarter turns of the host's board
  about the frame's centre — the formulas are linear, so a cell past the frame turns as
  well as one inside it), so everyone opens from their top-left and writes left to
  right, toward the middle. The host, the wire and the client's own copy stay in the
  host's frame; only what is drawn and typed on is turned
  (`GameModel.refreshOccupyView`), and a word is turned back before it's judged, kept or
  sent (`commitOccupy`). Letters are always drawn upright, so a rival's words read
  backwards on your screen — like a Scrabble board seen from across the table — and a
  run counts as a word if it reads as one in **either direction** along its line
  (`occupyIsWord`), on the client and the referee alike.
- **Your words are your own.** Every later word borrows a letter through a gap tile,
  exactly as everywhere else — and it has to be a letter you already own. A rival's tile
  can't be borrowed (`OccupyRefusal.notYours`) and can't be built through
  (`throughRival`); a tile's owner is stamped when it lands and never changes again. Two
  players' tiles *may* sit flush against each other, and the line they make is not read
  as one word: a run is a maximal **same-owner** line (`occupyOwnedRuns`), so each side
  of a seam is judged and valued on its own — the seam is a border, not a word. One walk
  answers both what a word has to be to land and what it is worth, so the two can't
  drift apart. A letter already in both an across and a down word has no free direction,
  so crossing your own long word's letters is still how you defend it; a rival's is
  defended by being theirs.
- **Value.** Every tile is worth the length of the longest word **of its owner's** that
  it sits in, and you score the tiles you own. Two 3-letter words are worth 12; one
  5-letter word is worth 20; so spamming short words loses to building long ones, and a
  rival's letter next door adds nothing to either of you. The header shows your value;
  under it, the pile gauge is replaced by a **balanced bar** of everyone's share
  (`OccupyBarView`), you first in green, each rival in their own colour (`SeatColors`),
  the same colour their tiles wear on the board — with **everyone's name and points
  under the bar** in the same colours, so the bar says who's ahead and the numbers say
  by how much.
- **Zones.** A **five-by-five zone** opens a minute into the game and stays open for a
  minute; at the whistle whoever owns the most tiles inside it banks `OCCUPY_ZONE_BONUS`
  (25 points), a tie banks nothing, and fifteen seconds later the next one opens. Seven
  run in a ten-minute game — no zone is opened with less than half a minute of match
  clock left, so the end of a game belongs to the words already on the board — and one
  still open when the game ends is decided there. The host opens and closes them
  (`HostSession.spawnOccupyZones` / `closeOccupyZones`, the places rolled off the game's
  seed so a replay grows the same ones) on empty ground within `OCCUPY_ZONE_REACH` (6)
  of a letter already down or of a start square nobody has opened from yet, clear of
  every start square and every other zone, and **preferring ground two or more seats can
  reach** — with nothing to capture, a zone one player alone can play into is a gift
  rather than a contest (`occupyZoneCandidates`). A slot with nowhere to go is retried
  for ten seconds and then given up, not saved up. Zones ride the snapshot
  (`OccupyState.zones`) with their own lifecycle — `slot`, `opensAt`, `closesAt`,
  `winner`, `counts`, `resolved`, the times in seconds since the deal so every screen
  runs the countdown off the start it already has — and what they pay is banked in
  `OccupyState.bonuses`, which `scores` includes. On the board an open zone's squares
  are a shade lighter than the lattice, with an edge round the patch and the seconds
  left on its middle square; a decided one settles into its winner's colour with what it
  paid (`BoardContentView`). A line under the bar says how the open zone stands and how
  long is left, and every opening and whistle gets a banner.
- **The pile** is dealt to `OCCUPY_HAND` (24) and refilled after every word — grown off
  the shared board as it stands, so every letter has a known way on — and never buries
  anyone.
- **The end.** Ten minutes (`OCCUPY_SECONDS`), whatever the size of the field; or early,
  once nobody has placed a word for a full minute — with a thirty-second opening grace
  during which the stall clock doesn't run. The header turns the last twenty seconds of a
  stall into a visible countdown. Most value wins; ties go to zones taken, then to
  quadrants held (whoever owns more tiles in a quadrant of the frame), then to whoever
  reached their score first.
  A player who leaves ranks last whatever they own.

Over the wire it's protocol **v7**, reshaped in **v9** (the frame in place of a size,
and the zones in the snapshot) and again in **v10** (nothing changes hands, and a zone
is a minute-long contest with a winner and a bonus): a client sends `place` (the new tiles and the borrowed
squares — the outcome, not the picks), the host judges it against its board and
dictionary, broadcasts the whole board in the next `state`, and only *then* answers the
sender with `placed` — so a word a player has already been shown is never taken back for
the instant between the answer and the board that agrees with it. A `refused` takes the
word back off the sender's board, puts the letters dealt for it back, returns the ones it
spent, and puts the word back in the row to try again. Scores are the board's, so no
`progress` reports travel in this mode; the two clocks are the host's alone, and each
screen shows its own reading of them. `WORD_AUTOSTART=occupy` opens straight onto a board
against a stand-in rival on an in-memory mesh, for screenshots.

`GameKitTransport` implements `BattleTransport` over a real `GKMatch`, and
`Matchmaking` forms one. Two roads in for friends, ranked by what the OS can do (§7.3):

- **Party codes (26+)** — `GKGameActivity` issues a short shareable code and URL, and
  `findMatch` turns the party into a `GKMatch`. Worth knowing the code *format* is
  Apple's, not ours: two same-length parts joined by a dash, so `newBattleCode`'s five
  letters don't apply here.
- **Invites (everywhere)** — `GKMatchmakerViewController` in invite-only mode: friends,
  Messages threads, nearby players. The only road below 26, and the fallback above it.

And a third for strangers — **random matches**, two buttons on the Battle screen and
the same two on Occupy's:

- **DUEL** is exactly two players; **PARTY** asks Game Center for at least three and
  takes up to eight in a Battle, four in Occupy. Both go through Game Center's
  rules-free automatch, headless (`GKMatchmaker.findMatch`), so the search is drawn in
  the game's own tiles and CANCEL is `GKMatchmaker.cancel`. `GKMatchRequest.playerGroup`
  is the whole of the pooling: a stable hash of
  `timetiles/<battle|occupy>/<duel|party>/v<PROTOCOL_VERSION>` (`MatchPool`), so a
  Battle never meets an Occupy game, a duel never meets a party and — with no sandbox —
  a newer build never meets an older one (protocol is v9 as of the Occupy reshape).
- **Nobody opened the room, so nobody is its host.** Everyone enters as a client; if no
  `host` announcement arrives within a two-second claim window, the lowest
  `gamePlayerID` stands up a host session in its client's place
  (`BattleSession.becomeHost`, off `ClientEvents.onShouldHost`). Lowest id wins if two
  ever claim: a client trades its host only for a lower announcer, and a host that
  hears a lower one yields (`HostEvents.onYield`). The host repeats its announcement
  once a second to anyone connected but unseated, and a client re-greets on any
  announcement while the snapshot has no seat for it, so a hello that beat the host
  session into existence is retried rather than lost. In the lobby a lost host simply
  triggers another election; mid-game the lobby still dies with its host.
- **Nobody presses START either.** The rule lives in `HostSession` (`AutoStartRule`):
  a duel deals the moment its second seat fills; a party once `PARTY_IDLE_SECONDS`
  (20) pass with nobody new arriving — and with two if a third came and went, rather
  than stranding the pair. Either way a `START_COUNTDOWN_SECONDS` (5) countdown rides
  the `state` snapshot (`BattleState.countdown`, the v8 wire change) so every screen
  counts the same seconds; a field that shrinks below two cancels it. As the countdown
  begins every device calls `finishMatchmaking`, closing the door; a party's host had
  held it open with `addPlayers` until then. A random lobby whose host is left alone
  for ten seconds is searched again automatically (`onAbandoned`).
- Strangers get a shorter mid-game seat grace (10 s, not 30) and a lobby that turns
  away anyone who lands after the deal, since there is no road back in for them.

All of it above the adapter plays out over `MemoryMesh` in CI (`BattlePlayTests`,
`SessionTests`). What only devices can answer: whether `findMatch` returns a party at
three or waits to fill, whether GameKit keeps filling after it returns and whether
`addPlayers` pairs with fresh searchers, how `expectedPlayerCount` behaves for a player
who never connects (forming is settle-timer based, so it only affects the "N of M"
line), whether `match.players` shrinks on a disconnect (the transport keeps its own
set either way), and how the two-second claim plus five-second countdown feel.

Everything the web game ran a broker, STUN and TURN for is Apple's problem from here.

**None of it has formed a match.** That needs a signed-in Apple ID on real hardware — no
sandbox (TN2417), and real-time matches are reported broken in the simulator. It compiles
for both platforms against the documented API; treat it as the shape the §7.4 spike starts
from rather than as working code.

### Game Center

The shape follows §7.1: **signed-out is a designed state, not an error.** Auth starts at
launch and blocks nothing — Solo, the Daily Deal and the tutorial never ask about it, and
anything earned meanwhile is held and flushed if sign-in later succeeds. Only Battle,
which genuinely needs an identity, turns anyone away, and it says which of three reasons
applies: not signed in, still signing in, or Screen Time restricting multiplayer — the
last being its own state because retrying can't fix it.

Two GameKit details the service exists to absorb: the authenticate handler can fire more
than once (the player can sign in or out from Settings), and it sometimes hands back a
view controller that *must* be presented — ignoring it strands the player signed out with
no way forward.

Signing is per-developer: `bootstrap.sh` copies `Local.xcconfig.example` to
`Local.xcconfig` (gitignored) for your Team ID. It goes through an xcconfig rather than
Xcode's UI because `xcodegen generate` would wipe the latter; entitlements live in
`project.yml` for the same reason, since XcodeGen owns the generated `.entitlements` file
and overwrites anything hand-written there.

**Still to do, and only doable in Xcode's UI:** create the GameKit bundle (File → New →
File → GameKit) holding the leaderboard definitions, which syncs to App Store Connect. The
identifiers it must match are already fixed in code — `LeaderboardID` (four boards, one the
Daily Deal's *recurring* 24h/24h board) — and a test asserts those strings don't drift.

### Shipping a build

```bash
./apple/tools/release.sh ios            # archive + export an .ipa
./apple/tools/release.sh ios upload     # ...and send it to App Store Connect
./apple/tools/release.sh macos          # a .pkg for the Mac App Store
```

Both platforms archive, export and sign cleanly today — verified end to end, producing a
distribution-signed `Time Tiles.ipa` carrying `beta-reports-active` (the TestFlight
entitlement) alongside Game Center and iCloud KVS.

The build number comes from
[`tools/next-build-number.py`](tools/next-build-number.py), not a hand-maintained field:
the **commit count**, raised past the highest build App Store Connect already holds. The
count alone almost works — it needs no maintenance and rises on its own — but it is not
monotonic across a squash merge, which collapses a branch's commits into one. #49 went up
as build 60 from a 64-commit branch that landed as main's 56th commit, so the next four
uploads would have collided with builds already accepted. Asking what's up there is the
rule the number is actually subject to, and it needs no constant to keep in step.

```bash
./apple/tools/next-build-number.py --explain   # the number, and how it got there
```

That also means `CFBundleVersion` and `CFBundleShortVersionString` have to *reference* the
build settings — XcodeGen otherwise writes literal defaults that silently override them,
and every upload arrives as build 1.

**Before the first upload**, two things that can't be done from the CLI:

1. An **app record** in App Store Connect for `dev.nana.TimeTiles` (Apps → +). Apps can't
   be created by the API.
2. An **App Store Connect API key** (Users and Access → Integrations). Save the `.p8` as
   `~/.appstoreconnect/private_keys/AuthKey_<KEYID>.p8` — **it downloads exactly once**,
   and a lost one has to be revoked and replaced — then put its two ids in
   `apple/Local.env` (gitignored; copy `Local.env.example`). Without them the script stops
   after building the package, which you can still drag into Transporter.

### Shipping from CI

Merging to main is the release. Any push to main that touches `apple/` runs
[`release.yml`](../.github/workflows/release.yml): it runs the app tests, archives,
exports, validates and uploads to TestFlight, on a macOS runner with no laptop involved.
The Actions tab's **Release** workflow also takes a manual run, with a switch to build
without uploading when you just want to know it still archives.

Everything signing needs is in the repository's Actions secrets, put there once by:

```bash
./apple/tools/setup-ci.py --dry-run   # what exists, what it would create
./apple/tools/setup-ci.py             # create it, set the secrets
```

It issues the distribution certificate through the App Store Connect API rather than
Xcode's UI — same reason `setup-gamecenter.py` exists — by generating a key pair here and
sending Apple only the CSR. Six secrets come out of it: `APPLE_TEAM_ID`, `ASC_KEY_ID`,
`ASC_ISSUER_ID`, `ASC_KEY_P8`, `APPLE_DIST_CERT_P12` and `APPLE_DIST_CERT_PASSWORD`.

**The certificate's private key exists in exactly one place**: `apple/.release/ci/`
(gitignored). Apple never had it and can't reissue it. Lose it and the certificate is
scrap — you revoke it and run the script again, which is survivable, but there are only
three distribution certificates to go around. Note that `.release/` is otherwise build
output: `release.sh` only clears the archive and export directories inside it, but a
blanket `rm -rf apple/.release` takes the key with it.

The export signs **manually** on the runner. Under automatic signing, an API key with
no Apple ID behind it makes Xcode reach for Apple's *cloud-managed* distribution
certificate, and the export dies with "Cloud signing permission error" when the key
isn't allowed one — then finds no App Store profile to fall back on. So
[`tools/ensure-profile.py`](tools/ensure-profile.py) finds or creates an App Store
provisioning profile through the API, paired with whichever distribution certificate
is actually in the keychain, installs it, and `release.sh` names it in the export
options. A laptop signed into Xcode with no API key still exports automatically.

Two things the runner can't do:

- **The Mac build.** A `.pkg` needs a Mac Installer Distribution certificate as well as
  the Apple Distribution one, so `./apple/tools/release.sh macos upload` stays a local
  command.
- **Create the app record.** Still Apps → + in App Store Connect, once, by hand.

The runner writes the same gitignored `Local.xcconfig` and `Local.env` a developer keeps,
so the release script can't tell a laptop from a runner — there is one release path, not a
CI copy of one that drifts. What makes that possible on a machine with no Apple ID signed
in is `xcodebuild`'s API-key authentication: given the `.p8`, it issues and downloads the
provisioning profile itself.

The app icon is generated from the game's design tokens by
[`tools/make-icon.swift`](tools/make-icon.swift) — kept as a script so it's reproducible
rather than a mystery binary. It is honestly a placeholder: the game's visual language
rather than a designed mark. Fine for TestFlight, worth replacing before the App Store.

### What's left, and what it's waiting on

- **Phase 3 needs exercising, not writing.** The app signs with Game Center and iCloud KVS
  entitlements in the binary (verified: `codesign -d --entitlements`), but *none of the
  runtime behavior has been seen work* — the sign-in sheet, a score landing on a real
  board, two devices merging through iCloud. That needs the GameKit
  bundle (below) and test Apple IDs. Note unreleased leaderboards are visible to friends of
  test accounts (TN2417).
- **The §7.4 spike is the last unknown**, which the plan puts in week one precisely because its
  findings can resize the phase: 8-device mesh stability under a star protocol, and what
  actually happens to a backgrounded player. There is no documented API to rejoin an
  existing >2-player `GKMatch`, so re-entry goes through the host's `addPlayers` backfill —
  and whether a party code lands you back in the *live* match is undocumented, which makes
  it a spike question rather than a mechanism. Everything the spike needs to run is now
  built; it needs devices and test Apple IDs.
### Game Center configuration

```bash
./apple/tools/setup-gamecenter.py --dry-run   # report what's missing
./apple/tools/setup-gamecenter.py             # create it
```

Idempotent, and it lives in the repo rather than a web form because the identifiers have
to stay in lockstep with what the app submits against — `LeaderboardID` and
`Matchmaking.battleActivityID`. A drifted identifier doesn't fail loudly; the score
just silently never arrives.

Currently configured: the `battle` activity (party codes, 2–8 players) and four
leaderboards. Achievements already created in App Store Connect are left alone — the
script only ever adds — so any from the retired set stay there, unused, until they're
removed by hand.

**The Daily Deal board is the one to be careful with.** It's recurring — 24h duration,
daily rule — and its start instant has to agree with `DailyRules.resetHourUTC`, or players
in different time zones submit *different puzzles* into the same occurrence. The script
anchors it on the next reset hour for that reason; App Store Connect won't accept a start
date in the past, so it can't simply be a fixed constant.

Two quirks the API doesn't document well, both discovered the hard way: `recurrenceDuration`
rejects `P1D` and wants a duration with time components (`PT24H`), and `recurrenceRule` is
an RRULE (`FREQ=DAILY;INTERVAL=1`), not a duration.
- **Phase 5's input bridges are in** (`Board/BoardInputBridge.swift`): pinch now re-aims at
  the fingers' *live* midpoint every frame rather than the one it started at, so a pinch
  that travels pans the board the way the web's does; iOS reads the real `UITouch.TouchType`,
  so an iPad trackpad gets the mouse rules (no hold-to-drag) instead of being assumed to be
  a finger, and Pencil is now classified as pen deliberately rather than by omission; and
  macOS scroll wheels and two-finger trackpad scrolls pan the board.

  The bridge is a *sensor, not a driver* — SwiftUI still recognizes the pinch and still owns
  the drag pipeline, so if the bridge never attaches, behavior degrades to exactly what
  shipped before it. **Still unverified without hardware**: that the touch-type probe always
  observes a touch before SwiftUI's `DragGesture` reports it (an ordering assumption about
  window-attached recognizers), and the feel of both on a real trackpad and a real Pencil.

## Picking it up on a Mac

```bash
./apple/bootstrap.sh
```

That installs XcodeGen if needed, generates `Word.xcodeproj` from
[`project.yml`](project.yml) (the checked-in source of truth — the generated project
stays out of git), and opens it. First time only: pick your Team under
Signing & Capabilities. Then Run — the game screen deals through WordCore and loads
the bundled dictionary (`public/dictionary.txt` is referenced from the web app
directly, so the platforms can't drift).

Next up is phase 3's Game Center half once the developer account is in place, or the
`GKMatch` adapter behind `WordNet`'s `BattleTransport` for phase 4. The notes in
`../docs/apple-port-notes/` remain the source of truth: `ui.md` for interaction
and `protocol.md` for the wire format, both with file:line references into the
web app.

## Layout

```
apple/
  PORTING.md                    # conventions + API contract the port follows
  Packages/WordCore/            # the game core (SPM, no dependencies, Linux-testable)
    Sources/WordCore/           #   one file per TS module (plus DailyDeal.swift, new here)
    Tests/WordCoreTests/        #   ported vitest suites + golden parity fixtures
  Packages/WordBoard/           # board interaction logic (SPM, Linux-testable)
    Sources/WordBoard/          #   GestureMachine + BoardGeometry (pure, no SwiftUI)
    Tests/WordBoardTests/       #   exhaustive gesture + viewport-math suites
  Packages/WordNet/             # battle protocol (SPM, Linux-testable, no GameKit)
    Sources/WordNet/            #   Protocol + HostSession/ClientSession + MemoryTransport
    Tests/WordNetTests/         #   protocol, roster, grace, attacks, referee, election
  Word/                         # the app target (SwiftUI)
    Board/                      #   camera, board rendering, pointer surface,
                                #   the UIKit/AppKit input bridge
    Game/                       #   model, Solo + Battle clocks, the game screen, its
                                #   chrome (header, gauge, word row, pile, actions),
                                #   overlays and the results screen
    Screens/                    #   router, home, battle entry + lobby, and the tile
                                #   lettering every screen is built from
    Services/                   #   audio synthesis, storage, settings, saved games,
                                #   progression, battle session, Game Center auth,
                                #   matchmaking, the GKMatch transport
  WordTests/                    # app-layer rendering, editing + lifecycle tests
```
