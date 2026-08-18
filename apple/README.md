# Word on Apple platforms

The native iPhone/iPad/Mac port, built to [`docs/apple-port-plan.md`](../docs/apple-port-plan.md).

## State

**Phase 0 + Phase 1 are complete.** `Packages/WordCore` is the full game core in pure
Swift — board rules, generator, pacing/attack tables, placement engine, battle
referee/codes/tile-stream, tutorial script, sound-cue tables, and persistence models —
**bit-exact with the web game**: golden fixtures generated from the TypeScript core
(`npm run gen:fixtures` at the repo root) replay in the Swift tests, so the same seed
deals the same letters on both platforms. 227 tests, green on Linux and macOS alike:

```bash
cd apple/Packages/WordCore && swift test
```

CI (`.github/workflows/ci.yml`) runs the web tests, the Swift tests, a fixture-drift
check (TS core changed → fixtures must be regenerated in the same commit), and a
resource-sync check (the bundled word pool must stay byte-identical to the web's —
its file order is determinism-critical).

Conventions and the porting API contract live in [`PORTING.md`](PORTING.md).

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
```
