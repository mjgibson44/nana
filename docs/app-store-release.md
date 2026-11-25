# Getting Time Tiles onto the App Store

Where the first App Store release (iOS, **version 1.0.0**) stands, and what's left. Written
2026-11-24 for whoever picks this up next. Read [`apple/README.md`](../apple/README.md) →
"Shipping a build" / "Shipping from CI" for how builds get made; this file is only about
the release.

## Where it stands

**Done**

- **Builds reach TestFlight on their own.** Every merge to `main` that touches `apple/`
  runs [`.github/workflows/release.yml`](../.github/workflows/release.yml): tests,
  archive, export, validate, upload. Build 93 went up this way. (The run after #63 was
  refused by App Store Connect once and the next run worked with no changes; if it happens
  again the log now prints Apple's reason, since `asc.py` writes errors to stderr.)
- **Version 1.0.0, iPhone only.** `MARKETING_VERSION: 1.0.0` and
  `TARGETED_DEVICE_FAMILY: "1"` on the Word target in `apple/project.yml`. iPhone-only was
  a deliberate choice: the layout is a phone column, and iPad would need its own store
  screenshots. `"1,2"` brings iPad back.
- **App icon.** TI/ME in the game's dark-and-green tiles, drawn by
  `apple/tools/make-icon.swift` (`swift apple/tools/make-icon.swift apple`). Picked over
  five other variations.
- **Encryption.** `ITSAppUsesNonExemptEncryption: false` is in the Info.plist, so App
  Store Connect won't ask the export-compliance question per build.
- **Decisions made:** free; no in-app purchases; iPhone only; ship with the current icon.

**Not done** — in order:

1. [ ] **Privacy policy page goes live** at Matt's site, **mjgibson.com** (being built in
   a separate project). The **same URL is used as the Support URL**. As of writing,
   `https://www.mjgibson.com/privacy` serves the home page (the site is a client-side app
   that answers every path), so check the rendered page in a browser, not with `curl`.
   **This blocks submission**: Apple rejects a listing whose privacy URL isn't a policy.
2. [x] **A 1.0.0 build is on TestFlight**: build **99**, uploaded when #65 merged
   (2026-11-24). Pick that one in step 10, or any later 1.0.0 build.
3. [ ] **Sign in to App Store Connect** (Matt — Apple ID + two-factor). Accept any
   pending agreement banner there or on developer.apple.com; a missing agreement makes
   both the web UI and the API refuse.
4. [ ] **Create version 1.0.0** on the iOS app (App Store tab → + version, or it may
   already exist from the build).
5. [ ] **Fill the listing** from [Listing text](#listing-text) below.
6. [ ] **Upload media** — see [Store assets](#store-assets).
7. [ ] **Pricing and availability:** Free, all territories.
8. [ ] **Age rating questionnaire:** answer No throughout → 4+. (The dictionary is a full
   word list, so a player can type crude words themselves; the game never shows any
   unprompted.)
9. [ ] **App Privacy ("nutrition label"):** *Data Not Collected*. The app uses Game Center
   (identity, leaderboards, matchmaking) and iCloud key-value storage for progress — both
   Apple's services, not data the developer collects — and has no analytics, ads or
   tracking SDKs. Web UI only; the API can't set this.
10. [ ] **Pick the build** (the 1.0.0 one) and add **Review notes**: "Solo needs no
    account. Duel and Battle need two Game Center players: one taps HOST and shares the
    code, the other taps JOIN and enters it. A first-time tutorial runs before the first
    mode is opened; it can be skipped from its menu."
11. [ ] **Release option:** manual release after approval is the safer first time.
12. [ ] **Submit for review.** Confirm with Matt before pressing it — it can't be quietly
    undone.

### Doing steps 4–10 by API instead of the web UI

`apple/tools/asc.py` already talks to the App Store Connect API (versions, localizations,
screenshot uploads and review submissions are all available there; the privacy label is
not). It needs `apple/Local.env` (gitignored, see `Local.env.example`) with `ASC_KEY_ID`
and `ASC_ISSUER_ID`, and the key at `~/.appstoreconnect/private_keys/AuthKey_<KEYID>.p8`.
On Matt's Mac the `.p8` is there (`AuthKey_Y52…`) but **no `Local.env` exists**, so the
issuer ID has to come from App Store Connect → Users and Access → Integrations (it's
printed above the key list). CI has both as Actions secrets, which can't be read back.

## Store assets

Made on 2026-11-24 and committed under [`release/`](../release/) at the repo root, with
the listing draft (`release/app-store-listing.md`). Paths below are relative to it. Every
capture is reproducible (below) if any need re-shooting.

| Slot | File | What it shows |
|---|---|---|
| iPhone 6.9" screenshot 1 | `screenshots/01-home.png` | Home: TIME/TILES, Solo, Duel, Battle |
| 2 | `screenshots/02-play.png` | A word held over the board with the gap, green preview |
| 3 | `screenshots/05-battle-attack.png` | Live Battle: "Incoming! +2 tiles from a rival" |
| 4 | `screenshots/03-tutorial-gap.png` | Tutorial's "Borrow a letter" step, gap button lit |
| 5 | `screenshots/04-solo-setup.png` | Solo setup: Regular/Fast toggle, Play |
| App preview 1 | `video/appstore-preview-late-886x1920.mp4` | 29s late game: deal lands, board clear |
| App preview 2 | `video/appstore-preview-886x1920.mp4` | 22s opening game |

Screenshots are 1320×2868 (6.9" iPhone; App Store Connect scales them down for smaller
iPhones). Previews are 886×1920, 30fps H.264 with a silent stereo track, inside Apple's
15–30s window. `screenshots-ipad/` and `icon-variations/` are kept from before the iPhone-only and
icon decisions (`icon-variations/comparison.png` shows the six icons considered) — not
needed for this release. `design-reviews/` holds the renders reviewed while the menus,
tutorial and results screens were redesigned; reference only.

**Caveats:** screenshots 1–5 were taken before the latest changes landed — the opening
camera now starts the first word four cells in (affects 02-play slightly) and the icon
changed (not visible in screenshots). The **game-end screen** changed after capture and
isn't in the set. Re-shoot if any of that matters.

### Regenerating them

Debug builds have capture hooks (`apple/Word/Services/DemoPlayer.swift`, and
`WORD_AUTOSTART` in `RootView`). On an iPhone 18 Pro Max simulator (6.9", 440×956 pt),
dark appearance, with `xcrun simctl status_bar <udid> override --time 9:41
--batteryState charged --batteryLevel 100 --wifiBars 3 --cellularBars 4`:

| Capture | Launch environment (prefix each with `SIMCTL_CHILD_` for `simctl launch`) |
|---|---|
| Home | none — just launch |
| Mid-game, word held | `WORD_AUTOSTART=demo WORD_DEMO_WORDS=2 WORD_DEMO_TAP=0.05 WORD_DEMO_BEAT=0.2`, wait ~15s |
| Late game | `WORD_AUTOSTART=demo WORD_DEMO_WARMUP=12 WORD_DEMO_FILL=2 WORD_DEMO_LEFT=14` (+ `WORD_DEMO_WORDS=1` for a still) |
| Battle attack | `WORD_AUTOSTART=battle-demo WORD_DEMO_ATTACK_AT=5`, screenshot ~5–6s after the game appears (each battle deal is random) |
| Tutorial | `WORD_AUTOSTART=tutorial`, then tap S O L A R, ✓, O |

Then `xcrun simctl io <udid> screenshot --type=png out.png`. For video, `xcrun simctl io
<udid> recordVideo --codec=h264 raw.mov` (stop with SIGINT), trim off the launch (the app
appears ~1.6–1.8s in) and export:

```bash
ffmpeg -ss 1.8 -t 29 -i raw.mov -f lavfi -i anullsrc=channel_layout=stereo:sample_rate=44100 \
  -vf "fps=30,scale=886:-2,crop=886:1920" -c:v libx264 -profile:v high -level 4.0 \
  -pix_fmt yuv420p -b:v 10M -c:a aac -b:a 128k -shortest -movflags +faststart preview.mp4
```

The Solo demo uses a fixed deal (`WORD_DEMO_SEED`, default `timetiles`), so it replays
the same game every time.

## Listing text

Counts are characters against Apple's limits.

- **Name** [30]: `Time Tiles`
- **Subtitle** [30]: `Word race against the pile` (26)
- **Category:** Games → Word; secondary Games → Puzzle
- **Support URL / Privacy Policy URL:** the mjgibson.com privacy page (step 1)
- **Copyright:** `2026 Matthew Gibson` (confirm the name Matt wants shown)

**Promotional text** [170, editable without review]:

> Place one word, then build every word after it through a letter already on the board.
> New tiles keep coming. Keep up, or the pile buries you.

**Keywords** [100]: `crossword,word,game,tiles,letters,puzzle,spelling,anagram,scrabble,multiplayer,battle,duel,brain` (96) — "scrabble" is a trademark; swap for `wordplay` if review objects.

**Description** [4000]:

```
Time Tiles is a fast crossword game about keeping your head above the pile.

You're dealt a pile of letter tiles. Spell a word and put it down. From then on, every new word has to go through a letter that's already on the board: build it with a gap where the borrowed letter goes, tap that letter, and the word drops into place across or down — whichever reads.

Meanwhile the clock keeps dealing you more tiles. Play them faster than they arrive and you'll clear the pile for a bonus. Fall behind, and when the pile hits its limit, the game is over.

SOLO
Play at Regular or Fast pace and chase your best score. Every deal is cut from a real crossword, so there's always a way through.

DUEL
Host a game, share the code, and go head-to-head with a friend on the same stream of tiles.

BATTLE
Up to eight players. Every long word you land sends tiles to your rivals' piles. Last one standing wins.

FEATURES
• A short tutorial that teaches the one move the whole game is built on
• Live word checking against a 170,000-word dictionary — green reads, red doesn't
• Hold a word over a letter to preview exactly where it will land
• Game Center leaderboards, and progress that follows you across devices
• No ads, no accounts to make, no timers to buy
```

**What's New** — not shown for a first release; keep for 1.0.1.

## Known gaps worth knowing before review

- **Duel/Battle haven't been exercised against live Game Center** (host, join by code,
  share). The README's "What's left" section says the same of Game Center generally. A
  reviewer will likely try Solo only, but a two-device test before submitting is cheap.
- **Daily, Occupy and the board modifiers are hidden, not deleted** — their code and
  tests remain; none is reachable from the UI.
