# WordCore porting conventions

How `src/game/*.ts` becomes `apple/Packages/WordCore` (plan: `docs/apple-port-plan.md` §4–§5).
Every module port follows these rules so independently written files compose and the
battle determinism contract survives.

## Ground rules

1. **Port the source, not the idea.** Keep control flow, constants, caps, and even
   rejection paths structurally identical to the TS file. The seeded RNG's draw count
   per iteration is part of the contract.
2. **JS semantics table** — use these translations everywhere:
   | JS | Swift |
   |---|---|
   | `Math.imul(a, b)` | `a &* b` on `UInt32` |
   | `x | 0` add / wrapping add | `&+` on `UInt32` |
   | `>>>` | `>>` on `UInt32` (logical) |
   | `Math.floor(rng() * n)` | `Int((rng() * Double(n)).rounded(.down))` |
   | `Math.round(x)` (half-up) | `Int((x + 0.5).rounded(.down))` |
   | `str.charCodeAt(i)` / `str.length` in hashes | UTF-16 code units (`str.utf16`) |
   | `Object.keys/values/entries` order | `TileMap.keys/values/entries` (insertion-ordered) |
   | `Array.prototype.sort` (stable) | `sorted(by:)` — documented stable in Swift; keep comparators identical |
   | `x % n` on possibly-negative x | port the TS expression literally (e.g. `((from % t) + t) % t`) |
3. **`TileMap` is the only board type.** Never use `[String: String]` for a board —
   `TileMap` (Sources/WordCore/TileMap.swift) preserves JS object insertion order,
   which the generator's RNG indexes into.
4. **Linux-compatible**: the package builds with `swift test` on Linux (CI + this
   container). Foundation basics only (`JSONDecoder`, `Bundle.module`); no
   CoreFoundation-only or Darwin-only API. No new package dependencies.
5. Language mode is Swift 5 (set in Package.swift) — don't fight concurrency warnings.
6. **Tests**: Swift Testing (`import Testing`, `@Test`, `#expect`). Mirror the vitest
   suite structure and test names. Load fixtures with the helper in
   `Tests/WordCoreTests/TestSupport.swift`.
7. Doc comments: keep the TS file's explanatory comments (they're good); cite the
   source file once at the top (`/// Ported from src/game/foo.ts`).
8. Storage-backed modules (`stats`, `setups`, `onboarding`, sound pref) take an
   injectable `KeyValueStore` protocol (get/set/remove by string key) instead of
   touching UserDefaults directly; mirror the TS behavior that failed reads mean
   defaults and writes never throw.

## Public API contract (agents: match these signatures exactly)

Already ported (do not re-create): `Types.swift` (`CellKey`, `Direction`, `Cell`,
`Bounds` incl. `Bounds(size:)` + `contains`, `keyOf`, `parseKey`), `TileMap.swift`,
`Rng.swift` (`seededRng(_:) -> () -> Double`, `randomSeed()`), `Board.swift`,
`Levels.swift`, `Generator.swift`, `Battle.swift` — see those files for the shapes
they export.

Modules to port and their required public surface:

### Modes.swift (from modes.ts)
```swift
public enum GameMode: String { case endless, battle, tutorial }
public enum SoloPace: String, CaseIterable { case regular, fast }
public struct ModeInfo { public let name, tagline: String; public let details: [String] }
// SOLO_INFO, BATTLE_ROYALE_INFO, TUTORIAL_INFO, PACE_NAMES ([SoloPace: String]),
// PACE_OPTIONS, DOOR_INFO — port as `public let` / static tables.
// All numeric constants keep their TS names as `public let` (ENDLESS_START_TILES…).
public func endlessInitialSeconds(_ pace: SoloPace) -> Int
public func endlessDripSeconds(_ intervalsElapsed: Int, _ pace: SoloPace) -> Int
public func endlessDripTiles(_ intervalsElapsed: Int, _ pace: SoloPace) -> Int
public func battleDripTiles(round: Int) -> Int
public func battleAttackMultiplier(round: Int) -> Double
public func battleRoundAt(seconds: Double) -> Int
public func battleDripTilesAt(dripIndex: Int) -> Int
public func battleAttackTiles(wordLength: Int, round: Int, grewFrom: [Int] = []) -> Int
public func splitAttackTiles(count: Double, targets: Int, from: Int = 0) -> [Int]
public func formatSeconds(_ totalSeconds: Double) -> String
```
`splitAttackTiles` keeps the TS guards: non-finite count or `targets <= 0` → `[]`;
negative count → all-zero shares. Fixture test: `Fixtures/modes.json`.

### Placement.swift (from placement.ts)
```swift
public let GAP = -1
public struct Pick: Equatable { public var letter: String?; public var rackIndex: Int }
public struct PlacementStep: Equatable { public var key: CellKey; public var letter: String; public var rackIndex: Int }
public struct PlacementPlan { public var steps: [PlacementStep]; public var unfilledGaps: [CellKey]; public var complete: Bool }
public func planPlacement(board: TileMap, bounds: Bounds, anchor: Cell, dir: Direction, picks: [Pick]) -> PlacementPlan
public func anchorForGapTarget(board: TileMap, bounds: Bounds, target: Cell, dir: Direction, picks: [Pick]) -> Cell?
public func planWordCells(board: TileMap, bounds: Bounds, length: Int, own: [CellKey], dir: Direction, start: Cell) -> [CellKey]?
public func startableDirections(board: TileMap, bounds: Bounds, cell: Cell) -> [Direction]
public func impliedDirections(board: TileMap, cell: Cell) -> [Direction]
public func cursorCell(board: TileMap, bounds: Bounds, anchor: Cell, dir: Direction, picks: [Pick]) -> Cell?
public func findAvailable(rack: [String], letter: String, taken: Set<Int>) -> Int
```
(TS `size: number | Bounds` params become `Bounds`; callers use `Bounds(size:)`.)

### Tutorial.swift (from tutorial.ts)
```swift
public struct TutorialStep { public let tiles: [String]; public let word: String; public let needsGap: Bool; public let done: String }
public let TUTORIAL_STEPS: Int
public let tutorialScript: [TutorialStep]   // TS `TUTORIAL_SCRIPT` / steps array — keep content identical
public struct ScriptedPlacement { public var anchor: Cell; public var dir: Direction; public var picks: [Pick] }
public func scriptedPlacement(board: TileMap, bounds: Bounds, step: TutorialStep, rack: [String]) -> ScriptedPlacement?
```
Match the TS file's actual export names/shapes if they differ — the file is the truth.

### SoundSpec.swift (from sounds.ts — DATA ONLY, no audio playback)
```swift
public enum Waveform: String { case sine, square, sawtooth, triangle }
public struct Blip { public let freq: Double; public let to: Double?; public let at: Double; public let dur: Double; public let gain: Double; public let type: Waveform }
public enum GameSound: String, CaseIterable { case tick, deal, attack, commit, overflow, lose, win }
public let soundVoices: [GameSound: [Blip]]   // exact values from sounds.ts:54-93
// Envelope constants the player will need: attack 0.008s linear, decay to 0.0001,
// schedule offset 0.01s, stop at dur + 0.02s — export as named constants.
```

### Persistence.swift (from stats.ts + setups.ts + onboarding.ts + the sound pref)
```swift
public protocol KeyValueStore { func get(_ key: String) -> String?; func set(_ key: String, _ value: String); func remove(_ key: String) }
public struct GameRecord: Codable, Equatable { public var score: Int; public var words: Int; public var at: Double }
public struct Stats: Equatable { public var gamesPlayed: Int; public var recent: [GameRecord] }
public let RECENT_LIMIT: Int
public func loadStats(from store: KeyValueStore) -> Stats
public func recordGame(_ record: GameRecord, in store: KeyValueStore) -> Stats
public struct SoloSetup: Equatable { public var pace: SoloPace }
public func loadSoloSetup(from store: KeyValueStore) -> SoloSetup
public func saveSoloSetup(_ setup: SoloSetup, to store: KeyValueStore)
// onboarding: hasSeenTutorial/markTutorialSeen, hasSeenDoor/markDoorSeen(GameDoor)
// sound: isSoundEnabled/setSoundEnabled — pref semantics: anything but "off" is on.
```
Keep the exact storage keys (`nana.stats.v1`, `nana.setup.solo.v1`, `nana.tutorial.v1`,
`nana.doors.v1`, `nana.sound.v1`) and the exact JSON shapes so a future migration can
read web exports. Mirror the defensive parsing (garbage → defaults).

## Verifying

```bash
cd apple/Packages/WordCore && swift test          # all suites + parity fixtures
npm run gen:fixtures                              # regenerate from TS (must be a no-op diff)
swift apple/tools/make-icon.swift apple           # regenerate the app icon
./apple/tools/release.sh ios                      # archive + export a TestFlight build
```
