# Word on Apple platforms

The native iPhone/iPad/Mac port, built to [`docs/apple-port-plan.md`](../docs/apple-port-plan.md).

## State

**Phase 0 + Phase 1 are complete; phase 2a (board + unified gesture layer) is built.**

`Packages/WordCore` is the full game core in pure Swift — board rules, generator,
pacing/attack tables, placement engine, battle referee/codes/tile-stream, tutorial
script, sound-cue tables, and persistence models — **bit-exact with the web game**:
golden fixtures generated from the TypeScript core (`npm run gen:fixtures` at the
repo root) replay in the Swift tests, so the same seed deals the same letters on
both platforms.

`Packages/WordBoard` is the board's interaction brain, kept pure so it tests in CI
without a simulator (plan §11): the **gesture disambiguation state machine**
(pointer events in, intents out — 6pt tap slop, 350ms double-press, 300ms
hold-to-drag preview, locked-board semantics, pointer-id filtering) and the
**viewport math** (zoom clamps, pinch anchoring, shrink-only auto-fit,
board-growth scroll compensation), each with an exhaustive Swift Testing suite.

The app target's `Word/Board` + `Word/Game` are the phase-2a SwiftUI layer: a
custom pan/zoom board viewport (owning its offset is what lets pinch zoom and its
scroll correction land in the same frame), a Canvas-drawn cell lattice with real
views only for occupied cells (the §11 zoom-out perf gate is a measured XCTest in
`WordTests`, ~20ms for a full 33×33 board offscreen), and one gesture pipeline
feeding board and rack alike. Solo chrome (clocks, scoring UI, undo, tutorial,
settings) is phase 2b.

```bash
cd apple/Packages/WordCore && swift test    # core + golden parity fixtures
cd apple/Packages/WordBoard && swift test   # gesture machine + board geometry
xcodebuild test -project apple/Word.xcodeproj -scheme Word \
  -destination 'platform=macOS'             # board render perf gate (Mac only)
```

CI (`.github/workflows/ci.yml`) runs the web tests, both packages' Swift tests, a
fixture-drift check (TS core changed → fixtures must be regenerated in the same
commit), and a resource-sync check (the bundled word pool must stay byte-identical
to the web's — its file order is determinism-critical).

Conventions and the porting API contract live in [`PORTING.md`](PORTING.md).

Known phase-2a gaps to close on-device during 2b (all flagged inline in code):
pinch-pan tracks the gesture's *initial* midpoint (live-midpoint tracking needs a
`UIPinchGestureRecognizer` bridge — the math in `WordBoard.PinchAnchor` already
takes a live midpoint), Apple Pencil is classified as touch (correct behavior,
coarser than the web's three-way split), and macOS trackpad scroll-to-pan is not
wired (drag-to-pan and pinch work; scroll-wheel events need an NSEvent bridge —
phase 5 Mac polish).

## Picking it up on a Mac (phase 2 — the SwiftUI app)

```bash
./apple/bootstrap.sh
```

That installs XcodeGen if needed, generates `Word.xcodeproj` from
[`project.yml`](project.yml) (the checked-in source of truth — the generated project
stays out of git), and opens it. First time only: pick your Team under
Signing & Capabilities. Then Run — the placeholder screen deals a seeded puzzle
through WordCore, shows the rack and the hidden solution, and loads the bundled
dictionary (`public/dictionary.txt` is referenced from the web app directly, so the
platforms can't drift).

Then phase 2 in the plan: board + the unified gesture layer first (§6.2 lists the four
hard problems and the notes in `../docs/apple-port-notes/ui.md` carry the full
interaction inventory with file:line references into the web app).

## Layout

```
apple/
  PORTING.md                    # conventions + API contract the port follows
  Packages/WordCore/            # the game core (SPM, no dependencies, Linux-testable)
    Sources/WordCore/           #   one file per TS module (see PORTING.md map)
    Tests/WordCoreTests/        #   ported vitest suites + golden parity fixtures
  Packages/WordBoard/           # board interaction logic (SPM, Linux-testable)
    Sources/WordBoard/          #   GestureMachine + BoardGeometry (pure, no SwiftUI)
    Tests/WordBoardTests/       #   exhaustive gesture + viewport-math suites
  Word/                         # the app target (SwiftUI)
    Board/                      #   camera, board rendering, unified pointer surface
    Game/                       #   GameModel (App.tsx port), GameScreen, rack
  WordTests/                    # app-layer tests (board render perf gate)
```
