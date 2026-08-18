# Word on Apple platforms

The native iPhone/iPad/Mac port, built to [`docs/apple-port-plan.md`](../docs/apple-port-plan.md).

## State

**Phase 0 + Phase 1 and phase 2a are complete. Phase 2b is underway: its core
solo editing loop is built.**

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
feeding board and rack alike.

The first phase-2b slices complete the editing loop and Solo session lifecycle:
Mac/iPad hardware-keyboard commands, a responsive word bar, 50-deep undo/redo,
selected-word move/rotate/remove controls, both Solo pace schedules, wall-clock
countdowns that freeze behind readable overlays, the loose-tile gauge and board
alarm, board-clear refills/bonuses, opaque pause, and a final word/score summary.
The lifecycle is a deterministic state machine with focused expiry, pause and
history tests; the controls and summary also have render snapshots. Remaining
phase 2b work is process-death save/resume, tutorial and onboarding,
stats/settings/theme, audio/haptics, and the full accessibility pass.

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
Signing & Capabilities. Then Run — the game screen deals through WordCore and loads
the bundled dictionary (`public/dictionary.txt` is referenced from the web app
directly, so the platforms can't drift).

Continue phase 2b from process-death save/resume. The notes in
`../docs/apple-port-notes/ui.md` remain the interaction source of truth, with
file:line references into the web app.

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
    Game/                       #   model, Solo clock state machine, screen + chrome
  WordTests/                    # app-layer rendering, editing + lifecycle tests
```
