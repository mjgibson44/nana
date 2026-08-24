# Word on Apple platforms

The native iPhone/iPad/Mac port, built to [`docs/apple-port-plan.md`](../docs/apple-port-plan.md).

## State

**Phases 0–2 are complete. Everything in phases 3 and 4 that doesn't need an Apple
Developer account is built — what's left in both is the GameKit call sites and the
hardware to test them on.** What runs today: Solo (both paces), the **Daily Deal**, and the guided
tutorial, playable on iPhone, iPad and Mac.

| Package / target | What it is |
|---|---|
| `Packages/WordCore` | The game core in pure Swift — **bit-exact with the web game** via golden fixtures generated from the TypeScript core (`npm run gen:fixtures`), so the same seed deals the same letters on both platforms. |
| `Packages/WordBoard` | The board's interaction brain, kept pure so it tests without a simulator (plan §11): the **gesture disambiguation state machine** (6pt slop, 350ms double-press, 300ms hold-to-drag, locked-board semantics, pointer-id filtering) and the **viewport math** (zoom clamps, pinch anchoring, shrink-only auto-fit, growth compensation, scroll-to-pan). |
| `Packages/WordNet` | The **battle wire protocol** over an injectable transport — roster and seat capacity, seat grace and re-entry, attack clamping/splitting, the referee, the v6 host-election handshake, and the version gate. Tests run over an in-memory mesh, so only the GKMatch adapter will need devices (plan §7.5). |
| `Word/` (app) | SwiftUI: a custom pan/zoom board (owning its offset is what lets zoom and its scroll correction land in one frame), a Canvas cell lattice with views only for occupied cells, one gesture pipeline feeding board and rack, the editing loop with undo/redo, the paced Solo session, the tutorial, home/stats/settings screens, synthesized audio + haptics, and save/restore across process death. `Board/BoardInputBridge.swift` is the one place that reaches past SwiftUI into UIKit/AppKit, for the three things SwiftUI won't report: the live pinch midpoint, the pointer's actual device kind, and Mac scroll wheels. |

```bash
cd apple/Packages/WordCore  && swift test   # core + golden parity fixtures
cd apple/Packages/WordBoard && swift test   # gesture machine + board geometry
cd apple/Packages/WordNet   && swift test   # battle protocol over a mock mesh
xcodebuild test -project apple/Word.xcodeproj -scheme Word \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO   # app tests incl. the zoom-out perf gate
```

(`CODE_SIGNING_ALLOWED=NO` is only needed until there's a developer account to
sign with — see phase 3 below. Drop it once a Team is set.)

CI (`.github/workflows/ci.yml`) runs the web tests, all three Swift packages on Linux, a
fixture-drift check (TS core changed → fixtures must be regenerated in the same commit),
and a resource-sync check (the bundled word pool must stay byte-identical to the web's —
its file order is determinism-critical).

Conventions and the porting API contract live in [`PORTING.md`](PORTING.md).

### The Daily Deal

One fixed deal a day, the same letters for everyone, no clock — `DailyDeal.swift` in
`WordCore` plus a row on the home screen. It works because `TileStream` grows its deal off
a *hidden* board rather than the player's, so one seed yields the same letters however
differently two people play them; Solo's own deal path grows tiles off the live board and
would diverge on the first move.

The knobs the plan leaves open (§16.3) sit together in `DailyRules` rather than scattered
through the code, because each is a product decision that wants playtesting:

| Knob | Default | Why |
|---|---|---|
| `resetHourUTC` | 8 | Midnight US Pacific / 9am Central European. UTC midnight — the obvious pick — flips the puzzle mid-afternoon in the US. **Must agree with the recurring leaderboard's occurrence boundary** when phase 3 lands. |
| `tileCount` | 30 | A fixed deal, not a timed run: the score should say how well you used the letters, not how fast you type. |
| `attemptsPerDay` | 1 | The daily-puzzle ritual. Interrupted games still resume — this stops restarting, not resuming. |

The seed is salted so the day's letters aren't derivable from the date alone (§8.4) — a
speed bump, not a lock, which is the posture the plan already accepts for v1. Results are
recorded against the day a game was *started* on and flagged `withinDay: false` if the
puzzle rolled over mid-game, so phase 3 knows not to submit them. Streaks are computed from
the *set* of days played, which is the shape §9.1's iCloud merge needs.

### Progression, leaderboards and achievements

Phase 3's logic layer, built so that the only thing left needing an Apple Developer account
is the GameKit call itself:

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
- **`Achievements.swift` — the launch fifteen (§8.3).** Every one falls out of a funnel the
  game already had (`finishGame`, `commit`, the overflow alarm). Reported as a percent,
  which GameKit is happy to receive twice — that idempotence is what makes re-reporting on
  sign-in safe. Six are battle-only and stay dark until phase 4 fills the battle fields of
  `GameReport`; nine can be earned today.

`Services/Progression.swift` binds them together and leaves the GameKit call sites as one
small protocol, `ProgressionSubmitter`, so all of the above tests without an account.
Storage is `LocalSyncStore` today; swapping in `NSUbiquitousKeyValueStore` once the iCloud
entitlement exists is a one-line change there and nothing anywhere else.

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

`GameKitTransport` implements `BattleTransport` over a real `GKMatch`. **It has never run
against one** — that needs an account and two devices — so treat it as the shape the §7.4
spike starts from rather than as working code.

### What's left, and what it's waiting on

- **Phase 3's Game Center half** needs an Apple Developer account, an App ID with the Game
  Center/iCloud capabilities, and test Apple IDs. What remains is genuinely small: implement
  `ProgressionSubmitter` with `GKLeaderboard.submitScore` / `GKAchievement.report`, add
  `GKLocalPlayer` auth (calling `Progression.signedIn(as:)` on success), the `GKAccessPoint`,
  the GameKit bundle whose leaderboard IDs must match `LeaderboardID`, and swap the sync
  store for iCloud's.
- **Phase 4's remaining half** is matchmaking and the spike. Match *formation* — party
  codes on iOS 26, invites below it — needs Game Center auth, so it waits on the account
  alongside phase 3. Then the §7.4 spike, which the plan puts in week one because its
  findings can resize the phase: 8-device mesh stability, and what actually happens to a
  backgrounded player (there is no documented API to rejoin an existing >2-player
  `GKMatch`, so re-entry goes through the host's `addPlayers` backfill — and whether a
  party code lands you back in the *live* match is undocumented, i.e. a spike question,
  not a mechanism).
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
    Game/                       #   model, Solo + Battle clocks, screen + chrome, tutorial
    Screens/                    #   router, home, doors/cards, stats, settings, lobby
    Services/                   #   audio synthesis, storage, settings, saved games,
                                #   Daily Deal results, progression, battle session,
                                #   the GKMatch transport
  WordTests/                    # app-layer rendering, editing + lifecycle tests
```
