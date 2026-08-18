> Research appendix to [`docs/apple-port-plan.md`](../apple-port-plan.md).
> Generated 2026-08-18 against commit `2b8f271`; file:line references are to that tree.

# Interaction & UI Inventory — "Word" (nana) web game → SwiftUI rebuild reference

All paths absolute. Line numbers from current working tree.

---

## 1. SCREEN MAP & NAVIGATION GRAPH

Top-level router is a single state: `screen: 'home' | 'battle' | 'game'` (/home/user/nana/src/App.tsx:293). Everything else is overlays conditionally rendered on top.

### Screens
| Screen | Component | Rendered at |
|---|---|---|
| Home | `HomeScreen` | App.tsx:2971–3013 |
| Battle doorway (name + host/join form) | `BattleMenu` | App.tsx:3028–3040 (when `screen==='battle'` and no live connection) |
| Battle lobby (code, roster, start) | `BattleLobby` | App.tsx:3018–3026 (when connected) |
| Game (header + board + word bar + rack) | inline | App.tsx:3063–3473 |

### Overlays / dialogs (z-order from styles.css)
- **Toast** pill over board — App.tsx:3228–3232, `.game-toast` z=150, styles.css:333–364.
- **Board alarm** pulsing frame — App.tsx:3224, `.board-alarm::after` z=140, styles.css:2053–2073.
- **BattleSpectator** ("You're out!", live field) — App.tsx:3414–3423, `.spectate` z=180, styles.css:2145–2154. Covers board+header when eliminated or dropped-and-rejoined (`spectating` computed App.tsx:1602–1608). Cannot be dismissed; replaced by results when battle ends.
- **SplashCard** (game start / speedup / battle round announcements) — App.tsx:3376, `.splash-backdrop` z=200 (styles.css:989–998), auto-dismisses after `SPLASH_MS=1700ms` (App.tsx:91, 1380–1384), click-anywhere dismisses early (Splash.tsx:55).
- **ConfirmDialog** (battle restart/lobby/leave confirms) — App.tsx:3443–3471 (game), 3043–3058 (battle screen); shares z=200 backdrop.
- **ModeInfoDialog** — two uses: tutorial intro card (App.tsx:2988–2994, Continue/Skip) and once-ever mode explainer (App.tsx:2996–3000 on home, 3407 over game after tutorial handoff).
- **SetupDialog** (Solo speed sheet, radiogroup of paces + Play) — App.tsx:2954–2969, rendered at 3001 and 3408.
- **GameSummary** (full-screen end report, solo only) — App.tsx:3383–3393, `.summary` z=300 full-screen opaque (styles.css:1044–1051).
- **BattleResults** (standings + own word report) — App.tsx:3429–3440, same `.summary` chrome (BattleResults.tsx:75).
- **StatsPage** / **SettingsPage** — App.tsx:3395, 3397–3404 (also on home 3002–3010); both reuse `.summary` full-screen with fixed `.page-close` X (styles.css:1731–1736).
- **PauseScreen** — App.tsx:3381, `.pause-screen` z=340 fully opaque (styles.css:2274–2284) — deliberately hides the board so a stopped clock can't be used to plan (PauseScreen.tsx:13–21). Escape resumes (PauseScreen.tsx:23–33).
- **ConnectionOverlay** ("Reconnecting…") — App.tsx:3042, 3426, `.net-overlay` z=350 (styles.css:2331–2340), `role="alertdialog"`.
- **Battle notice** pill over home (why a battle ended under you) — App.tsx:2980–2984, `.battle-notice` z=450 (styles.css:2249–2266), tap to dismiss.
- Drag ghosts z=1000 (styles.css:642–652, 760–769).
- **Tutorial banner** (step instructions between header and board) — App.tsx:3190–3219; **tutorial finish band** replaces word bar + rack at script end — App.tsx:3288–3297; Skip + X live in the header corner replacing the Menu — App.tsx:3122–3152.
- **Dictionary error** strip below board — App.tsx:3280–3284.

### Navigation edges
- Home → door: `chooseDoor` (App.tsx:694–707): first game ever → tutorial offer card (`offerTutorial` 665–669); first time through this door → explainer; else `enterDoor` (623–635): **solo → SetupDialog sheet** (opens on last-used pace, setups.ts persisted); **battle → screen 'battle'**.
- SetupDialog Play → `playSetup` (642–647) → `startGame('endless', pace)` → screen 'game'. Dismiss → home (or home from post-tutorial handoff, `dismissSetup` 654–657).
- Home Tutorial button → straight into tutorial, no card (`openTutorial` 683–687). Tutorial exit by any road → `leaveTutorial` (722–730): first-timers continue to the door they picked (via its explainer), tutorial-for-its-own-sake → home.
- Share link `#code` → battle screen with join code prefilled, hash stripped (App.tsx:739–749).
- Battle: host `onStart` → host broadcasts → `handleBattleStart` (752–766) → screen 'game'. Host "everyone to lobby" → `handleBattleStop` (769–779) → screen 'battle'. Connection lost for good / lobby closed → `handleBattleEnded` (783–798) → home + notice. Leave (confirmed if host-with-guests or mid-game, `requestLeaveBattle` 922–933) → home.
- Game header: "Play again" appears when complete && !inBattle (App.tsx:3108–3121). Menu (Menu.tsx) items are conditional: Pause (solo, unfinished only, App.tsx:3158), Reset game (solo), host Restart/To-lobby, Standings/Final score, Settings, Leave/Return home (Menu.tsx:106–129).
- Battle finished → `finishGame('won')` freeze + `BattleResults` raised, win fanfare only for winners (App.tsx:1730–1743). "See the board" closes results over the frozen board (BattleResults.tsx:99–101).

---

## 2. THE BOARD

- **Logical size**: fixed virtual `BOARD_SIZE = 33` (/home/user/nana/src/game/levels.ts:18) but **only the active bounds render**: `boardBounds(board)` (App.tsx:1030) gives a rect that grows as tiles near edges (`GROW_MARGIN = 8`, levels.ts:25) — "the board grows whenever tiles come near an edge, so it can never actually be run out of" (App.tsx:1028–1029). Grid renders row-major divs for bounds only (Grid.tsx:80–99), CSS grid `gridTemplateColumns: repeat(N, var(--cell))` (Grid.tsx:166–168).
- **Viewport**: `.board-wrap` is a flex-1 `overflow: auto` scroll container (styles.css:423–431); board `margin: auto` so small boards center, large ones scroll (comment styles.css:427–430). Scroll is centered on each new game (App.tsx:1015–1021). `contain: paint` on `.board` for overlay performance over 1000+ cells (styles.css:440–446).
- **Cell sizing**: `--cell-base: 44px` desktop, `38px` under 600px width (styles.css:3, 1739–1741); `--cell: calc(var(--cell-base) * var(--zoom,1))` set as inline style var on board-wrap (styles.css:450–452, App.tsx:3236). 1px hairline gap + 1px border (styles.css:437–439). Board tiles are frameless solid fills, `inset: 0`, letter `font-size: calc(var(--cell)*0.52)` (styles.css:529–542) — rounded/shadowed frames removed on the board because they became noise when zoomed out.
- **Zoom**: pinch-driven `zoom` state (App.tsx:474), clamped MIN 0.55 / MAX 1.6 (App.tsx:109–110). **Auto-fit** re-picks zoom whenever tiles change so the whole crossword fits, but only ≤1.0 (`AUTO_ZOOM_MAX=1`), padded by 1 cell, ignoring deltas <0.03; it never scrolls toward the tiles — the viewport-center point (as fraction of tile-box) is restored after the resize in a second `useLayoutEffect` (App.tsx:1089–1133, `measureTiles` 136–157). A ResizeObserver bumps `fitTick` to refit on viewport resize (App.tsx:1071–1077). Manual pinch is left alone until the next placement (comment 1113–1114).
- **Board growth compensation**: when bounds prepend rows/cols, scroll is nudged by exactly that many steps in the same layout pass so tiles don't visibly jump (App.tsx:1035–1046).
- **Placement preview**: `target` = anchored cell+dir if in 'place' mode, else the hovered cell (preview follows pointer while letters are staged and nothing is dragged) (App.tsx:1197–1206, onCellHover 1213–1219). `planPlacement` → `preview` map of ghost letters + `previewGaps` set (App.tsx:1226–1241). Ghosts render as dashed translucent tiles, gap squares emptier still (Grid.tsx:116–124, styles.css:555–570). **Cursor cell** (where the next letter lands, walks ahead of typed letters, skipping over existing tiles) gets a heavy inset ring (App.tsx:1243–1254, styles.css:469–473). **Rotate button** (`➜`/`⬇` glyph) sits in the anchored cell's bottom-right corner, only when the cell can start a word both ways (Grid.tsx:139–157, App.tsx:1222–1224, styles.css:483–507) — it is the only indicator of the assumed direction, and tapping it flips it.
- **Direction assumption**: `assumeDir` — neighbors imply the direction (letter left ⇒ across, above ⇒ down), otherwise the last direction used wins (App.tsx:1175–1186, `lastDir` 433). Tutorial deliberately flips `lastDir` after each step (App.tsx:1993).
- Cells carry `data-cell data-row data-col` (Grid.tsx:96–98) — **the whole drop/hit-test contract is `document.elementFromPoint(x,y).closest('[data-cell]')`**.

---

## 3. INPUT GESTURES — EXACT

Constants: `TAP_SLOP = 6px` (App.tsx:85), `HOLD_DRAG_MS = 300` (App.tsx:94), double-press window 350ms (App.tsx:2568), `UNDO_DEPTH = 50` (App.tsx:88).

### Word-building interaction model
State machine `Interaction = idle | spell(picks) | place(anchor, dir, picks)` (App.tsx:243–248). `picks` are **pile indices in typed order** — a player can pick letters first (spell) or a cell first (place) and switch freely (267–271). Every new game pre-anchors the middle cell in 'place' mode so typing previews immediately (App.tsx:536–539).

1. **Type a word, then tap a square (or vice versa)**: letters typed (or pile tiles tapped) accumulate in `picks`, shown in the WordBar; clicking a cell (`onCellClick` App.tsx:2279–2306) anchors it — staged letters "ride along" to a new anchor without landing. Special-case: exactly one staged letter + click on an empty cell commits immediately with no direction choice (App.tsx:2288–2291). Enter or the green ✓ commits (`commit` 2024–2145); Escape/✗ clears everything (`clearFocus` 1296–1300).
2. **Tap a pile tile**: pointerdown starts a potential drag (App.tsx:3342 → `startDrag` 2418–2433); on pointerup within 6px slop it's a tap → `togglePick(index)` claims/releases the tile for the current word (App.tsx:2443–2446, 1941–1953). Picked tiles lift 4px, invert colors, and wear a small 1-based order badge (Rack.tsx:54, styles.css:572–586).
3. **Drag pile → board**: same pointerdown; past slop it's a drag — a fixed-position ghost tile follows the pointer via direct `style.transform` writes (no React re-render) (App.tsx:2509–2533, 3347–3357). Drop resolves by `elementFromPoint` → `[data-cell]`; lands only on empty cells (App.tsx:2471–2492). On a **locked board** (Battle) a dragged rack tile is routed through `commit()` so dictionary rules and attacks still apply (App.tsx:2456–2469).
4. **Drag board cell → cell**: board tile pointerdown (`onBoardTilePointerDown` App.tsx:2556–2600) starts a drag; source tile hides in place (`hiddenKeys` 2717–2722, `.tile-hidden` styles.css:551). Drop onto empty cell (or its own cell) moves it (App.tsx:2477–2492).
5. **Drag board → pile**: drop resolves `closest('[data-rack]')` (the whole rack wrapper, including over the shuffle button — Rack.tsx:29) and returns the letter (App.tsx:2494–2504).
6. **Tap a board tile**: within slop → `selectTile` (App.tsx:2448–2453 → 2229–2254). If letters are staged: attempts `commitThroughLetter` — places the staged word so its **first gap** lands on the tapped letter, trying the crossing direction first, preferring the fit that spells real words (App.tsx:2168–2217); a word with no gap stays put (a stray tap can't discard it). If nothing staged: selects the tile for deletion (ring, `is-selected` styles.css:667–671) with Delete-direction along its across-run by preference (2240–2243), AND anchors it for continuing a word (2246–2252). On a locked board tap never selects for deletion (2235, 2561–2565).
7. **Double-click / double-tap a board tile** (unlocked boards only): manual detection — two presses on the same key within 350ms (App.tsx:2554–2586; native dblclick is unreliable once pointerdown is preventDefault-ed, comment 2551–2553). On a word's **first letter** → `rotateWord` about that pivot (preferring the across word that can rotate; toast "No room to turn X" if none can) (2573–2582); on any other tile → `returnToRack` (2583).
8. **Word controls popover**: selecting a tile opens `WordControls` above it listing every run through that cell (across and/or down) with name, grab (compass), rotate, trash buttons (Grid.tsx:126–135, WordControls.tsx:28–92); hovering a row highlights the whole word (`is-in-word` fill, styles.css:656–659). Grab pointerdown starts a **whole-word drag**: multi-tile ghost laid across/down follows the pointer, drop moves the word so its first letter lands on the drop cell, keeping its direction (App.tsx:1854–1896, 3359–3374).
9. **Press-and-hold preview drag (touch/pen only)**: with letters staged, holding a **non-tile** board spot for 300ms picks the preview up — a held anchor reverts to 'spell' so the ghost letters follow the finger (via `elementFromPoint` hover updates); movement >6px before the timer fires cancels into a normal pan; release anchors the word at that cell (ready to confirm, not committed) (App.tsx:2616–2701). While active, a non-passive `touchmove` preventDefault vetoes board scrolling (2705–2711), and contextmenu is suppressed (3242–3245). Mouse pointers are excluded — they aim by hovering (2639).
10. **Pinch zoom**: two-finger touch on board-wrap; handled manually because tiles set `touch-action: none` which kills native pinch (comment App.tsx:2741–2743). The board point under the fingers' midpoint is captured **once** as a fraction (fx, fy) of the board's size; every frame re-aims that point at the current midpoint, so zoom+pan is one gesture and rounding never compounds (App.tsx:2751–2756, 2823–2861, `alignPinch` 165–175). rAF-throttled (2793–2821); scroll correction lands in the same layout pass via `useLayoutEffect` (2882–2895); a pending correction survives one commit past finger-lift (2766–2772).
11. **Shuffle**: pinned button in the rack corner reshuffles pile and drops the staged word (Rack.tsx:63–74, App.tsx:2602–2605).
12. **WordBar tile tap** removes that staged letter/gap (WordBar.tsx:102–119).
13. **PileTools row** (shares the word bar): Redo (only rendered when available), Undo, Gap, Rotate (shows the direction it would switch TO), Backspace (PileTools.tsx:46–125). Undo/redo restore full board+rack+staged-picks snapshots; tiles dealt by the clock are retro-added to every snapshot so undo never destroys dealt tiles (App.tsx:952–998, 1452–1459, 2011–2012).

### Keyboard (physical; window-level `keydown`, App.tsx:2310–2414)
There is **no text input field for gameplay** — no hidden input; a global listener handles keys. Guards: only on game screen, not while any overlay/pause/spectate/dialog is up (2315–2321), not with meta/ctrl/alt (2322), not when target is INPUT/TEXTAREA/contentEditable (2323–2325), and a focused BUTTON keeps Space and (when nothing staged) Enter (2329–2331) — every game button also self-blurs after click for this reason (e.g. PileTools.tsx:58–60, App.tsx:3114).
- `a–z`: `typeLetter` — claims the first unclaimed matching pile tile; a letter not in the pile does nothing (App.tsx:2340–2344, 1955–1965).
- `Space`: `addGap` — stages a hole that must land on an existing board letter (2334–2338, 1971–1973).
- `Backspace`: selected board tile first (delete and step **backward** along the word), else un-stage last letter (2346–2357). `Delete`: selected tile, stepping **forward** (holding either eats the word, `deleteSelected` 1908–1932).
- `Escape`: clear selection + anchor + staged word in one press (2360–2367). Also closes Menu (Menu.tsx:62–64) and resumes from Pause (PauseScreen.tsx:25–30).
- `Enter`: commit the previewed placement (2370–2375).
- `ArrowRight` / `ArrowDown`: aim the anchored cell across/down, only if startable that way (2377–2387). (No ArrowLeft/Up.)
- BattleMenu code field: Enter submits join (BattleMenu.tsx:98–100).

### Commit pipeline (every landing goes through it)
`commit(anchor, dir, picks)` (App.tsx:2024–2145): plans placement; locked boards reject with toasts (dictionary loading / lone letter / "X isn't a word") (2041–2062); tutorial gap-step enforcement (2064–2081); plays 'commit' sound (2090); Battle computes and sends attack tiles with a "Sent N tiles across your rivals!" toast (2098–2122); ends the whole gesture via `clearFocus` (2129).

### Post-gesture click swallowing
`swallowNextClick` (App.tsx:487–508): after a drop/tap gesture, the browser's trailing synthetic click would re-anchor a cell; a flag is armed and cleared by the next window-bubble click (with a 500ms backstop timer). `onCellClick` bails while armed (2281). **SwiftUI has no synthetic trailing clicks — drop this mechanism entirely rather than porting it.**

---

## 4. VISUAL STATE LANGUAGE

- **Design language**: monochrome — black/white/grey structural; the *only* color is functional tile feedback (styles.css:6–11). Chunky 2–3px ink borders, `box-shadow: 0 2px 0` pressed-button style with `:active` translateY(2px) (styles.css:378–393).
- **Cell status** `valid | invalid | isolated | disconnected` (App.tsx:196), worst-problem-wins priority: invalid(red) > isolated(yellow, single letters spelling nothing) > disconnected(orange, real word marooned from the main crossword) > valid(green) (App.tsx:1140–1152). Board tiles carry the status as a **solid fill** (border tints vanish frameless) (styles.css:616–635). Token pairs: `--ok-*` green, `--bad-*` red, `--warn-*` orange, `--iso-*` yellow, light styles.css:33–46, dark 71–84.
- **WordBar verdict**: live dictionary check tints the whole bar (`word-bar-good`/`-bad` backgrounds styles.css:803–809) and the staged tiles (`t-valid`/`t-invalid`, WordBar.tsx:107–109); overflow-off-the-grid outranks the verdict for the bad tone (WordBar.tsx:46). The verdict judges the words the board would actually gain (crossings included) once a target exists, else just the typed string ≥3 letters (App.tsx:1265–1293). Color-only — no text verdict (WordBar.tsx:16–18).
- **Header gauges** (Scoreboard.tsx):
  - Score with per-change bump animation (span re-keyed by value, `score-bump` 320ms, styles.css:216–230) and floating **score pops** "+12"/"−12" in green/red that rise and fade (1100ms, styles.css:246–281); pops are watched from the score itself so every board mutation reports identically (App.tsx:1324–1341); suppressed in tutorial/battle (1338).
  - Timer (label "Time" or "Next tiles") with `score-timer-urgent` red 1s pulse when Endless is over the loose limit (App.tsx:3084–3100, styles.css:289–299).
  - **Tile gauge** (`TileGauge`): Endless "Loose tiles N/20" during drip phase; Battle "Pile N/25" with warnAt 15 / urgentAt 20 (App.tsx:2918–2929; limits modes.ts:187,203,207,210). Tones via `tileTone` (Scoreboard.tsx:40–47): green ok → steady orange `warn` within 5 of an implicit limit → blinking orange `alert` (1.1s) → fast red `urgent` (0.55s) → red `over`, where the display flips to "+N / Limit exceeded" (Scoreboard.tsx:95, 147–157; styles.css:301–326).
  - Battle "Standing: N of M" block (App.tsx:1642–1650, Scoreboard.tsx:160–171); "+25 all tiles" bonus chip (Scoreboard.tsx:172–174), hidden on phones (styles.css:1761–1763).
  - Tutorial swaps the score for "Step N of 3" (App.tsx:3073–3077).
- **Board alarm**: whenever the gauge tone is warn/alert (→ orange, 1.1s pulse) or urgent/over (→ red, 0.55s), a 5px border pulses around the entire board area — same color as the count so warnings never disagree (App.tsx:2931–2945, styles.css:2047–2073).
- **Toasts** (`.game-toast`): single slot, keyed by serial so repeats replay; announces dealt tiles ("+5 tiles!"), incoming attacks, placement refusals, rival eliminations ("X is out! N players still standing"), tutorial step completions; auto-clears at 2500ms, CSS animates in/out over 2400ms (App.tsx:415, 1746–1750; toast producers 812–819, 1523, 1626, 1675–1680, 1979–1981, 2004; styles.css:333–364).
- **Elimination**: own = full-screen spectator overlay + earlier 'lose' sound at `finishGame('buried')` (App.tsx:1370); rivals = toast; post-battle = results standings with medals 🥇🥈🥉/ordinals (BattleResults.tsx:27, 119).
- **Theme**: `ThemePref = 'light' | 'dark' | 'system'` persisted to localStorage `nana.theme.v1` (theme.ts:9–35). Applied as `data-theme` on `<html>`; 'system' removes the attribute and a `prefers-color-scheme: dark` media block takes over (styles.css:88–125); applied before first paint (main.tsx:7–9). Dark token block duplicated verbatim for `[data-theme='dark']` (styles.css:50–85). Settings offers Light/Dark/System as a radiogroup (SettingsPage.tsx:15–19, 56–70). Sound toggle is a `role="switch"` slab with animated knob (SettingsPage.tsx:73–91, styles.css:1276–1307).
- **Sounds** (context for haptic/audio parity): commit, deal, attack (lower/falling), tick (last 3s of Endless rounds, once per second, App.tsx:106, 1559–1569), overflow alarm on crossing the loose limit (re-arms on re-crossing, 1578–1588), lose, win; `primeSound` on first gesture (App.tsx:320); toggling sound on plays a demo commit (App.tsx:311–316).

---

## 5. RESPONSIVE BEHAVIOR (phone vs desktop)

Single breakpoint `@media (max-width: 600px)` (styles.css:1738–1849):
- `--cell-base` 44px → 38px (1740).
- Header forced to one row (`flex-wrap: nowrap`), smaller score font (21px vs 26px), bonus chip hidden (1745–1763).
- **WordBar wraps into two rows**: staged letters get a full-width row; all buttons drop to a second row, right-aligned so confirm keeps the thumb corner (1774–1792). Independently, WordBar measures itself every render and hides its hairline dividers when the buttons can't share a row (`word-bar-actions-slim`, WordBar.tsx:50–92 — measure-with-dividers-restored trick inside useLayoutEffect + ResizeObserver).
- Rack: right padding 50px keeps tiles clear of the pinned shuffle button; ≥601px this drops to 18px because the 10-tile-max field never reaches it (styles.css:1355–1389, 1798–1802). Rack rows cap at 10 tiles wide and the field centers while filling left; pile scrolls beyond `max-height: 28vh` (1360–1381).
- Toast becomes multi-line, capped to viewport (1821–1825); splash/summary/home type down-sized (1804–1834).
- `@media (max-width: 540px)`: lobby code 40px → 30px (2391–2395).
- Behavioral (not CSS) differences: hold-to-drag preview and pinch are touch/pen only (App.tsx:2639, 2823); mouse aims previews by hover instead (Grid pointerover delegation, Grid.tsx:169–177; hover tracked only while letters are staged to avoid re-render churn, App.tsx:1213–1219). Typing is effectively desktop-only (no virtual keyboard is ever summoned); touch users stage letters by tapping pile tiles.
- Layout plumbing: `.app` is `height: 100dvh` column (styles.css:144–148); `env(safe-area-inset-bottom)` padding on rack, summary, home, tutorial-finish (1356, 1059, 1439, 1713); viewport meta pins `maximum-scale=1.0, user-scalable=no` (index.html:5) — page zoom is disabled in favor of the board's own pinch.

---

## 6. ANIMATION / TRANSITION INVENTORY

| Animation | Spec | Source |
|---|---|---|
| Score bump | scale 1.22 @40%, 320ms ease-out, replayed via key remount | styles.css:220–230, Scoreboard.tsx:113 |
| Score pop float | rise+fade, 1100ms ease-out forwards; removal on `onAnimationEnd` | styles.css:246–281, Scoreboard.tsx:118–126, App.tsx:1343–1345 |
| Timer/count pulses | `timer-pulse` opacity 0.45 @50%; 1s urgent timer; 1.1s alert; 0.55s urgent count | styles.css:289–326 |
| Toast in/out | translate/fade, 2400ms ease forwards; state cleared at 2500ms | styles.css:347–364, App.tsx:1746–1750 |
| Rack tile drop-in | 600ms `cubic-bezier(0.2,0.9,0.3,1.35)` overshoot, `backwards` fill, staggered 90ms per tile; `tileDrop` state cleared at 1600ms | styles.css:1404–1421, Rack.tsx:43–49, App.tsx:1752–1756 |
| Splash-in | opacity+scale(0.92→1), 180ms ease-out; reused by splash card, summary/stats/settings screens, pause screen | styles.css:1011–1019, 1050, 2283 |
| Splash auto-dismiss | 1700ms timer | App.tsx:91, 1380–1384 |
| Board alarm pulse | border opacity to 0.2 @50%, 1.1s warn / 0.55s urgent, infinite | styles.css:2060–2073 |
| Reconnect dot pulse | 1.1s | styles.css:2370–2383 |
| Settings switch | background/border/knob 140ms ease | styles.css:1286, 1302 |
| Mode card hover/press | translateY −2px/+1px, 120ms | styles.css:1490–1510 |
| Buttons pressed | translateY(2px) + shadow removal on :active | styles.css:390–393, 905–908 |
| Picked rack tile | translateY(−4px) + inverted colors (no transition — snaps) | styles.css:572–577 |
| Endless clear bonus | 900ms delay before banking + refill so the bonus visibly lands first | App.tsx:1691–1703 |
| Copy button "Copied!" | reverts after 1600ms | BattleLobby.tsx:40–44 |
| Drag ghosts | none — raw transform tracking at pointer speed | App.tsx:2511–2517, 1867–1873 |

No spring/layout animations exist for tile placement itself — commits are instant.

---

## 7. ACCESSIBILITY STATE

Present:
- `aria-label`/`title` on every icon button (WordBar.tsx:134,144; PileTools.tsx throughout; Rack.tsx:66–67; Menu.tsx:96–97 + `aria-expanded`; Grid.tsx:146–148 rotate button; WordControls.tsx:50,67,81; dialog/page closes).
- Roles: `dialog`+`aria-modal` on summary/stats/settings/pause/spectate/confirm/mode-info/setup (GameSummary.tsx:96, StatsPage.tsx:25, SettingsPage.tsx:37, PauseScreen.tsx:38, BattleSpectator.tsx:72, ConfirmDialog.tsx:26–28, ModeInfoDialog.tsx:42–43, SetupDialog.tsx:39–41); `alertdialog` on ConnectionOverlay (ConnectionOverlay.tsx:20); `status` on toast, tutorial banner, splash (+`aria-live="polite"`), lobby/battle statuses, spectate standing (App.tsx:3191,3229; Splash.tsx:56; BattleLobby.tsx:119,146; BattleMenu.tsx:113); `alert` on battle error (BattleMenu.tsx:114); `menu`/`menuitem` (Menu.tsx:78,107); `radiogroup`/`radio`+`aria-checked` on setup tabs and theme options (SetupDialog.tsx:60–67, SettingsPage.tsx:56–64); `switch` on sound (SettingsPage.tsx:77–78); `presentation` on backdrops; lobby code gets a spelled-out `aria-label` (BattleLobby.tsx:82); icons are `aria-hidden` + `focusable=false` (icons.tsx:28–29); score pops and decorative marks `aria-hidden` (Scoreboard.tsx:117).
- Pause screen Resume gets `autoFocus` (PauseScreen.tsx:48).

Absent (gaps to fix in the rebuild):
- **The board itself has no accessibility tree**: cells and tiles are plain divs — no role, no label, no focusability, no keyboard navigation of the grid (Grid.tsx:92–158). Rack tiles likewise (Rack.tsx:40–56). Cell status colors have no non-visual equivalent (no text/label for invalid/isolated/disconnected).
- Word verdict is color-only by design (WordBar.tsx:16–18).
- No focus trap in any dialog; no `aria-live` announcements for score/gauge changes; drag & drop has no accessible alternative for moving a single placed tile (though word building itself is fully keyboard-driven, and word controls buttons cover move/rotate/remove).
- Physical-keyboard game input works only through a window listener; there's no visible focus model for it.

---

## 8. SWIFTUI MAPPING NOTES

Maps cleanly:
- Screen router → enum + switch; full-screen pages (summary/stats/settings/pause) → `fullScreenCover`; dialogs/sheets (setup, explainers, confirms) → `.sheet`/custom overlay; setup tabs → segmented Picker; theme → `preferredColorScheme` (`system` = nil) with `@AppStorage`; menus → `Menu`; toasts/splashes → timed overlays; countdowns → the existing wall-clock model (`endsAt` vs frozen `remainingMs`, App.tsx:190–194, 1405–1428) ports directly and is the right model for background/foreground transitions; word bar / rack → wrapping layouts; ResizeObserver divider-dropping → `ViewThatFits`; score pops → transient identifiable array + `.transition`.
- WordControls popover → anchored popover/overlay above the selected tile.
- Rack drop-in stagger, score bump, pulses → standard SwiftUI animation.

Needs care — and what a naive rebuild would get wrong:
1. **One unified pointer pipeline, not per-view gestures.** The web version decides tap vs drag *after the fact* by 6px slop (App.tsx:2443), runs drag tracking on window-level listeners keyed by `pointerId`, and hit-tests drops with `elementFromPoint` against `[data-cell]` — which works across the scrolled, zoomed board, the rack, and screen coordinates uniformly. In SwiftUI, per-cell `.onDrag`/`.gesture` will fight the ScrollView; you need a coordinate-space hit-test (board frame in a named coordinate space → row/col from offset ÷ cell step) and a single drag layer rendering the ghost above everything (web z=1000).
2. **Tiles suppress scrolling (`touch-action: none`, styles.css:524) but empty cells don't** — dragging a tile never pans the board, dragging empty board does. A blanket `simultaneousGesture` or a blanket drag gesture on the board breaks one or the other.
3. **Hold-to-drag preview** (App.tsx:2607–2711): 300ms long-press *on empty board* while letters are staged converts the gesture from pan to preview-drag, un-anchors a held anchor back to 'spell', tracks the finger via hover, and *anchors without committing* on release. During it, scrolling must be hard-disabled (web uses a non-passive touchmove preventDefault). SwiftUI: `LongPressGesture(minimumDuration: 0.3).sequenced(before: DragGesture())` + `.scrollDisabled(isPreviewDragging)`. Note it fires only for touch/pen — keep hover-based aiming for Mac/iPad-pointer.
4. **Manual double-tap detection** (350ms, App.tsx:2554–2586) exists because preventDefault kills native dblclick — in SwiftUI use `.onTapGesture(count: 2)` *but* be aware the web version starts a drag on the *first* press immediately; a naive `TapGesture(count:2).exclusively(before: drag)` adds latency to single-press drags. The web behavior: first press starts a drag candidate AND records the press; the second press within 350ms cancels into rotate/return. Replicate by checking a timestamp inside the unified pointer-down.
5. **Pinch anchoring** (App.tsx:2744–2895): the anchor is a *fraction of the board*, captured once at touch-start and re-aimed at the live midpoint every frame, with the scroll correction applied in the same frame as the size change. Naive `MagnificationGesture` scaling a view inside a ScrollView will drift and snap. Better: keep zoom as a cell-size multiplier (like the CSS var — only tiles resize, chrome doesn't) and compute contentOffset corrections synchronously. Also replicate the clamps (0.55–1.6) and the fact that the *page* never zooms.
6. **Auto-fit zoom** must only ever shrink (cap 1.0), only when tiles change or the viewport resizes, must skip deltas ≤0.03, and must restore the viewport-center point relative to the tile box — it never scrolls toward the crossword (App.tsx:1089–1133). Getting this wrong makes the board "chase" the player.
7. **Board growth compensation**: bounds grow by prepending rows/cols; scroll must be adjusted by exactly the prepended steps in the same layout pass or the board visibly jumps (App.tsx:1035–1046). In SwiftUI, anchoring scroll content to a stable cell coordinate space (e.g., render the full 33×33 logical space, or offset math on bounds change) sidesteps this.
8. **Keyboard**: no hidden text field exists — input is a global keydown listener with careful guards (App.tsx:2310–2414). On Mac/iPad use `.onKeyPress`/keyboard shortcuts at the scene level with the same overlay guards; on iPhone decide whether to surface a virtual keyboard at all (the web game doesn't — pile-tapping is the touch path). If you add one, keep letter-availability rules (`findAvailable` — typing only claims letters actually in the pile) and Space=gap, Enter=commit, Escape=clear, arrows=direction.
9. **Click swallowing** (App.tsx:487–508) is a web artifact — do not port; but DO port its intent: a completed drag/hold gesture must not also register as a tap on the cell underneath.
10. **Preview-follows-pointer** requires hover tracking on Mac/iPad-pointer (`.onContinuousHover`), gated exactly as the web gates it: only while letters are staged and nothing is dragged (App.tsx:1213–1219), or a large board re-renders on every pointer move.
11. **Ghost rendering bypasses state**: web writes `style.transform` directly per pointermove (App.tsx:2513–2516). SwiftUI equivalent: drive the ghost with a `GestureState`/`@State` CGPoint — fine — but keep the ghost in an overlay layer, not inside the scroll view.
12. **Word verdict & preview planning run on every keystroke** (planPlacement + extractRuns over the whole board, App.tsx:1226–1293) — cheap here, but port the memoization pattern.
13. **Locked-board (Battle) mode** changes gesture semantics wholesale: no tile drags off the board, no selection-for-deletion, no double-tap return, no undo; taps still aim gaps/anchor words; every landing (even a single dragged tile) goes through commit's dictionary gate with rejection toasts (App.tsx:935–961, 2041–2062, 2456–2469, 2556–2565).
14. **Pause semantics**: the pause screen is deliberately opaque — the board must not be visible while clocks are stopped (PauseScreen.tsx:13–21, styles.css:2270–2284). Clocks freeze whenever any readable overlay is up in solo (splash, settings, stats), but never in multiplayer except own reconnection (App.tsx:1391–1418).
15. Multi-touch correctness: every drag filters events by `pointerId` (App.tsx:2512, 2519, 1868) — in SwiftUI, ensure a second finger can't hijack an in-flight drag, and that pinch (two fingers) coexists with a held one-finger gesture the way the web's separate touch/pointer channels do.


## KEY FACTS
- Router is one state: screen = 'home' | 'battle' | 'game' (App.tsx:293); everything else is ~15 overlays with explicit z-order (toast 150, spectator 180, dialogs 200, summary 300, pause 340, net 350, notice 450, drag ghosts 1000).
- Board is a virtual 33x33 grid (levels.ts:18) but only the active bounds render, growing with an 8-cell margin as tiles approach edges; scroll is compensated when rows/cols are prepended so tiles never visibly jump (App.tsx:1035-1046).
- Cell size = 44px desktop / 38px <=600px, multiplied by a pinch zoom clamped 0.55-1.6 via a CSS variable so only tiles resize, never the chrome (styles.css:3,1740,450-452; App.tsx:109-110).
- Auto-fit re-picks zoom whenever tiles change but only ever shrinks (cap 1.0, epsilon 0.03, 1-cell pad) and restores the viewport-center point relative to the tile box - it never scrolls toward the crossword (App.tsx:1089-1133).
- Word building is a 3-state machine: idle | spell(picks) | place(anchor,dir,picks); picks are pile indices in typed order, so letters-first and cell-first flows interconvert freely (App.tsx:243-271); each new game pre-anchors the center cell (App.tsx:536-539).
- Tap vs drag on any tile is decided after pointerup by a 6px slop (TAP_SLOP, App.tsx:85, 2443); rack tap = togglePick, board tap = selectTile (gap-aiming commitThroughLetter if letters are staged, else select-for-deletion + anchor).
- All drops are hit-tested with document.elementFromPoint().closest('[data-cell]'/'[data-rack]') in screen coordinates - the whole DnD contract is data attributes, valid at any zoom/scroll (App.tsx:2471-2504, 2683-2688, 1877-1882).
- Double-press on a board tile is manually detected (same key twice within 350ms) because preventDefault on pointerdown breaks native dblclick: on a word's first letter it rotates the word, elsewhere it returns the letter to the pile (App.tsx:2551-2586).
- Press-and-hold (300ms, touch/pen only, on empty board, letters staged) picks the staged word's preview up to drag under the finger; movement >6px first cancels into a pan; release anchors without committing; scrolling is vetoed by a non-passive touchmove listener while active (App.tsx:2607-2711).
- Pinch zoom is hand-rolled (tiles set touch-action:none which kills native pinch): the board point under the fingers is captured once as a fraction and re-aimed every rAF frame, with scroll correction in the same layout pass to avoid tearing (App.tsx:2741-2895, alignPinch 165-175).
- Keyboard is a global window keydown listener - NO hidden input field exists; a-z claims matching pile tiles only, Space stages a gap, Enter commits, Escape clears all, Backspace/Delete eat a selected word backward/forward, ArrowRight/Down aim direction (App.tsx:2310-2414).
- Every landing goes through one commit() pipeline: locked (Battle) boards reject non-words with toasts, battles compute attack tiles there, tutorial validates its gap step there, and the commit sound plays there (App.tsx:2024-2145).
- Cell validation colors, worst-problem-wins: invalid=red > isolated=yellow > disconnected=orange > valid=green, rendered as solid cell fills; same 4 token families in light and dark palettes (App.tsx:1140-1152; styles.css:33-46,71-84,616-635).
- Header tile gauge escalates ok(green) -> warn(steady orange) -> alert(orange blink 1.1s) -> urgent(red blink 0.55s) -> over(red, display flips to '+N over limit'), and the board grows a matching pulsing border frame at the loud stages (Scoreboard.tsx:40-47; App.tsx:2931-2945; styles.css:2047-2073).
- WordBar gives a live dictionary verdict as color only (green/red bar + tiles), judged on the words the board would actually gain including crossings, not just the typed letters (App.tsx:1265-1293; WordBar.tsx:46,107-109).
- Theme = light/dark/system via data-theme attribute on <html>; system removes the attribute and prefers-color-scheme takes over; persisted in localStorage and applied before first paint (theme.ts; main.tsx:9; styles.css:50-125).
- Phone breakpoint (<=600px): smaller cells, one-row header (bonus chip hidden), WordBar wraps to two rows with confirm kept in the thumb corner, rack right-padding for the pinned shuffle button; WordBar also self-measures to drop its dividers when cramped (styles.css:1738-1849; WordBar.tsx:50-92).
- Undo/redo keep 50 board+rack+staged-picks snapshots; clock-dealt tiles are retroactively appended to every snapshot so undo never deletes dealt tiles; battles record no history at all (App.tsx:88,935-998,1452-1459).
- A post-gesture 'swallowNextClick' flag eats the browser's trailing synthetic click after any drop so it can't re-anchor a cell - a web artifact that must NOT be ported literally, but its intent (gesture end != tap) must be (App.tsx:487-508,2281).
- Word controls popover on a selected tile lists every run through that cell with grab (whole-word drag ghost), rotate-about-first-letter, and remove-to-pile; hovering rows highlights the word on the board (WordControls.tsx; App.tsx:1766-1896).
- Splash cards auto-dismiss after 1700ms and pause solo clocks while up; toasts live 2500ms in a single replayable slot; rack tiles drop in with a 600ms overshoot curve staggered 90ms (App.tsx:91,1380-1384,1746-1756; styles.css:1404-1421).
- Countdown model is wall-clock endsAt vs frozen remainingMs, normalized by a single effect as overlays come and go; solo clocks pause for splash/settings/stats/pause, multiplayer clocks pause only for own reconnection (App.tsx:190-194,1391-1428).
- Accessibility: buttons/dialogs/status regions are well labeled (roles dialog/status/menu/radiogroup/switch), but the board grid, board tiles, and rack tiles are bare divs with no roles, labels, focusability, or non-color status encoding (Grid.tsx:92-158; Rack.tsx:40-56).
- Pause screen is deliberately fully opaque - the board must not be readable while clocks are stopped; Escape or Resume returns (PauseScreen.tsx; styles.css:2270-2284).
- The page viewport pins user-scalable=no; the app is 100dvh with safe-area-inset-bottom padding on rack/home/summary (index.html:5; styles.css:144-148,1356).

## RISKS
- Per-view SwiftUI gestures will fight the scrollable board: the web design depends on window-level pointer tracking + coordinate hit-testing (elementFromPoint on data-cell). Rebuild needs one unified drag layer and frame-based row/col math in a named coordinate space, or drags will break at non-default zoom/scroll.
- Tiles block scrolling (touch-action:none) but empty cells pan the board - a blanket drag gesture on the grid breaks one behavior or the other.
- Double-tap semantics: the web starts a drag candidate on the FIRST press and cancels into rotate/return on a second press within 350ms; a naive TapGesture(count:2).exclusively(before:drag) adds latency to every single-press drag.
- Hold-to-drag preview must hard-disable board scrolling while active (web uses non-passive touchmove preventDefault) and fire only for touch/pencil, never mouse; forgetting the 6px pre-fire pan cancel makes panning impossible with letters staged.
- Pinch anchoring: the anchored board point is a fraction captured once and re-aimed every frame, with scroll correction applied in the same frame as the size change; MagnificationGesture scaling a view inside ScrollView will drift and snap back.
- Auto-fit zoom must never enlarge past 1.0, never move the player's focal point, and must skip <3% deltas - otherwise the board 'chases' the player after each placement and fights manual pinch.
- Board bounds grow by prepending rows/cols; without same-frame scroll compensation the whole crossword visibly jumps on edge growth.
- swallowNextClick is a web synthetic-click artifact - port the intent (a completed gesture is not also a tap) but not the mechanism, or you'll introduce phantom 500ms input dead zones.
- No hidden text field exists: keyboard is a global keydown listener with overlay/button-focus guards. On iPhone a virtual keyboard is a design addition, not a port; typing must only claim letters actually present in the pile (findAvailable), Space is the gap key, and Enter/Escape guards around focused buttons matter.
- Battle (locked board) inverts many gesture affordances (no drag-off, no delete-select, no double-tap return, no undo) while keeping tap-to-aim-gap - easy to miss if gestures are wired per-mode-agnostic.
- Timing is contractually meaningful: countdowns are wall-clock deadlines that freeze while specific overlays are up (solo only); multiplayer clocks may never pause except for own reconnection, and drip/expiry effects are guarded against double-firing by refs - a naive Timer-based port can double-deal tiles.
- Score pops are derived by watching the total score, not raised by actions - porting them as per-action events will miss undo/redo/word-removal deltas and double-fire on bonuses.
- The dictionary loads async: word verdicts, locked-board commits, and 'best direction' gap placement all degrade gracefully when it's null - handle the not-yet-loaded state or battles will let non-words down.
- Accessibility of the board is absent in the source (bare divs) - a straight port reproduces an inaccessible grid; SwiftUI rebuild should add labels/rotor actions rather than mirroring the DOM.
- Rack indices are load-bearing: picks reference pile positions, shuffle invalidates them (interaction is reset), and snapshot restore re-maps them - any rack model that reorders tiles without clearing/remapping picks corrupts the staged word.
- Elimination/spectator flow depends on host broadcasts (players[].waiting/buried/left, outOrder); the spectator card never counts self as standing even before the host's echo lands - replicate or the count flickers.