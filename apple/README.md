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

There is deliberately no Xcode project yet — this container has no Xcode, and checked-in
project skeletons nobody has opened are worse than none. First session on a Mac:

1. Xcode → New Project → **Multiplatform App** (iOS + macOS destinations), name `Word`,
   save into `apple/` (creates `apple/Word.xcodeproj`).
2. Add the local package: File → Add Package Dependencies → Add Local → select
   `apple/Packages/WordCore`. Link the `WordCore` library to the app target.
3. Add `public/dictionary.txt` to the app target as a bundled resource (the validation
   dictionary is app-provided by design — the core's `parseDictionary` equivalent is a
   `Set<String>` init; the package bundles only the generation pool).
4. Sanity check in a SwiftUI preview: `try! generatePuzzle(wordPool: commonWords,
   tileCount: 20, rng: seededRng("hello"))` and render the letters.

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
