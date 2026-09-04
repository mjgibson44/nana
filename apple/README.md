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
- **Words are permanent.** Nothing on the board moves, turns, comes back off, or undoes —
  so only real words are allowed down, in Solo as much as in Battle.
- **The pile is the only pressure.** Reach `PILE_LIMIT` (24) tiles in hand and the game
  ends on the spot, in either mode. The gauge under the header fills toward it in green
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

Retired with it: undo/redo, dragging tiles, the selected-word controls, the loose-tile
deadline, the Daily Deal, the tutorial, the stats and settings pages, and — since the
redesign owns every corner of the screen — Game Center's floating access point and the
achievement set behind it. Sound and
haptics stay on unless a stored preference says otherwise. Battle keeps its lobby,
codes and invites; its header shows the player's placing ("1st") instead of a score, and
the results screen carries the standings and the player's words.

Every screen is built from the same pieces (`Screens/TileText.swift`): words spelled in
tiles, one margin round the outside, one gap between sections, one gap between tiles.
The palette and spacing live in `Theme.swift`. Screens render offscreen in
`ScreenSnapshotTests` (PNGs in `/tmp/word-*.png`), and `WORD_AUTOSTART=solo` in the
launch environment opens straight onto a game so a simulator can be screenshotted.

| Package / target | What it is |
|---|---|
| `Packages/WordCore` | The game core in pure Swift — **bit-exact with the web game** via golden fixtures generated from the TypeScript core (`npm run gen:fixtures`), so the same seed deals the same letters on both platforms. |
| `Packages/WordBoard` | The board's interaction brain, kept pure so it tests without a simulator (plan §11): the **gesture disambiguation state machine** (6pt slop, 350ms double-press, 300ms hold — to drag, or to aim a gapped word through a placed letter — locked-board semantics, pointer-id filtering) and the **viewport math** (zoom clamps, pinch anchoring, shrink-only auto-fit, growth compensation, scroll-to-pan). |
| `Packages/WordNet` | The **battle wire protocol** over an injectable transport — roster and seat capacity, seat grace and re-entry, attack clamping/splitting, the referee, the v6 host-election handshake, and the version gate. Tests run over an in-memory mesh, so only the GKMatch adapter will need devices (plan §7.5). |
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

### The Daily Deal (retired from the app)

The mode is gone from the app, but `DailyDeal.swift` and `DailyRules` stay in `WordCore`
with their tests: the recurring leaderboard is already configured against them in App
Store Connect, and `Progression` still knows how to file a daily result should the mode
come back. The seed is salted so the day's letters aren't derivable from the date alone
(§8.4), and `TileStream` grows its deal off a *hidden* board so one seed yields the same
letters however differently two people play them.

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

`GameKitTransport` implements `BattleTransport` over a real `GKMatch`, and
`Matchmaking` forms one. Two roads in, ranked by what the OS can do (§7.3):

- **Party codes (26+)** — `GKGameActivity` issues a short shareable code and URL, and
  `findMatch` turns the party into a `GKMatch`. Worth knowing the code *format* is
  Apple's, not ours: two same-length parts joined by a dash, so `newBattleCode`'s five
  letters don't apply here.
- **Invites (everywhere)** — `GKMatchmakerViewController` in invite-only mode: friends,
  Messages threads, nearby players. The only road below 26, and the fallback above it.

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
