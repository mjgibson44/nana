# Word on iPhone, iPad, and Mac — Port Plan

*A plan for turning the web game into a native Apple-platform app built on Game Center,
GameKit multiplayer, and the rest of Apple's game stack.*

*Written 2026-08-18 against the codebase as of `2b8f271`. Apple platform facts below were
verified against developer.apple.com documentation current as of this date; anything
uncertain is flagged as such.*

---

## 0. TL;DR

**Build a native SwiftUI multiplatform app (one Xcode target: iPhone, iPad, Mac) with the
game core ported to a pure Swift package, and replace the entire PeerJS/WebRTC/TURN
multiplayer stack with GameKit.** The codebase makes this unusually tractable: everything
under `src/game/` is deliberately framework-free, plain-data, and unit-tested — it ports
mechanically to Swift — and the multiplayer design (host-authoritative star, one seed per
game, tiles never on the wire) is *exactly* the architecture Apple documents for GKMatch
real-time games. Every piece of networking infrastructure in `infra/` exists only to make
browser WebRTC work and is retired outright by Game Center.

The headline wins, in order of impact:

1. **GKMatch real-time multiplayer** replaces PeerJS + broker + STUN/TURN. Matchmaking,
   invites, NAT traversal, and transport are Apple's problem; up to 16 players per match
   (the game needs 8). The 10-message JSON protocol survives nearly verbatim (plus one
   new host-announcement message, §7.2).
2. **Game Center join codes, natively**: iOS 26's `GKGameActivity` *party codes* are a
   first-class, OS-integrated version of the game's 5-letter battle codes — shareable
   through Messages and the Games app, with deep links into the lobby.
3. **A new "Daily Deal" mode almost for free**: battle's deal stream is already
   seed-driven (`createTileStream` — same seed, identical letter sequence on every
   client), so one date-derived seed gives every player on Earth the same letters each
   day — the perfect fit for a **recurring daily leaderboard** and iOS 26 **Challenges**
   (Apple's own docs use "a daily mini crossword" as the worked example).
4. **Leaderboards, achievements, and the Apple Games app** give Solo mode the persistent
   progression the web version lacks, and make the game surface well in the new
   system-wide Games hub.
5. Platform delighters that fit this specific game: hardware-keyboard play on iPad/Mac
   (typing is already a core mechanic), Core Haptics paired with the synthesized sound
   set, a daily-puzzle widget, App Intents/Shortcuts, iCloud sync of stats, and Game Mode.

**Recommended v1 scope cut**: no web↔native cross-play (rationale in §10 — every
credible precedent routes cross-play through a server, not P2P). The web version stays
up; golden parity tests keep the deterministic core bit-identical between TypeScript and
Swift so cross-play (or a shared web/native Daily Deal) stays a live option.

Realistic effort: **~3–4 months of focused work** to a shippable App Store v1
(phases and estimates in §14).

---

## 1. Where we're starting from

What matters about the current codebase for a port:

- **The game core is already a portable library.** The rules engine, generator, pacing
  tables, attack math, referee, placement engine, and tutorial script under `src/game/`
  are pure TypeScript over plain serializable data — no DOM, no React (`types.ts`
  documents serializability as a design goal). Board = sparse
  `Record<"row,col", letter>`; eight vitest suites pin the behavior. A few files in the
  directory carry small browser fringes the port peels off (§4 handles each):
  `localStorage` in stats/setups/onboarding/sounds, `window.location` in `battleLink`,
  and `sounds.ts` is half data table, half Web Audio playback engine.
- **Multiplayer is transport-agnostic except for one file.** `src/net/battleSession.ts`
  is the only transport-aware code; `App.tsx` talks to it through the small
  `BattleHandle`/`BattleEvents` interfaces. The wire protocol is 10 JSON message types,
  `attack` flowing in both directions (client→host: `hello`, `progress`, `attack`,
  `pong`, `leave`; host→client: `state`, `start`, `stop`, `reject`, `attack`, `ping`),
  protocol version 5, all assuming reliable ordered delivery. The host decides roster,
  start/stop, attack splitting, elimination order, and game over; clients own their
  boards entirely.
- **Determinism does the heavy lifting.** One 12-char seed per game; every client grows
  the identical deal via `xmur3` + `mulberry32` feeding the crossword generator
  (`createTileStream`). The opening batch is sized by the first request — identical
  because every client asks for the same `BATTLE_START_TILES = 15` — and all growth
  after it is in fixed 5-tile chunks, independent of how later requests are sized.
  Attacks travel as counts; receivers draw letters from a private stream seeded
  `"<seed>/attacks/<selfId>"`. Tiles never cross the wire. This carries over to GameKit
  unchanged — and the same stream is what makes the Daily Deal mode (§8.2) nearly free.
- **The infra directory is pure WebRTC tax.** PeerJS broker, Caddy TLS, coturn TURN,
  and the Metered free-tier relay credentials in `.env.production` exist solely for
  browser-to-browser introductions and NAT traversal. GameKit needs none of it.
- **The UI is the real porting work.** The pointer pipeline in `App.tsx` (unified
  tap/drag disambiguation by 6px slop, `elementFromPoint` drop hit-testing,
  hold-to-drag preview, hand-rolled anchored pinch zoom, global-keydown typing) is
  sophisticated and must be *redesigned* for SwiftUI, not transliterated. §6 itemizes
  the traps.
- **Sounds are a data table.** All seven cues are synthesized oscillator "blips"
  (waveform, frequency/glide, envelope) — they port to AVAudioEngine as data, no assets.

---

## 2. The strategic choice: native SwiftUI, core ported to Swift

Three ways to get on the App Store, and why we take the third:

| Option | What it is | Verdict |
|---|---|---|
| **Wrap the web app** (WKWebView/Capacitor) | Ship the existing React app in a shell | Fastest, but it can't be the goal: Game Center, GKMatch, haptics, widgets, App Intents, and Games-app presence all live behind native APIs; a bare wrapper also risks App Review guideline 4.2 (minimum functionality). Useful only as a stopgap, and it would keep the TURN/broker infra alive forever. |
| **Mac Catalyst / "Designed for iPad" on Mac** | iPad build re-hosted on macOS | Catalyst is maintained but positioned by Apple for *existing* UIKit iPad apps; a new app gets no benefit. "Designed for iPad" is worth enabling as a free extra (it includes Game Center), but it isn't the Mac product — single-pointer emulation, no real Mac windowing/menus. |
| **Native SwiftUI multiplatform** ✅ | One Xcode app target with iOS/iPadOS/macOS destinations (native macOS SDK — Xcode's default for new multiplatform apps), game core in a Swift package | The only option that actually leverages what this plan is for. The pure game core makes the usual "rewrite risk" small: the hard 20% (rules, generator, referee) is already isolated and tested, and the UI was getting rebuilt for touch-vs-pointer-vs-keyboard parity anyway. |

Supporting facts (verified): single-target multiplatform with per-platform destinations
has been Xcode's default since Xcode 14 and remains so in Xcode 26; Apple's guidance is
native macOS destination for SwiftUI apps, Catalyst only "if you're bringing an existing
iPad app to Mac." SwiftUI should handle the board — note the real size: at max zoom-out
the full lattice is **1,100+ visible cells** (33×33 plus growth; the web stylesheet
itself remarks "over a thousand cells"), which makes §11's zoom-out render benchmark a
load-bearing gate, not optional polish. SpriteKit stays the escape hatch for the board
layer only if profiling fails that gate (physics/particles/large animated node counts —
the usual SpriteKit triggers — don't otherwise apply).

**Language/tooling baseline**: Swift 6 (strict concurrency), SwiftUI app lifecycle
(also future-proof against TN3187's UIScene requirement), Swift Testing for tests,
SPM local packages for everything non-UI.

---

## 3. Targets and minimum OS

| Platform | Ship in v1 | Minimum OS | Notes |
|---|---|---|---|
| iPhone | ✅ | iOS 18 | Primary target. Honest rationale: 18 is a developer-convenience floor (fewer availability checks, modern SwiftUI), not a hard requirement — nothing in v1 needs more than 17. For a friends-and-family audience the cost is near zero, and dropping to 17 stays feasible if a key tester's device demands it. |
| iPad | ✅ | iPadOS 18 | Hardware keyboard + pointer are first-class here. |
| Mac | ✅ | macOS 15 | Native destination; menu bar, resizable window, full keyboard play. |
| visionOS | ⏳ later | — | Near-free compatibility mode immediately; native destination is a small follow-up (§9.6). |
| watchOS / tvOS | ❌ | — | No sensible fit for a typing/tile game. |

**iOS 26 features are gated, not required**: party codes (`GKGameActivity`), Challenges
(`GKChallengeDefinition`), and the GameSave framework are all 26-only. The app runs fully
on 18/15 with invite-based multiplayer and classic+recurring leaderboards; on 26+ it
lights up party codes and challenges via `if #available`. Revisit the floor at launch
time — if the actual audience (friends & family) is all on 26-class devices by then,
raising the floor to iOS 26/macOS 26 deletes the fallback code paths (decision point,
§16).

---

## 4. Architecture: packages and module map

Proposed repo layout — the web app stays untouched at the root; everything Apple lives
under `apple/`:

```
apple/
  Word.xcodeproj                 # one app target, destinations: iPhone/iPad/Mac
  Word/                          # app layer (SwiftUI)
    WordApp.swift                #   @main, scenes, theme plumbing
    Screens/                     #   Home, Setup, Game, Battle lobby, Stats, Settings…
    Board/                       #   grid rendering + the unified gesture layer (§6)
    Services/                    #   GameCenterService, AudioEngine, Haptics, Persistence
  Packages/
    WordCore/                    # pure Swift port of src/game/ — no UI imports
      Sources/WordCore/          #   Board, Generator, Modes, Battle, Rng, Placement,
                                 #   Tutorial, Scoring, Stats, SoundSpec (blip tables)
      Tests/WordCoreTests/       #   ported vitest suites + golden parity fixtures
    WordNet/                     # battle session over GameKit (HostSession/ClientSession)
      Sources/WordNet/
      Tests/WordNetTests/        #   protocol tests over an in-memory mock transport
  Fixtures/                      # JSON golden vectors generated from the TS core
tools/
  gen-fixtures.mjs               # Node script: runs the TS core, emits Fixtures/*.json
```

Module mapping, TypeScript → Swift:

| TS module | Swift home | Porting notes |
|---|---|---|
| `game/types.ts` | `WordCore/Board.swift` | `Cell` becomes a `Hashable` struct; keep a `"row,col"` string codec for save/fixture compatibility. **Board must preserve insertion order** (§5). |
| `game/board.ts` | `WordCore/Validation.swift` | Run extraction, components, `validateBoard`. JS relies on stable sort order for component ties; Swift's `sort()` is documented guaranteed stable too, so order matches — pin it with parity tests. |
| `game/generator.ts` | `WordCore/Generator.swift` | The determinism-critical file. Keep `rng` injectable; replicate attempt/failure caps (100/400, 500, 200, 800, 200) and exact RNG draw counts per rejection path. |
| `game/rng.ts` | `WordCore/Rng.swift` | xmur3 + mulberry32 on `UInt32` with `&*`/`&+`; hash **UTF-16 code units**; final `Double(u) * 0x1p-32`. |
| `game/modes.ts` | `WordCore/Modes.swift` | Pacing tables, `battleAttackTiles` (JS `Math.round` is half-up — Swift `.rounded()` matches for the non-negative values that occur; pin with tests), `splitAttackTiles` (port the double-mod negative-`from` normalization literally). |
| `game/battle.ts` | `WordCore/Battle.swift` | Tile stream, referee, rankings. Join-code helpers survive (§7.3 keeps 5-letter codes as the UX). Drop the `window.location` bits for a deep-link equivalent. |
| `game/levels.ts`, `placement.ts`, `tutorial.ts` | `WordCore/…` | Mechanical ports; the gap-tile contract in `placement.ts` has the densest test coverage — port tests first. |
| `game/setups.ts`, `stats.ts`, `onboarding.ts` | `WordCore/Persistence.swift` + app `Services/` | `localStorage` keys → `UserDefaults` keys (same names); mirror the "garbage falls back to defaults, writes never throw" semantics. iCloud sync in §9.1. |
| `game/sounds.ts` | `WordCore/SoundSpec.swift` + app `Services/AudioEngine.swift` | The Blip table is pure data → port verbatim; playback in §6.5. |
| `game/dictionary.ts`, `commonWords.ts` | `WordCore` bundled resources | Ship `dictionary.txt` (1.74 MB, 172,823 words) and `common-words.txt` (5,000 words) as package resources. **Preserve `common-words.txt` line order exactly** — bucket order is determinism-critical. |
| `net/battleSession.ts` | `WordNet/` | Re-implemented over GKMatch (§7). The message enums, host-authority logic, and seat/grace design port; the dial/broker/ICE machinery is deleted. |
| `theme.ts` | app layer | `@AppStorage` + `preferredColorScheme` (`system` = nil). |
| React components | app `Screens/` + `Board/` | Rebuilt, using §6 as the spec. |

`WordCore` has zero dependencies and compiles on all platforms including visionOS —
which is what keeps later targets cheap.

---

## 5. Porting the game core: the determinism contract

For two battle clients to grow identical deals from one seed, the Swift port must be
**bit-exact** with the TS implementation in seven specific ways (all verified against
the source):

1. **RNG arithmetic.** `Math.imul` = low-32 truncating multiply → `UInt32 &*`;
   `| 0` wrap → `&+` on `UInt32`; `>>>` → logical shift (native on `UInt32`);
   `(h << 13) | (h >>> 19)` is a rotl13 — parenthesize everything (Swift precedence
   differs from JS). Final value: `Double(u) * 0x1p-32` is exactly JS's
   `(x >>> 0) / 4294967296`.
2. **Seed hashing over UTF-16 code units.** JS `charCodeAt`/`length` count UTF-16 code
   units. Current seeds are ASCII (`[0-9a-z]{12}`, plus `"<seed>/attacks/<selfId>"`),
   but hash `String.utf16` anyway — and if a hashed string ever includes user text,
   NFC-normalize on both platforms first (macOS text input can produce decomposed
   forms the web never sees).
3. **Insertion order is load-bearing.** The generator indexes the RNG into
   `Object.keys(grid)` (anchor selection), `Object.values(solution)` (the letter
   shuffle), and filtered key lists (extend letters) — JS gives insertion order for
   these string keys. Swift `Dictionary` order is unspecified **per process**. The port
   needs an order-preserving board structure for generation (dictionary + appended key
   array, or an `OrderedDictionary`).
4. **Exact RNG draw counts on failure paths.** A missing-candidates rejection consumes
   1 draw, wrong-length 2, `canPlace`/span failure 4. Refactoring the loop shape
   desynchronizes clients even with a perfect RNG.
5. **Word pool order.** `byLetter`/`byLength` bucket order = `common-words.txt` line
   order; per-word letter order = first-occurrence order (`new Set(word)`), which a
   Swift `Set<Character>` will destroy — dedupe with an order-preserving pass.
6. **Sort-order ties.** `components()` largest-first tie order and `rankByElimination`
   equal-`outOrder` order both lean on stable sorting. JS `Array.prototype.sort` is
   stable (ES2019) and Swift's `sort()` is *also* documented guaranteed stable, so a
   direct port matches — but the reliance is invisible in the code, so pin it with
   parity fixtures (and index tiebreakers cost nothing if you want belt-and-braces).
7. **Rounding and edge cases.** `Math.round` half-up in attack math; `splitAttackTiles`'
   NaN/negative handling; keep the caps and clamps (attack clamp 50, pile limits) in
   one place.

**Why bother with bit-parity when v1 has no cross-play?** Three reasons: (a) golden
fixtures generated from the TS core are the cheapest possible proof that the port is
*faithful* — hundreds of behaviors validated in one test; (b) it keeps web↔native
cross-play and a **shared web/native Daily Deal** (same date → same letters on both
platforms) on the table; (c) it costs almost nothing if done from the start and is
miserable to retrofit.

**Golden fixture harness** (build this before porting the generator):
`tools/gen-fixtures.mjs` runs the existing TS core in Node and emits JSON vectors into
`apple/Fixtures/`:

- xmur3 hashes + first 10k mulberry32 outputs (as raw `UInt32`, not floats) for a seed
  corpus (empty, ASCII, both `é` normalizations, emoji, long strings);
- full `createTileStream(seed).next(...)` letter sequences for ~20 seeds under varied
  request interleavings (the existing `battle.test.ts` patterns) — **including varied
  first-request sizes**, since the opening batch is sized by the first call and a port
  that misses that desyncs silently;
- complete `generatePuzzle`/`extendPuzzle` outputs (letters + solution boards) for
  seeded runs;
- `battleAttackTiles`/`splitAttackTiles` exhaustive tables.

Swift Testing consumes the fixtures; CI regenerates them from TS and fails on drift.
Then port the eight vitest suites themselves (board, generator, modes, battle, levels,
placement, setups, tutorial) — they're the behavioral spec.

---

## 6. Rebuilding the UI in SwiftUI

### 6.1 Screen map

The web app is one router state (`home | battle | game`) plus ~15 z-ordered overlays.
SwiftUI equivalents are mostly direct: enum-switched root, sheets for
setup/explainers/confirms, timed overlays for toasts and splash cards, an anchored
popover for word controls. One platform trap: `fullScreenCover` **does not exist on
native macOS** — build the full-screen pages (summary/stats/settings/pause) as one
custom opaque cover component in a window-filling `ZStack` and use it on all three
platforms rather than forking per-OS presentation. Behaviors to keep on purpose:

- **Pause stays opaque** — the board must not be readable while clocks are stopped.
- **Clock model ports as-is**: wall-clock `endsAt` vs frozen `remainingMs` is exactly
  right for app backgrounding; solo clocks pause under readable overlays, battle clocks
  never pause except during your own reconnection.
- **New on iOS, not in the web version: solo games must survive process death.** The OS
  routinely kills backgrounded apps, and a 30-minute endless run dying to a phone call
  is a regression web users never hit. The board is plain serializable data, so this is
  cheap: on `scenePhase → background`, serialize the in-progress solo game (board, pile,
  staged state, score, clock model) and offer resume on next launch. Phase-2 work.
- **Signed-out state is a real screen, not an error** — see §7.1.

### 6.2 The board

Render only the active bounds of the virtual 33×33 grid (grown with the 8-cell margin),
inside a two-axis scroll view; cell size = base (44pt regular / 38pt compact) × zoom
(clamped 0.55–1.6). Tiles as SwiftUI views are fine at this scale; drop to `Canvas` for
the cell lattice only if profiling says so.

The web version solved four hard problems that must be solved again, not copied.
(The companion notes in [`docs/apple-port-notes/`](apple-port-notes/) carry the full
file:line inventory; originals: unified pointer pipeline `App.tsx:2418–2533`, drop
hit-testing `App.tsx:2471–2504`, hold-to-drag preview `App.tsx:2607–2711`, pinch
anchoring `App.tsx:2741–2895`, auto-fit `App.tsx:1089–1133`, growth compensation
`App.tsx:1035–1046`.)

1. **One unified gesture layer, not per-cell gestures.** The web decides tap-vs-drag
   after the fact (6px slop) and hit-tests drops via `elementFromPoint` at any
   zoom/scroll. SwiftUI translation: a single high-priority gesture attached to the
   board layer, row/col from coordinate math in a named coordinate space, and one
   overlay layer that renders drag ghosts above everything. Per-tile `.onDrag` or
   scattered `.gesture`s will fight the ScrollView and break at non-default zoom.
2. **Tiles don't pan, empty cells do.** Dragging a tile must never scroll the board;
   dragging empty board must. This falls out of the unified layer (hit-test decides),
   not out of gesture priorities.
3. **Hold-to-drag preview (touch and Apple Pencil — the web excludes only mouse)**:
   300ms hold on empty board with letters staged picks the preview up; movement >6px
   before the timer cancels into a pan; release anchors without committing.
   `LongPressGesture.sequenced(before: DragGesture())` + `.scrollDisabled(while
   active)`. Mouse/trackpad instead aims by hover (`.onContinuousHover`, gated to
   letters-staged only). Include Pencil in the phase-2 gesture test matrix.
4. **Anchored pinch zoom + auto-fit.** Keep zoom as a cell-size multiplier; capture the
   pinch anchor once as a fraction of the board and re-aim it every frame with scroll
   correction in the same layout pass. Auto-fit only ever *shrinks* (cap 1.0, epsilon
   0.03) and restores the viewport center — it never scrolls toward the tiles. Board
   growth (prepended rows/cols) needs same-pass scroll compensation or the crossword
   visibly jumps.

Smaller ports called out in the research that a naive rebuild gets wrong: double-press
detection must not add latency to single-press drags (check a timestamp inside the
unified pointer-down, don't use `TapGesture(count: 2).exclusively(before:)`); a completed
drag must not also register as a tap (port the *intent* of `swallowNextClick`, not the
mechanism); battle's locked board flips gesture semantics wholesale (no drag-off, no
delete-select, no double-tap return, no undo — but tap-to-aim gaps stays); score pops
derive from watching the score value, not from actions.

### 6.3 Typing

There is no text field in the web game — typing is a global key listener. Map:

- **Mac / iPad hardware keyboard**: `.onKeyPress` on the focused game container —
  a–z claims matching pile tiles only (`findAvailable` rules), Space stages a gap,
  Enter commits, Escape clears, Backspace/Delete eat words backward/forward,
  ArrowRight/Down aim direction. Menu-bar equivalents on Mac get `.keyboardShortcut`.
- **iPhone**: keep the web's answer — tap pile tiles to stage letters; no virtual
  keyboard by default. (An optional keyboard toggle can come later; it's a design
  addition, not a port.)

### 6.4 Theme and visual language

Monochrome ink design with functional color only (green/red/orange/yellow tile states)
translates cleanly to SwiftUI with a small token set; light/dark/system =
`preferredColorScheme` driven by `@AppStorage("nana.theme.v1")` (nil = system). Keep
the worst-problem-wins cell status priority and the escalating gauge → board-alarm
pairing (same color, same cadence). The animation inventory (score bump, pops, toasts,
rack drop-in stagger with overshoot, pulse cadences 1.1s/0.55s) is all standard SwiftUI.

### 6.5 Sound and haptics

The seven cues are a data table (waveform, freq/glide, 8ms linear attack, exponential
decay). Port the table into `WordCore/SoundSpec.swift` and **pre-render each cue into an
`AVAudioPCMBuffer` at launch** (they're fixed — sample-exact synthesis in ~a page of
code), played through `AVAudioPlayerNode`s on a shared `AVAudioEngine`. This keeps the
"zero audio assets" property, avoids real-time-thread constraints of `AVAudioSourceNode`,
and gives lower latency than the web ever had. Configure the audio session as ambient
(mix with the player's music; a word game should never duck podcasts).

New on Apple platforms — pair cues with haptics (iPhone): `.sensoryFeedback` for
commit/deal ticks, Core Haptics patterns for the attack growl and the overflow alarm
(sync by starting the haptic pattern and audio buffer at the same time; iPad/Mac get
sound only). Respect the existing single "Game sound" switch and add a separate haptics
toggle.

### 6.6 Accessibility (do better than the web)

The web version labels its buttons and dialogs well but the board itself is bare divs —
no roles, no labels, no non-color status. The rebuild should close this rather than
mirror it: accessibility elements per tile ("R, row 4 column 7, part of ORBIT, valid"),
rotor/custom actions for place/return/rotate, coarse `aria-live`-equivalent
announcements (`AccessibilityNotification`) for deals/attacks/eliminations, Dynamic Type
in chrome (cells scale via zoom), Reduce Motion honored for pulses/pops, and
color-plus-shape status (e.g. a subtle underline/badge on invalid tiles) so validation
isn't color-only. Then declare it honestly in App Store Connect's **Accessibility
Nutrition Labels** (live now, still voluntary as of Aug 2026 — expected to become
required eventually).

---

## 7. Multiplayer on Game Center

### 7.1 What GameKit gives us (verified)

- **GKMatch** real-time matches for **up to 16 players** (peer-to-peer, hosted, and
  turn-based alike — the historical 4-player P2P cap is gone from current docs; the
  game needs 8). Apple handles matchmaking, invites, NAT traversal, and connection
  management; there is no STUN/TURN/broker to run. Traffic relays through Apple's
  service when direct P2P fails (widely reported behavior; not explicitly documented —
  budget ~200–300ms worst-case RTT, irrelevant for this latency-tolerant game).
- **`GKMatch.SendDataMode.reliable`** guarantees delivery *and* per-sender ordering —
  the exact assumption the existing protocol makes (`reliable: true` data channels).
  Keep every message reliable; the volume is tiny (the largest message is a
  full-state snapshot of ≤8 small player records).
- **Host tooling**: `chooseBestHostingPlayer(completionHandler:)` for electing a
  client-server topology host; `match(_:player:didChange:)` for connect/disconnect
  events; `GKMatchmaker.addPlayers(to:matchRequest:)` for backfilling a live match
  (host-invoked); `rematch()` for play-again.
- **Identity**: `GKLocalPlayer` authentication at launch (the handler can fire multiple
  times; present its view controller when given one); `gamePlayerID` is the stable
  per-game player identity — it replaces the sessionStorage `playerKey`. Name entry is
  delegated to Game Center's one-time profile setup rather than deleted: friends see
  each other's real names/photos, everyone else sees nicknames and often the default
  monogram avatar. Fine for this audience, but test the never-used-Game-Center
  first-auth flow explicitly (phase 3).

**Signed-out mode is a designed state, not an error.** The web game needs no account;
the port must not regress that when auth fails, is declined, or is restricted
(`isMultiplayerGamingRestricted`). Spec: Solo, the tutorial, and the Daily Deal always
play signed-out — scores are held locally and submitted when auth later succeeds; the
Battle door and the Standings row explain the requirement and re-trigger auth. This
state gets a row in the screen map, a phase-3 exit criterion, and App Review will
exercise it.
- **Private matches**: `GKMatchmakerViewController` with `.inviteOnly` (friends,
  contacts, Messages groups, phone/email invites), `.nearbyOnly` (local Wi-Fi/Bluetooth
  — a genuinely new capability vs the web: same-room battles with no internet path
  between routers), and rules-free automatch with `playerGroup` filtering.
- **iOS 26 party codes**: `GKGameActivity` with a party-code-enabled activity
  definition — the system generates/accepts short codes and URLs shareable OS-wide;
  `findMatch(completionHandler:)` turns the party into a GKMatch. This *is* the game's
  5-letter-code UX, now OS-blessed.

### 7.2 Protocol mapping — what changes, what doesn't

The message set survives; the transport plumbing is replaced:

| Today (PeerJS) | On GameKit |
|---|---|
| `hello {name, key, proto}` | `hello {proto}` — name from `GKPlayer.displayName`, key from `gamePlayerID`. **Keep the `proto` field** (bump to v6 with the new message below): TN2417 says prerelease builds connect to released ones (no sandbox partition), so the app must version-gate itself. |
| `state` full snapshot, `start {seed}`, `stop`, `reject`, `attack {count}` | Identical `Codable` structs over `send(_:to:dataMode:.reliable)`. `start` before `state` relies on per-sender ordering — guaranteed by `.reliable`; add the `game` counter check anyway (cheap belt-and-braces). The snapshot holds the roster: 8 seats plus any departed players still holding a standings entry — still well under a KB. |
| `ping`/`pong` every 10s, 25s staleness | Mostly replaced by `match(_:player:didChange:)`. Keep a slow app-level heartbeat (~15s) anyway — the delegate's timeliness for half-dead links isn't documented, and the heartbeat is 10 lines. |
| Host = code owner (peer id = code) | **New message: `host {proto}`** — on the web the code *is* the host's address, but a GKMatch formed from a party code is a mesh with no marked owner, and clients can't `hello` a host they can't identify. So: the party/lobby creator broadcasts `host` on match formation and re-broadcasts it to every later-connecting player; clients that see no announcement within a short timeout fall back to lowest `gamePlayerID`; pre-26 invite flows already know the host — it's the `GKInvite` sender. This is the one genuinely new protocol element (hence v6). `chooseBestHostingPlayer` is optional polish, not correctness — the host role here is referee, not relay. |
| Star topology enforced by dialing | GKMatch is a full mesh, so enforce the star by *convention*: clients send only to the host player; host sends `state` to all and attack shares point-to-point. (Mesh delivery being available changes nothing about authority.) |
| Broker/ICE/TURN machinery, dial budgets, `unavailable-id` retries | Deleted. |

Host-authority logic (roster, seat grace, attack splitting via `splitAttackTiles` with
the rotating remainder, write-once `outOrder`, `checkOver`) ports from
`battleSession.ts` into `WordNet.HostSession` essentially line-for-line — it's already
transport-independent. Same trust model as today (clients self-report boards/burials;
host clamps attacks) — fine for friends-and-family scale; note the anti-cheat posture
in §8.4 for public leaderboards.

### 7.3 Join flows

Ranked UX per OS generation:

1. **iOS 26+ — party codes.** "Host Battle" starts a `GKGameActivity` for the battle
   activity definition; the system provides the shareable code + URL (Messages, Games
   app); joiners enter the code or tap the link; `findMatch()` yields the GKMatch.
   Deep links arrive via `GKGameActivityListener.player(_:wantsToPlay:)`.
2. **Pre-26 fallback — invites.** `GKMatchmakerViewController(.inviteOnly)`; invitees
   accept via Game Center notification. Nearby mode for same-room play on any
   supported OS.
3. **Optional pre-26 code entry** — hash a typed 5-letter code into
   `GKMatchRequest.playerGroup` and automatch (documented semantics: only same-value
   requests match; the room-code use is a community pattern, not Apple-documented, and
   requires both players searching concurrently). Ship only if pre-26 code-typing
   matters in practice; invites likely cover it.

Universal Links replace the `#battle=CODE` hash links (§9.4), and the web lobby can
advertise the app to iOS visitors (§10).

### 7.4 Disconnects, backgrounding, and rejoin — the honest part

This is the one area where the web version is *ahead* of what GameKit gives us, and the
design must adapt rather than port:

- **What the web does**: 30s host-side seat grace, 115s client redial budget with
  backoff, heartbeat staleness, rejoin-as-spectator after grace, battle never pauses.
- **What changes on iOS**: backgrounding the app suspends the process and GameKit
  reports the player disconnected; there is **no documented API to rejoin an existing
  >2-player GKMatch by ID** (the 2-player `shouldReinviteDisconnectedPlayer` doesn't
  extend to 8). A quick app-switch may survive on the transport's own tolerance, but a
  real drop means re-entering through matchmaking.
- **The design**: keep the seat-grace model host-side unchanged (grace expiry stamps
  `outOrder`, game plays on — all pure logic). For re-entry, the **documented** path is
  primary: the host's session auto-invokes `addPlayers(to:)` targeted at a graced
  seat's `gamePlayerID` (with a visible one-tap "let them back in" affordance in the
  host's lobby/spectator UI as backup — design this in phase 4). Whether re-entering
  the same party code lands a player back in the *same in-progress* GKMatch is
  undocumented — treat it as a spike question, not a mechanism. Either way, the
  returner's `hello` with the same `gamePlayerID` re-attaches the seat exactly as
  today. Board state: if the process lived, the board is still in memory (same as a
  web tab); if it died, they re-enter as a waiting spectator for the next game (the
  web has the same property — a reloaded tab loses its board). Deterministic streams
  make everything else resyncable from the `state` snapshot + seed.
- **Host death still ends the lobby** (the web makes the same call — "hosts take the
  whole lobby down with them"). GameKit's player-state callbacks let clients detect it
  in seconds instead of burning a 115s redial budget. Host migration remains future
  work in both codebases; the protocol has no support for it today.
- **Spike this first** (§14, phase 4 gate): 8 physical devices, kill/background/airplane
  each role mid-battle, measure `didChange` latency and party-code re-entry time. The
  30s grace number may need tuning to iOS realities.

### 7.5 Multiplayer testing story (verified, plan around it)

- There has been **no Game Center sandbox since 2016** (TN2417): dev builds hit
  production with dedicated test Apple IDs. Consequences: create test accounts;
  unreleased leaderboards are visible to friends of test accounts; **prerelease
  connects to release** — hence the protocol version gate.
- **Real-time GKMatch needs physical devices** (simulator real-time matches are
  widely reported broken; Apple's own sample instructs two devices, two Apple IDs).
  Budget hardware: 2 devices minimum for development, borrow/TestFlight to 8 for the
  full-field test.
- Xcode 16.3+'s **Game Progress Manager** (device on iOS 18.4+) covers
  leaderboards/achievements/activities/deep-link testing locally — use it for §8, not
  for GKMatch.
- `WordNet` itself tests without any of this: the host/client sessions run over an
  in-memory mock transport in unit tests (same trick the web could have used), so
  protocol logic — host election (announcement, timeout fallback, late joiners), grace
  timers, seat re-attach, attack splitting, referee, version rejection — is CI-fast.
  Only the GKMatch adapter needs devices.

---

## 8. Game Center as a product layer

Everything in this section is configured via the **Xcode GameKit bundle** (File → New →
GameKit Bundle, synced to App Store Connect) — versioned config in the repo.
Leaderboards/achievements config shipped with Xcode 16.3; activities and challenges
config need Xcode 26 — moot here, since Xcode 26 is already the toolchain (§13).

### 8.1 Leaderboards

| Leaderboard | Type | Score |
|---|---|---|
| Solo — Regular | Classic, all-time | Best score |
| Solo — Fast | Classic, all-time | Best score |
| Daily Deal | **Recurring: 24h duration, 24h restart** (Apple's documented daily-puzzle configuration) | Best score that day |
| Battle wins (optional) | Classic | The app's locally tracked cumulative win count (from stats, iCloud-synced — §9.1's merge makes this correct across devices), submitted as the score after each win. (`context` is a 64-bit annotation on a submission, not an aggregator — Game Center never sums anything for you.) |

Submission via `GKLeaderboard.submitScore(_:context:player:leaderboardIDs:)` from
`finishGame` — the single funnel every game end already flows through. Surface via
`GKAccessPoint` on the home screen (top corner, `showHighlights`) plus a "Standings"
row in the existing Stats page.

### 8.2 The Daily Deal (new mode, small build, biggest retention lever)

**Seed = `"daily/" + date` (salted, see §8.4), tiles drawn from
`createTileStream(seed)`** — battle's hidden-board stream, *not* solo's deal path.
This distinction matters: solo's timed drips grow letters off the player's own live
board (`extendPuzzle(board, …)`), which diverges from everyone else's on the first
move; only the stream's private hidden board yields identical letters for all players.
The mode is therefore "battle's deal plumbing under a solo-style ruleset" (fixed deal
vs. timed run — decide in design), score to the recurring leaderboard. Everyone in the
world gets the same letters each day.

**Rollover semantics must be pinned, not discovered**: capture the seed *and* the
target leaderboard occurrence when the game starts; if the occurrence rolls over before
`finishGame`, suppress the submission with a "too late for today's board" notice
(recurring leaderboards happily accept a stale game's score into the new day's board
otherwise). The same instant drives the widget timeline and streak accounting. Also
decide: the daily reset hour (UTC midnight flips the puzzle at 4–8pm for US players — a
fixed local-friendly hour may be better) and the attempt policy (one attempt NYT-style
vs. unlimited with best-score) — both added to §16.

Why this earns its place in an Apple-platform plan specifically:

- Recurring leaderboards are purpose-built for it (Apple's docs literally use a daily
  mini crossword as the example).
- **iOS 26 Challenges are built on leaderboards** — adopting the daily leaderboard makes
  "challenge your friends to today's deal" a system feature (friend-group score
  competitions with real-time score updates and rematch; Apple doesn't publish a
  participant cap), surfaced in the Games app. The old `GKChallenge` API is deprecated
  in 26; use `GKChallengeDefinition` in the GameKit bundle.
- It powers the widget (§9.3: today's deal, played-or-not, streak), an App Intent
  ("Play the Daily Deal"), and a Games-app activity card (`GKGameActivityDefinition`
  deep-linking into the mode).
- If the web app later adds the same mode, bit-parity (§5) means web and iOS players
  compare the same puzzle — a reason players install the app (the leaderboard lives
  in Game Center).

### 8.3 Achievements

Cap: 100 achievements / 1,000 points. Launch set (~15, all detectable from existing
core events — `finishGame`, `commit`, referee outputs, stats):

first solo game · first battle won · win an 8-player battle · place an 8-letter word ·
clear the pile N times in one solo game · survive to a battle's final round · win a
battle without ever passing 15 pile tiles · play 7 Daily Deals in a row · finish the
tutorial · score 500 in Solo Fast · send 25 attack tiles in one game · win two battles
in a row · play a word through a gap tile · come back from "over the limit" in solo ·
100 games played.

Report from the same `finishGame`/`commit` funnels; `GKAchievement.report` is
idempotent-friendly (percentComplete).

### 8.4 Games app presence and anti-cheat posture

All App Store games appear in the Apple Games app automatically (iOS/iPadOS/macOS 26);
prominence comes from adopting exactly what's above: player auth, leaderboards,
achievements, challenges, and activities, plus normal App Store metadata. No extra work
beyond §8.1–8.3 — this is the payoff for doing them.

Anti-cheat: scores are client-computed (same trust model as the web). For friends-scale
leaderboards that's acceptable. The cheap serverless layers, if global Daily Deal
boards ever matter: (a) submit only through the `finishGame` funnel; (b) **salt the
daily seed with an app-internal constant** — a bare `"daily/" + date` seed is publicly
derivable, letting anyone precompute the puzzle or grind it in a script; (c) clamp
submissions to a client-computed plausibility bound for the day's deal. Residual
client-trust remains and is accepted for v1; Game Center's identity signing
(`fetchItems(forIdentityVerificationSignature:)`) only matters if a companion server
ever exists.

---

## 9. Other Apple services worth adopting

### 9.1 Persistence and iCloud sync

- Local: `UserDefaults` with the same keys/semantics as the web's `localStorage`
  (`nana.stats.v1`, `nana.setup.solo.v1`, `nana.tutorial.v1`, `nana.doors.v1`,
  `nana.sound.v1`, theme) — reads fall back to defaults, writes never throw.
- Sync: **`NSUbiquitousKeyValueStore`** (1 MB / 1,024 keys — the whole stat block is a
  few KB) mirrors stats/settings/streaks across the player's devices with zero UI and
  no sign-in flow. This is the right tool at this data size; CloudKit/SwiftData would
  be over-engineering, and the new **GameSave** framework (file-based iCloud Drive
  saves, conflict UI) is 26-only — adopt later only if save data outgrows KVS.
- **KVS is last-writer-wins per key, so a single stats blob would silently clobber
  itself across devices** (iPhone Monday, iPad Tuesday — whoever syncs last erases the
  other's games). Store per-device stat blobs keyed by device ID and merge on read:
  sums for counters, max for bests, date-set union for streaks. The merge is a pure
  `WordCore` function with tests — and it's what makes the battle-wins leaderboard
  (§8.1) correct.
- Daily Deal streaks live in the same merged store (and the widget reads a shared
  App Group copy).

### 9.2 App Intents / Shortcuts / Spotlight

Three intents, all thin wrappers over existing entry points: **Play Solo** (pace
parameter), **Play the Daily Deal**, **Host a Battle**. They light up Shortcuts, Siri,
Spotlight, and (iOS 18+) Control Center/Action-button launchers, and the same intents
back the widget's interactive button.

### 9.3 WidgetKit

One widget family at launch: **Daily Deal** — small/medium; shows today's date, a
played/unplayed state, and current streak; taps deep-link via the Play-Daily-Deal
intent. Timeline flips at the daily reset hour — a natural fit for WidgetKit's
timeline model. Data design: widgets can't talk to GameKit, so everything rendered
comes from the App Group cache the main app refreshes (on foreground and after a
Daily Deal submission, then `WidgetCenter.reloadTimelines`). That's also why
"your score vs. friends' best" is **dropped from v1**: it would be stale exactly for
the user a widget targets — add it later only with an honest "as of 9:14" cache age.

**Local notifications (opt-in)** close the Daily Deal loop: "today's deal is live" at
the reset hour and "your 6-day streak ends tonight" — `UserNotifications` framework,
no server, a few hours of work (phase 5). This is the standard daily-puzzle retention
mechanism and the plan would be incomplete without it; *remote* push stays rejected
(§9.8 — Game Center already delivers invite/challenge notifications natively).

Skip Live Activities: a real-time P2P match cannot run while backgrounded (no
background execution for game networking; GameKit marks backgrounded players
disconnected), so a "live battle" lock-screen activity would be advertising a state
the app can't sustain. Revisit only if a server ever exists.

### 9.4 Universal Links + Smart App Banner

Careful here — a naive setup contradicts §10's no-cross-play decision. A web battle
invite (`#battle=CODE`) points at a *browser-hosted PeerJS battle the native app cannot
join*; if the app claimed that path, tapping a web invite on iPhone would hijack the
user into an app lobby where the code means nothing. So for v1:

- **Native battle invites ride Game Center's own party URLs** (§7.3) — no work needed
  on the game's domain.
- The app claims `applinks:` only for **app-meaningful paths** (e.g. `/daily` for the
  Daily Deal). Web battle links stay web links. Re-claim `/battle/*` only if/when
  cross-play or the shared web Daily Deal ships. (If the app ever receives a
  web-format code anyway, show "this battle is running on the web — open in Safari".)
- Serve `/.well-known/apple-app-site-association` and add
  `<meta name="apple-itunes-app" content="app-id=…">` to the web app — Safari shows
  install/open banners on iOS. Note both are deployment changes, not just client code:
  the web app is a static SPA, so any path-form link also needs an SPA rewrite rule on
  the host. (Deep-link context doesn't survive App Store install; human-readable codes
  the user can retype are the graceful fallback.)

### 9.5 Game Mode and app categorization

`LSApplicationCategoryType = public.app-category.word-games` +
`LSSupportsGameMode = YES` (18.6+/macOS 26; `GCSupportsGameMode` for 18.0–18.5).
Zero API work; it's Info.plist only. Also required groundwork for Games-app placement.

### 9.6 visionOS (later, cheap)

`WordCore`/`WordNet` compile as-is (GameKit incl. GKMatch is on visionOS since 1.0;
activities/challenges at 26). The iPad build runs in compatibility mode immediately;
a native `Apple Vision` destination is mostly hover/ornament styling work. TabletopKit
(a spatial 3D table) would be a separate product decision, not a port — park it.

### 9.7 SharePlay (optional delighter, after v1)

The Game Center matchmaker already surfaces a SharePlay path on FaceTime calls with no
extra code. Full GroupActivities adoption (custom `GroupActivity` + session messenger)
would duplicate the GKMatch transport for one scenario — only worth it if
play-over-FaceTime becomes a headline use case.

### 9.8 Explicitly not adopting (v1)

StoreKit (free app, no IAP — §16; if monetization comes, StoreKit 2 tip-jar or a
cosmetic theme pack, never pay-to-win in a fair-deal game), CloudKit custom containers,
*remote* push notifications (Game Center invites/challenges notify natively; local
notifications ARE adopted — §9.3), ReplayKit, Multipeer Connectivity (GKMatch
`.nearbyOnly` covers same-room play within Game Center), App Clips — see §10.

---

## 10. The web version and the cross-play decision

**Recommendation: no web↔native cross-play in v1.** Grounds (researched):

- Native P2P with browser peers means embedding a WebRTC stack: Google ships no
  official iOS binaries; the community xcframework is one volunteer with a demonstrated
  5-month gap; lighter `libdatachannel` has no Swift binding; and the app would have to
  speak PeerJS signaling *plus* switch the web side off BinaryPack serialization. All
  feasible, none free, and it keeps the TURN/broker infra alive — negating a main
  benefit of the port.
- Every credible web+iOS cross-play precedent (generals.io, colonist.io, lichess,
  the .io genre) runs through a **server-authoritative WebSocket relay**, not P2P. If
  cross-play ever becomes a requirement, that's the move: a ~200-line room-relay both
  clients speak (the host-authoritative protocol transfers verbatim; ATS just wants
  `wss://`). The bit-parity work in §5 is the enabler either way.
- The audiences barely overlap in practice: a battle among friends will be organized in
  Messages either way, and the app's invite links land web users in §9.4's funnel.

**What happens to the web app**: it stays deployed and unchanged (it's the fixture
generator for parity tests, and the instant-play surface). Add the Smart App Banner +
AASA file; optionally later, the shared Daily Deal.

**App Clips** (instant "join this battle" from a link, no install): parked. GameKit is
*not* on Apple's documented App-Clip-unavailable list, but Game Center auth inside a
clip is unproven in the field, clips get no background networking, and the flow needs a
prototype (the 100 MB digital-invocation tier is comfortable). Without Game Center a
clip has no transport and nothing useful to show, so the post-launch spike is
all-or-nothing: prove GC auth works inside a clip, or drop the idea.

---

## 11. Testing strategy

| Layer | How | Runs where |
|---|---|---|
| Core parity | Golden fixtures from TS (§5) — RNG vectors, stream sequences, generator outputs, attack tables | CI, every commit |
| Core behavior | The eight vitest suites ported to Swift Testing | CI |
| Protocol | `WordNet` host/client over in-memory mock transport: seat grace, re-attach, splitting, referee, version rejection, out-of-order/duplicate defense | CI |
| Gestures | Extract gesture disambiguation as a pure state machine (pointer events in, intents out) and unit-test it exhaustively — XCUITest is the wrong instrument for 300ms holds and 6px slops under CI load, and scripted pinches can't verify anchoring. Keep a smoke-level XCUITest pass; verify pinch anchoring by hand. Plus XCTest performance on board rendering at max zoom-out (load-bearing per §2). | CI (simulator — fine for UI, it's GKMatch that needs devices) |
| Multiplayer integration | Physical-device matrix (§7.5): 2-device dev loop; scripted 8-device session pre-release; kill/background/airplane drills | Manual, phase-gated |
| Game Center config | Xcode Game Progress Manager (leaderboards/achievements/activities, deep links) | Dev machine + device |
| Beta | TestFlight: internal (up to 100) for the friends-and-family battle test — this game's actual QA lab | Continuous from phase 4 |

---

## 12. Repo layout and CI/CD

- Monorepo, as laid out in §4: web app untouched at root, `apple/` beside it,
  `tools/gen-fixtures.mjs` bridging them. Fixtures are committed (deterministic,
  small) and CI regenerates + diffs them so TS drift breaks the Apple build visibly.
- **CI**: GitHub Actions (repo is already here) for SPM tests — `swift test` on a
  macOS runner for `WordCore`/`WordNet` + the fixture-drift check + the existing
  `npm test`. **Xcode Cloud** for archive → TestFlight → App Store (25 free
  compute-hours/month with the developer membership; native GitHub integration;
  signing and distribution handled). This split keeps fast unit feedback in the PR
  loop and zero-maintenance release plumbing.
- App Store Connect config (leaderboards/achievements/activities/challenges) lives in
  the repo as the GameKit bundle — reviewable in PRs like code.

---

## 13. App Store readiness checklist

- [ ] Apple Developer Program membership; App ID with Game Center capability
      (+ iCloud KVS entitlement, Associated Domains, App Groups for the widget).
- [ ] Bundle ID / name decision: "Word" is unsearchable as an App Store name — pick a
      distinct store name (working options: "Word — Tile Battle", "Nana Word Race";
      decision in §16). Repo/product naming unaffected.
- [ ] Privacy nutrition label: **"Data Not Collected"** — per Apple's guidance, you are
      not responsible for disclosing data collected *by Apple* (Game Center is Apple's
      disclosure); data the developer collected via Apple frameworks *would* still need
      declaring — this app collects none, hence the label holds. No ATT, no tracking.
- [ ] Age rating questionnaire (new 2025 system — 4+/9+/13+/16+/18+): expect **4+**;
      a permissive validation dictionary is genre-standard (NYT, Words With Friends)
      and the questionnaire asks about presented content, not wordlists. Don't surface
      profane words in any future hint feature.
- [ ] `ITSAppUsesNonExemptEncryption = NO` (standard OS TLS only).
- [ ] Accessibility Nutrition Labels: declare what §6.6 actually ships.
- [ ] Game Center metadata: leaderboard/achievement artwork + localizations
      (artwork produced in phase 3 alongside the GameKit bundle).
- [ ] Optional: a launch In-App Event (event card imagery + copy, produced with the
      phase-6 store assets) — surfaces in the Games app; cut without ceremony if
      phase 6 runs tight.
- [ ] Build with Xcode 26 SDKs (mandatory for App Store uploads from April 2026 —
      already the plan).
- [ ] Screenshots iPhone/iPad/Mac; App Store description mirroring the web README's
      excellent copy.
- [ ] TestFlight external group (if going past 100 internal testers) → phased release.

---

## 14. Phased roadmap

Estimates assume one experienced developer (with AI pairing), full-time-ish. Each phase
ends in something runnable.

**Phase 0 — Foundations (≈1 week)**
Developer account, App ID, capabilities; Xcode project + package skeleton (§4); CI both
lanes; fixture generator emitting from the TS core; 2 test devices + test Apple IDs.
*Exit: empty app runs on iPhone/iPad/Mac; CI green; fixtures generating.*

**Phase 1 — WordCore (≈1.5–2 weeks)**
Port rng → board → placement → levels → modes → battle → generator → tutorial (tests
first, fixtures throughout). The generator + its insertion-order contract is the long
pole.
*Exit: all ported suites + golden parity tests green. **Gate: fixture parity is
non-negotiable before any UI work consumes the core.***

**Phase 2 — Solo app (≈3–4 weeks, split in two)**
*2a — board + gestures (≈2 weeks)*: board rendering + the unified gesture layer (§6.2),
the gesture state machine + its unit tests, zoom-out perf gate.
*2b — the rest of solo (≈1.5–2 weeks)*: typing, word bar/rack/controls, commit
pipeline, Solo pacing + pause/summary, save/restore across process death, tutorial,
onboarding cards, stats/settings, theme, audio + haptics, accessibility pass.
*Exit: Solo + tutorial fully playable on all three platforms; TestFlight internal.*

**Phase 3 — Game Center core + Daily Deal (≈2–2.5 weeks)**
Auth (including the signed-out/declined path and never-used-Game-Center first-run) +
access point; GameKit bundle with leaderboards/achievements + their artwork;
submission funnels; Daily Deal mode (stream-based deal, rollover semantics, streak) +
recurring leaderboard; iCloud KVS sync with the stats merge; Game Mode plist.
Challenges/activities config included, gated to 26+. (Widget + App Intents moved to
phase 5 — this phase was over-packed with them in.)
*Exit: scores on real boards from test accounts; daily mode live end-to-end;
signed-out mode exercised.*

**Phase 4 — Battle on GameKit (≈3–4 weeks)**
**Week 1 is the spike (§7.4)**: party-code + invite match formation, 8-device mesh
stability, background/kill/rejoin behavior (does party-code re-entry land in the live
match at all?), `didChange` latency — findings can resize this phase. Then: `WordNet`
port over mock transport (CI) including the host-election handshake, GKMatch adapter,
lobby UI (roster from GKPlayers, host "let them back in" affordance), spectator/results,
reconnection + seat grace tuned to iOS, protocol version gate, invite/party-link
handling.
*Exit: an 8-player battle across mixed devices survives drops, backgrounding, and a
host quit; friends-and-family TestFlight running weekly games.*

**Phase 5 — Platform polish (≈1.5–2 weeks)**
Mac menus/shortcuts/window sizing; iPad pointer + keyboard end-to-end; the Daily Deal
widget + App Intents + opt-in local notifications (moved from phase 3);
Designed-for-iPad opt-in review for Vision Pro compatibility mode; performance (board
at max zoom-out, launch time); accessibility labels finalized.

**Phase 6 — Ship (≈2 weeks, elapsed)**
§13 checklist, store assets (including the optional In-App Event card), review
submission (expect one Game-Center-related review round-trip), phased release.
Post-launch backlog seeded: hints from `puzzle.solution` (the web roadmap's own next
item); **live opponent boards** (the web roadmap's other open item — note it breaks the
"tiles never cross the wire" invariant and needs a board-snapshot message, i.e. a
protocol bump; payloads stay small at ≤8 players, no architectural obstacle); visionOS
native; SharePlay; App Clip spike; web Daily Deal parity.

Total: **13–17 weeks of work** (phase 6's two weeks are mostly elapsed review time
overlapping phase-5 polish, which is how the TL;DR's "3–4 months" holds). The two
schedule risks are the gesture layer (phase 2a) and the GKMatch reconnection spike
(phase 4) — both are front-loaded deliberately.

---

## 15. Risks and mitigations

| Risk | Likelihood / impact | Mitigation |
|---|---|---|
| 8-player GKMatch stability on poor networks (28-connection mesh under a star protocol) | Medium / high | An honest ladder, since this is the plan's central technical bet: (1) spike at 8 on real devices, phase-4 week 1; (2) if unstable, ship v1 with a lower `BATTLE_MAX` (4–6) and keep 8 behind a flag; (3) if 8 is a hard requirement and the mesh can't carry it, the answer is the §10 thin WebSocket relay — which reverses part of headline win #1 (serverless), a cost to accept knowingly, not discover late. Note invite-only parties do NOT mitigate this: they change matchmaking, not topology. |
| iOS backgrounding vs battle continuity (no rejoin-by-match-ID API) | High / medium | Seat-grace design absorbs it (game never pauses); documented rejoin path is host-driven `addPlayers` backfill (party-code re-entry into a live match is spike-unknown, §7.4); tune grace from spike data; set player expectations in UI ("switching apps mid-battle risks your seat"). |
| Bit-parity regressions between TS and Swift cores | Medium / high (silently different deals) | Golden fixtures in CI on both sides; order-preserving collections from day one; never "clean up" generator control flow. |
| SwiftUI gesture layer turns out harder than planned | Medium / medium | Phase 2a gives board+gestures a dedicated ~2 weeks (it shares phase 2 with the rest of the solo UI — the buffer is real but not four weeks); the unified-layer design (not per-view gestures) is the known-good shape; the pure gesture state machine keeps regressions caught in CI; SpriteKit remains the escape hatch for the board layer only. |
| Game Center matchmaking UX confuses the friends-and-family audience pre-26 (invites vs typed codes) | Medium / low | Party codes on 26+ solve it; pre-26 gets invites + nearby; keep the playerGroup code-hash trick in the back pocket. |
| No sandbox: prerelease and release clients can meet | Certain / low | `proto` version gate (already in the protocol), bumped on any wire change. |
| Relay latency when Apple falls back from direct P2P (undocumented) | Low / low | Game tolerates hundreds of ms; nothing to do beyond knowing it. |
| Solo dev bus-factor on a 4-month plan | — | Phases each end shippable; TestFlight from phase 2 keeps motivation and feedback live. |

---

## 16. Open questions (decisions needed, none blocking phase 0–2)

1. **Minimum OS floor**: ship 18/15 with 26 features gated (recommended, per §3), or
   go 26-only and delete the fallbacks? Decide by phase 3 (it shapes the join-flow
   work in phase 4).
2. **App Store name** ("Word" won't survive search): pick before phase 6; needs a
   quick availability check in App Store Connect.
3. **Daily Deal rules**: fixed deal vs timed run (cheap to prototype both behind the
   same seed); one attempt NYT-style vs unlimited-with-best-score; and the daily reset
   hour (UTC midnight flips the puzzle mid-afternoon for US players — a fixed
   local-friendly hour may serve better; the leaderboard restart, widget timeline, and
   seed derivation must all share whatever instant is chosen). Decide in phase 3.
4. **Monetization**: v1 free with no IAP (recommended — Game Center features want the
   widest possible friend graph), tip jar later?
5. **Web Daily Deal**: adopt the same date-seed on the web so both platforms share the
   puzzle (drives app installs via the leaderboard)? Cheap once §5 lands.
6. **Battle beyond 8 players?** GKMatch allows 16 — the logic is single-sourced on
   `BATTLE_MAX_PLAYERS`, but the mode-card copy in `modes.ts` (and the README) hardcode
   "2–8 players", so derive those strings from the constants during the port. Gated on
   the phase-4 stability spike and attack-math balance (the split design already
   scales: pressure per player is head-to-head-sized by construction).
