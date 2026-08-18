# Word on Apple platforms

The native iPhone/iPad/Mac port, built to [`docs/apple-port-plan.md`](../docs/apple-port-plan.md).

## State

**Phases 0–2 are complete, and phase 4's protocol half is built.** What runs today:
Solo (both paces) and the guided tutorial, playable on iPhone, iPad and Mac.

| Package / target | What it is |
|---|---|
| `Packages/WordCore` | The game core in pure Swift — **bit-exact with the web game** via golden fixtures generated from the TypeScript core (`npm run gen:fixtures`), so the same seed deals the same letters on both platforms. |
| `Packages/WordBoard` | The board's interaction brain, kept pure so it tests without a simulator (plan §11): the **gesture disambiguation state machine** (6pt slop, 350ms double-press, 300ms hold-to-drag, locked-board semantics, pointer-id filtering) and the **viewport math** (zoom clamps, pinch anchoring, shrink-only auto-fit, growth compensation). |
| `Packages/WordNet` | The **battle wire protocol** over an injectable transport — roster and seat capacity, seat grace and re-entry, attack clamping/splitting, the referee, the v6 host-election handshake, and the version gate. Tests run over an in-memory mesh, so only the GKMatch adapter will need devices (plan §7.5). |
| `Word/` (app) | SwiftUI: a custom pan/zoom board (owning its offset is what lets zoom and its scroll correction land in one frame), a Canvas cell lattice with views only for occupied cells, one gesture pipeline feeding board and rack, the editing loop with undo/redo, the paced Solo session, the tutorial, home/stats/settings screens, synthesized audio + haptics, and save/restore across process death. |

```bash
cd apple/Packages/WordCore  && swift test   # core + golden parity fixtures
cd apple/Packages/WordBoard && swift test   # gesture machine + board geometry
cd apple/Packages/WordNet   && swift test   # battle protocol over a mock mesh
xcodebuild test -project apple/Word.xcodeproj -scheme Word \
  -destination 'platform=macOS'              # app tests incl. the zoom-out perf gate
```

CI (`.github/workflows/ci.yml`) runs the web tests, all three Swift packages on Linux, a
fixture-drift check (TS core changed → fixtures must be regenerated in the same commit),
and a resource-sync check (the bundled word pool must stay byte-identical to the web's —
its file order is determinism-critical).

Conventions and the porting API contract live in [`PORTING.md`](PORTING.md).

### What's left, and what it's waiting on

- **Phase 3 (Game Center + Daily Deal)** needs an Apple Developer account, an App ID with
  the Game Center/iCloud capabilities, and test Apple IDs — its exit criteria can't be
  exercised without them. The stats funnel it hangs off already exists
  (`GameModel.onFinish`).
- **Phase 4's remaining half** is the `GKMatch` adapter behind `BattleTransport`, plus the
  lobby UI and the 8-device spike (§7.4). The protocol it speaks is done and tested.
- Known gaps to tune on-device: pinch pans about the gesture's *initial* midpoint (live
  midpoint tracking wants a `UIPinchGestureRecognizer` bridge — `PinchAnchor` already
  accepts one), Apple Pencil is classified as touch, and macOS trackpad scroll-to-pan
  needs an NSEvent bridge (phase 5 Mac polish; drag-to-pan and pinch work today).

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

Next up is phase 3 (Game Center) once the developer account is in place, or the
`GKMatch` adapter behind `WordNet`'s `BattleTransport` for phase 4. The notes in
`../docs/apple-port-notes/` remain the source of truth: `ui.md` for interaction
and `protocol.md` for the wire format, both with file:line references into the
web app.

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
  Packages/WordNet/             # battle protocol (SPM, Linux-testable, no GameKit)
    Sources/WordNet/            #   Protocol + HostSession/ClientSession + MemoryTransport
    Tests/WordNetTests/         #   protocol, roster, grace, attacks, referee, election
  Word/                         # the app target (SwiftUI)
    Board/                      #   camera, board rendering, unified pointer surface
    Game/                       #   model, Solo clock machine, screen + chrome, tutorial
    Screens/                    #   router, home, doors/cards, stats, settings
    Services/                   #   audio synthesis, storage, settings, saved games
  WordTests/                    # app-layer rendering, editing + lifecycle tests
```
