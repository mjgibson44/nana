import Foundation
import Observation
import WordBoard
import WordCore

/// A tile's live feedback color, worst problem first (App.tsx:196, 1140–1152).
enum CellFeedback: Equatable {
    case valid
    case invalid
    case isolated
    case disconnected
}

/// Word-building state, shared by every input flow (App.tsx:243–271):
///
///  - `spell`: letters were chosen first (typed or tapped from the pile) and
///    are waiting for a cell to land on;
///  - `place`: a board cell was chosen first — it always comes with a
///    direction, so letters preview from it as soon as they arrive.
///
/// `picks` holds pile indices in typed order in both cases, so a player can
/// start either way round and switch freely.
enum Interaction: Equatable {
    case idle
    case spell(picks: [Int])
    case place(anchor: CellKey, dir: Direction, picks: [Int])

    var picks: [Int] {
        switch self {
        case .idle: return []
        case let .spell(picks): return picks
        case let .place(_, _, picks): return picks
        }
    }

    func withPicks(_ picks: [Int]) -> Interaction {
        if case let .place(anchor, dir, _) = self {
            return .place(anchor: anchor, dir: dir, picks: picks)
        }
        return picks.isEmpty ? .idle : .spell(picks: picks)
    }
}

struct Selection: Equatable {
    var key: CellKey
    var dir: Direction
}

/// A tile riding under the pointer (App.tsx `DragState`, 200–206). The source
/// tile hides in place while the ghost follows.
struct TileDrag: Equatable {
    var letter: String
    var source: GestureMachine.DragSource
    var location: CGPoint
}

/// The single toast slot, keyed by serial so repeats replay (App.tsx:415).
struct GameToast: Equatable {
    var text: String
    var serial: Int
}

/// Keyboard vocabulary kept independent of SwiftUI's `KeyPress`, so the
/// global hardware-keyboard behavior is unit-testable (App.tsx:2310–2414).
enum GameCommand: Equatable {
    case letter(String)
    case gap
    case backspace
    case deleteForward
    case escape
    case confirm
    case direction(Direction)
}

private struct GameSnapshot {
    var board: TileMap
    var rack: [String]
    var picks: [Int]
}

/// A whole word riding under the pointer from the selected-word popover.
struct WordDrag: Equatable {
    var word: WordRun
    var letters: [String]
    var location: CGPoint
}

struct ScoredWord: Equatable {
    var word: String
    var points: Int
}

enum SoloGaugeTone: Equatable {
    case ok
    case warn
    case over
}

/// A finished game, frozen — what the stats funnel, and later Game Center,
/// are handed. Carrying the mode and the daily identity (rather than just a
/// score) is what lets one funnel serve Solo, the Daily Deal and whatever
/// phase 3 hangs off it.
struct GameOutcome: Equatable {
    /// What the game saw, in the shape the achievement evaluator wants.
    var report: GameReport
    var words: Int
    var tilesLeft: Int
    var bonusEarned: Bool
    var daily: DailyDeal?

    var mode: GameMode { report.mode }
    var score: Int { report.score }
}

/// How many seconds of an Endless round tick down to the tiles landing. Three
/// beats is long enough to be a warning and short enough not to be a metronome
/// (App.tsx:102–106).
let ENDLESS_TICK_FROM = 3

/// The solo board's interaction model, ported from the word-building half of
/// `App.tsx`. Phase 2a supplied the board and unified gesture layer; this model
/// also owns phase 2b's editing loop and Solo session lifecycle. Tutorial and
/// battle wiring arrive in later slices.
@Observable @MainActor
final class GameModel {
    private(set) var board = TileMap()
    private(set) var rack: [String] = []
    private(set) var interaction: Interaction = .idle
    private(set) var selection: Selection?
    private(set) var hoverCell: CellKey?
    private(set) var lastDir: Direction = .across
    private(set) var drag: TileDrag?
    private(set) var wordDrag: WordDrag?
    private(set) var toast: GameToast?
    private(set) var dictionary: Set<String>?
    private(set) var seed = ""
    private(set) var solo = SoloSession(pace: .regular, now: .distantPast)
    private(set) var bankedBonus = 0
    private(set) var finalScore = 0
    private(set) var finalTilesLeft = 0
    private(set) var finalBonusEarned = false
    private(set) var finalWords: [ScoredWord] = []
    private(set) var showSummary = false
    /// Bumped per deal so the viewport knows to re-center.
    private(set) var gameSerial = 0
    var boardLocked = false

    /// Which mode is being played. Battle joins in phase 4; the tutorial runs
    /// the scripted lesson with no clock and no score.
    private(set) var mode: GameMode = .endless
    /// Which day's Daily Deal this is, captured when the game *starts*.
    ///
    /// Held for the length of the game on purpose (plan §8.2): the puzzle can
    /// roll over mid-game, and the result belongs to the day it was begun on,
    /// not the day it happened to end on.
    private(set) var daily: DailyDeal?

    /// The battle's clock and deal position, while `mode == .battle`.
    private(set) var battle: BattleRun?
    /// Which round the battle is in, refreshed by the clock tick. Held rather
    /// than computed so `commit` — which has no clock of its own — values a
    /// word by the round it actually landed in.
    private(set) var battleRound = 1
    /// Watching rather than playing: buried already, or joined mid-game and
    /// waiting for the next start (App.tsx:1605–1609). A dead board takes no
    /// drips and can't be buried twice.
    var spectating = false
    /// The shared deal. Every player's stream is seeded identically, so drip
    /// *k* is the same letters on every screen.
    private var battleStream: TileStream?
    /// This player's private attack stream, seeded `<seed>/attacks/<selfID>`.
    /// Only counts cross the wire; the letters are drawn locally.
    private var attackStream: TileStream?

    /// A word landed and owes the field tiles. The session splits and sends it.
    var onBattleAttack: ((Int) -> Void)?
    /// The lesson's progress while `mode == .tutorial`.
    private(set) var tutorial: TutorialRun?

    /// Who sounds the game's cues (audio + haptics). Optional so tests and
    /// previews stay silent, and so the model never imports AVFoundation.
    var cues: GameCueSink?

    /// The last Endless tick sounded, keyed by round deadline and second so
    /// the 4Hz heartbeat plays each of the last three beats exactly once
    /// (App.tsx:1559–1569).
    private var tickedKey: String?
    /// Whether the loose pile is currently over the limit. Digging back under
    /// re-arms the alarm, so a player riding the limit is warned every time
    /// they cross it (App.tsx:1578–1588).
    private var overflowing = false

    // Recomputed once per board change rather than per render.
    private(set) var bounds = boardBounds(TileMap())
    private(set) var validation: BoardValidation?
    private(set) var wordsByCell: [CellKey: [WordRun]] = [:]
    private(set) var tileBounds: Bounds?
    private(set) var cellFeedback: [CellKey: CellFeedback] = [:]

    // What this game has seen, for the achievement evaluator (plan §8.3).
    // All of it falls out of funnels that already exist — `commit`,
    // `claimBoardClear`, and the overflow alarm — so nothing here changes how
    // the game plays.
    private(set) var usedGapTile = false
    private(set) var longestWordPlaced = 0
    private(set) var boardClears = 0
    private(set) var recoveredFromOverLimit = false

    private var toastSerial = 0
    private var dealSerial = 0
    private var finishRecorded = false
    private var history: [GameSnapshot] = []
    private var future: [GameSnapshot] = []

    private static let undoDepth = 50

    // MARK: Derived word-building state

    var picks: [Int] { interaction.picks }

    var pickList: [Pick] {
        picks
            .filter { $0 == GAP || rack.indices.contains($0) }
            .map { $0 == GAP ? Pick(letter: nil, rackIndex: GAP) : Pick(letter: rack[$0], rackIndex: $0) }
    }

    /// The direction to use for a cell without asking; nil means the cell
    /// can't start a word at all (App.tsx:1175–1186).
    func assumeDir(_ key: CellKey) -> Direction? {
        let cell = parseKey(key)
        let startable = startableDirections(board: board, bounds: bounds, cell: cell)
        if startable.isEmpty { return nil }
        let implied = impliedDirections(board: board, cell: cell).filter { startable.contains($0) }
        let choices = implied.isEmpty ? startable : implied
        return choices.contains(lastDir) ? lastDir : choices[0]
    }

    /// Where the word would go right now: a chosen cell owns the preview;
    /// until then staged letters follow the pointer (App.tsx:1197–1206).
    var target: (key: CellKey, dir: Direction)? {
        if case let .place(anchor, dir, _) = interaction { return (anchor, dir) }
        if let hoverCell, !picks.isEmpty, let dir = assumeDir(hoverCell) {
            return (hoverCell, dir)
        }
        return nil
    }

    var plan: PlacementPlan? {
        guard let target, !pickList.isEmpty else { return nil }
        return planPlacement(
            board: board, bounds: bounds, anchor: parseKey(target.key), dir: target.dir,
            picks: pickList)
    }

    var preview: [CellKey: String] {
        guard let plan else { return [:] }
        return Dictionary(uniqueKeysWithValues: plan.steps.map { ($0.key, $0.letter) })
    }

    var previewGaps: Set<CellKey> {
        Set(plan?.unfilledGaps ?? [])
    }

    /// The square the next letter lands on (App.tsx:1248–1254).
    var cursorKey: CellKey? {
        guard case let .place(anchor, dir, _) = interaction else { return nil }
        let cursor = cursorCell(
            board: board, bounds: bounds, anchor: parseKey(anchor), dir: dir, picks: pickList)
        return cursor.map { keyOf($0.row, $0.col) }
    }

    /// Only offer to rotate when the cell genuinely could go either way.
    var canRotateAnchor: Bool {
        guard case let .place(anchor, _, _) = interaction else { return false }
        return startableDirections(board: board, bounds: bounds, cell: parseKey(anchor)).count > 1
    }

    /// Controls get out of the way while something is being dragged.
    var showRotate: Bool { canRotateAnchor && drag == nil }

    /// The dragged board tile, hidden in place while its ghost follows.
    var hiddenBoardKey: CellKey? {
        if case let .board(cell, _) = drag?.source { return keyOf(cell.row, cell.col) }
        return nil
    }

    /// The dragged rack tile, likewise.
    var hiddenRackIndex: Int? {
        if case let .rack(index, _) = drag?.source { return index }
        return nil
    }

    /// Only show the ring while there is still a tile there to delete.
    var selectedKey: CellKey? {
        guard let selection, board[selection.key] != nil else { return nil }
        return selection.key
    }

    /// Live dictionary check on the word being built (App.tsx:1265–1293).
    var verdictOK: Bool? {
        guard let dictionary, let plan, plan.complete else { return nil }
        var next = board
        for step in plan.steps { next[step.key] = step.letter }
        let placed = Set(plan.steps.map(\.key))
        let runs = extractRuns(next).filter { $0.cells.contains { placed.contains($0) } }
        if runs.isEmpty { return nil }
        return runs.allSatisfy { $0.word.count >= MIN_WORD_LENGTH && dictionary.contains($0.word) }
    }

    var canConfirm: Bool {
        guard case .place = interaction, let plan else { return false }
        return plan.complete && !plan.steps.isEmpty && (!boardLocked || (verdictOK ?? false))
    }

    var canCancel: Bool { interaction != .idle || selectedKey != nil }

    var canUndo: Bool { !boardLocked && !history.isEmpty }
    var canRedo: Bool { !boardLocked && !future.isEmpty }
    var canBackspace: Bool { selectedKey != nil || !picks.isEmpty }

    // MARK: Derived Solo state

    var pace: SoloPace { solo.pace }
    var phase: SoloPhase { solo.phase }
    var dripsElapsed: Int { solo.dripsElapsed }
    var countdown: SoloCountdown? { solo.countdown }
    var isPaused: Bool { solo.paused }
    var splash: SoloSplash? { solo.splash }
    var isComplete: Bool { solo.complete }
    var endReason: SoloEndReason? { solo.endReason }

    /// Full-screen/readable overlays own input while visible. A finished board
    /// remains viewable but cannot be changed after the summary is dismissed.
    var canAcceptInput: Bool {
        !isComplete && !isPaused && splash == nil && !showSummary
    }

    var canPause: Bool { !isComplete && !isPaused && splash == nil }

    var boardScore: BoardScore {
        scoreBoard(validation, tilesLeft: rack.count)
    }

    /// Word points stay live; only the 25-point board-clear awards are banked.
    var runningScore: Int {
        bankedBonus + boardScore.words
            + (boardScore.bonusEarned ? ENDLESS_CONNECT_BONUS : 0)
    }

    var score: Int { isComplete ? finalScore : runningScore }

    /// Tiles still in the pile, plus placed tiles that are not part of a valid,
    /// connected word. This matches App.tsx's pressure gauge exactly.
    var looseTiles: Int {
        rack.count + cellFeedback.values.filter { $0 != .valid }.count
    }

    var showsLooseGauge: Bool { mode == .endless && phase == .drip && !isComplete }

    /// The tutorial has no clock at all — its board waits for the player
    /// (App.tsx:379–380).
    var showsClock: Bool { mode == .endless }

    var isTutorial: Bool { mode == .tutorial }
    var isDaily: Bool { mode == .daily }
    var isBattle: Bool { mode == .battle }

    /// Battle's pile gauge counts tiles in hand against a hard limit — unlike
    /// Solo's, which counts anything loose and treats the limit as a deadline.
    var battlePileTone: SoloGaugeTone {
        guard mode == .battle else { return .ok }
        if rack.count >= BATTLE_PILE_URGENT { return .over }
        if rack.count >= BATTLE_PILE_WARN { return .warn }
        return .ok
    }

    /// The Daily Deal's pressure isn't a clock, it's the pile: a fixed deal,
    /// and every tile you can't place costs you the bonus.
    var showsTilesLeft: Bool { mode == .daily }

    /// A daily can be handed in at any point; there's nothing to run out of.
    var canFinishDaily: Bool { mode == .daily && !isComplete }

    /// The tutorial's step counter takes the score's corner (App.tsx:3070–3077).
    var tutorialProgress: (step: Int, of: Int)? {
        guard let tutorial else { return nil }
        return (tutorial.displayStep, TUTORIAL_STEPS)
    }

    /// Every word is down: the way out replaces the pile and the word bar
    /// (App.tsx:3286–3297).
    var tutorialFinished: Bool { tutorial?.isDone ?? false }

    var gaugeTone: SoloGaugeTone {
        guard showsLooseGauge else { return .ok }
        if looseTiles > ENDLESS_LOOSE_LIMIT { return .over }
        if ENDLESS_LOOSE_LIMIT - looseTiles <= 5 { return .warn }
        return .ok
    }

    var boardClearReady: Bool {
        !isComplete && boardScore.bonusEarned && drag == nil && wordDrag == nil
    }

    func remainingSeconds(at now: Date) -> Int? {
        solo.remaining(at: now).map { Int(ceil($0)) }
    }

    /// Every run through the selected tile. A crossing offers both rows.
    var selectedWords: [WordRun] {
        guard let selectedKey else { return [] }
        return wordsByCell[selectedKey] ?? []
    }

    var highlightedKeys: Set<CellKey> {
        Set(highlightedWord?.cells ?? [])
    }

    private(set) var highlightedWord: WordRun?

    /// The anchored direction, when a cell is chosen.
    var interactionDir: Direction? {
        if case let .place(_, dir, _) = interaction { return dir }
        return nil
    }

    // MARK: Game lifecycle

    func newGame(
        seed: String = randomSeed(), pace: SoloPace = .regular, now: Date = .now
    ) {
        self.seed = seed
        mode = .endless
        tutorial = nil
        daily = nil
        clearBattle()
        solo = SoloSession(pace: pace, now: now)
        gameSerial += 1
        setBoard(TileMap())
        let puzzle = try? generatePuzzle(
            wordPool: commonWords, tileCount: ENDLESS_START_TILES, rng: seededRng(seed))
        rack = puzzle?.letters ?? []
        resetPlayState()
    }

    /// The host said go. Grow the shared deal from the seed and dive in.
    ///
    /// Battle's board is **locked**: a word placed is permanent, so only real
    /// words may land (the `boardLocked` branch of `commit` already enforces
    /// that). The opening batch is `BATTLE_START_TILES` for everyone, which is
    /// what keeps the shared stream in step — every client asks the stream for
    /// the same first number.
    func newBattle(
        seed: String, selfID: String, spectating: Bool = false, now: Date = .now
    ) {
        self.seed = seed
        mode = .battle
        tutorial = nil
        daily = nil
        self.spectating = spectating
        boardLocked = true
        battle = BattleRun(startedAt: now)
        battleRound = 1
        let stream = TileStream(seed: seed)
        battleStream = stream
        attackStream = TileStream(seed: "\(seed)/attacks/\(selfID)")
        solo = SoloSession(battleAt: now)
        gameSerial += 1
        setBoard(TileMap())
        rack = spectating ? [] : stream.next(BATTLE_START_TILES)
        resetPlayState()
    }

    /// Our share of a rival's word. Only the count crossed the wire; the
    /// letters come off this player's private stream (App.tsx:803–819).
    func receiveAttack(_ count: Int) {
        guard mode == .battle, !isComplete, !spectating, count > 0,
            let attackStream
        else { return }
        let letters = attackStream.next(count)
        guard !letters.isEmpty else { return }
        appendDealtTiles(letters)
        // Sent tiles get their own voice — lower and falling, so incoming
        // trouble never sounds like tiles you earned.
        cues?.play(.attack)
        rejectToast(
            "Incoming! +\(letters.count) tile\(letters.count == 1 ? "" : "s") from a rival")
        checkBattleBurial()
    }

    /// Battle's one loss rule: let the pile past the limit, for any reason at
    /// any moment, and you're out on the spot (App.tsx:1636–1639).
    private func checkBattleBurial() {
        guard mode == .battle, !isComplete, !spectating else { return }
        if rack.count > BATTLE_PILE_LIMIT { finishGame(reason: .buried) }
    }

    /// Deal today's puzzle.
    ///
    /// The letters come from `TileStream` — battle's hidden-board deal — and
    /// not from Solo's `extendPuzzle(board:)` path, which grows tiles off the
    /// player's *live* board and so would deal everyone something different
    /// the moment they made a move (plan §8.2).
    func newDaily(deal: DailyDeal, now: Date = .now) {
        seed = deal.seed
        mode = .daily
        tutorial = nil
        clearBattle()
        daily = deal
        solo = SoloSession(dailyAt: now)
        gameSerial += 1
        setBoard(TileMap())
        rack = TileStream(seed: deal.seed).next(DailyRules.tileCount)
        resetPlayState()
    }

    /// Hand today's board in. Unlike Solo there is no losing condition to
    /// trip — the player decides when they're done with the letters.
    func finishDaily() {
        guard canFinishDaily else { return }
        finishGame(reason: .dailyDone)
    }

    /// Start the guided lesson. Its first word is dealt spelled out in a row
    /// rather than shuffled — step one is about getting a word down at all
    /// (App.tsx:527–530) — and there is no clock to run out.
    func newTutorial(now: Date = .now) {
        seed = "tutorial"
        mode = .tutorial
        daily = nil
        clearBattle()
        tutorial = TutorialRun()
        solo = SoloSession(tutorialAt: now)
        gameSerial += 1
        setBoard(TileMap())
        rack = tutorialScript[0].tiles
        resetPlayState()
    }

    /// Leave battle behind — every other mode deals its own way.
    private func clearBattle() {
        battle = nil
        battleStream = nil
        attackStream = nil
        battleRound = 1
        spectating = false
        boardLocked = false
    }

    /// Everything a fresh board resets, whatever dealt it.
    private func resetPlayState() {
        selection = nil
        drag = nil
        wordDrag = nil
        hoverCell = nil
        toast = nil
        bankedBonus = 0
        finalScore = 0
        finalTilesLeft = 0
        finalBonusEarned = false
        finalWords = []
        showSummary = false
        dealSerial = 0
        finishRecorded = false
        lastDir = .across
        highlightedWord = nil
        history = []
        future = []
        tickedKey = nil
        overflowing = false
        usedGapTile = false
        longestWordPlaced = 0
        boardClears = 0
        recoveredFromOverLimit = false
        // Pre-anchor the middle cell so typing previews immediately
        // (App.tsx:536–539).
        let middle = keyOf(BOARD_SIZE / 2, BOARD_SIZE / 2)
        interaction = .place(anchor: middle, dir: assumeDir(middle) ?? .across, picks: [])
    }

    func dismissSplash(at now: Date = .now) {
        solo.dismissSplash(at: now)
    }

    func pause(at now: Date = .now) {
        solo.pause(at: now)
        clearTransientInput()
    }

    func resume(at now: Date = .now) {
        solo.resume(at: now)
    }

    /// Called by the UI heartbeat. The session machine changes its deadline
    /// before emitting, so the same expiry can never deal twice.
    func advanceClock(at now: Date = .now) {
        if mode == .battle {
            advanceBattle(at: now)
            return
        }
        switch solo.advance(at: now, looseTiles: looseTiles) {
        case .none:
            break
        case let .deal(tiles):
            dealBonusTiles(tiles, message: "+\(tiles) tile\(tiles == 1 ? "" : "s")!")
        case .buried:
            finishGame(reason: .buried)
        }
        soundTick(at: now)
        soundOverflow()
    }

    /// The battle's tick: keep the round current, land a drip when one is due.
    private func advanceBattle(at now: Date) {
        guard var run = battle else { return }
        battleRound = run.round(at: now)
        guard !isComplete, !spectating else {
            battle = run
            return
        }
        if let tiles = run.advance(at: now), let stream = battleStream {
            let letters = stream.next(tiles)
            appendDealtTiles(letters)
            rejectToast("+\(letters.count) tile\(letters.count == 1 ? "" : "s")")
            cues?.play(.deal)
        }
        battle = run
        checkBattleBurial()
    }

    /// The last few seconds of an Endless round tick, once a second, so the
    /// tiles about to land are heard coming (App.tsx:1552–1569). Keyed by
    /// deadline and second: the heartbeat runs at 4Hz, and a held clock is
    /// silent because a paused countdown reports no deadline.
    private func soundTick(at now: Date) {
        guard mode == .endless, !isComplete, !solo.clockHeld,
            case let .running(endsAt) = solo.countdown
        else { return }
        let second = Int(ceil(max(0, endsAt.timeIntervalSince(now))))
        guard second >= 1, second <= ENDLESS_TICK_FROM else { return }
        let key = "\(endsAt.timeIntervalSinceReferenceDate):\(second)"
        guard tickedKey != key else { return }
        tickedKey = key
        cues?.play(.tick)
    }

    /// Crossing the loose limit sounds the alarm — a warning, not a verdict:
    /// the round's remaining seconds are the deadline to dig back under.
    /// Digging under re-arms it (App.tsx:1571–1588).
    private func soundOverflow() {
        guard mode == .endless, phase == .drip, !isComplete else {
            overflowing = false
            return
        }
        let over = looseTiles > ENDLESS_LOOSE_LIMIT
        guard over != overflowing else { return }
        // Crossing back *under* is the comeback the badge is for.
        if overflowing, !over { recoveredFromOverLimit = true }
        overflowing = over
        if over { cues?.play(.overflow) }
    }

    /// The clear bonus lands before the refill. The view supplies the web's
    /// 900ms presentation delay and this method re-checks the board afterward.
    func claimBoardClear() {
        guard boardClearReady else { return }
        bankedBonus += ENDLESS_CONNECT_BONUS
        boardClears += 1
        dealBonusTiles(
            ENDLESS_CLEAR_TILES,
            message:
                "Board clear! +\(ENDLESS_CONNECT_BONUS) points · +\(ENDLESS_CLEAR_TILES) tiles")
    }

    func setSummaryPresented(_ presented: Bool) {
        guard isComplete else { return }
        showSummary = presented
    }

    func finishGame(reason: SoloEndReason) {
        guard !finishRecorded else { return }
        finishRecorded = true
        finalScore = runningScore
        finalTilesLeft = rack.count
        finalBonusEarned = boardScore.bonusEarned
        finalWords = (validation?.runs ?? [])
            .filter(\.valid)
            .map { ScoredWord(word: $0.word, points: wordScore($0.word)) }
        solo.finish(reason: reason)
        showSummary = true
        clearTransientInput()
        clearFocus()
        switch reason {
        case .buried:
            // Buried, or out of time: the game beat you (App.tsx:1370).
            cues?.play(.lose)
        case .dailyDone:
            // Nobody loses a daily — you hand in whatever you built.
            cues?.play(.win)
        }
        // One funnel for every ending, so stats are recorded exactly once.
        onFinish?(outcome)
    }

    /// Everything a finished game is worth knowing about, frozen.
    ///
    /// The battle fields stay at their defaults until phase 4 fills them, at
    /// which point six achievements light up with no change here.
    var outcome: GameOutcome {
        GameOutcome(
            report: GameReport(
                mode: mode,
                pace: pace,
                score: finalScore,
                longestWord: longestWordPlaced,
                usedGapTile: usedGapTile,
                boardClears: boardClears,
                recoveredFromOverLimit: recoveredFromOverLimit,
                tutorialFinished: tutorialFinished),
            words: finalWords.count,
            tilesLeft: finalTilesLeft,
            bonusEarned: finalBonusEarned,
            daily: daily)
    }

    /// Called once per finished game — the single stats/leaderboard funnel
    /// every game end flows through (plan §8.1 hangs Game Center submission
    /// here in phase 3).
    var onFinish: ((GameOutcome) -> Void)?

    func loadDictionary() async {
        guard dictionary == nil, let parsed = await WordDictionary.shared() else { return }
        dictionary = parsed
        refreshBoardCaches()
    }

    // MARK: Word building

    func setPicks(_ next: [Int]) {
        interaction = interaction.withPicks(next)
    }

    /// The hardware-keyboard contract. `true` means the app consumed the key;
    /// callers return `.handled` so focus traversal and system beeps stay out.
    @discardableResult
    func handle(_ command: GameCommand) -> Bool {
        switch command {
        case let .letter(letter):
            guard letter.count == 1, letter.first?.isLetter == true else { return false }
            typeLetter(letter)
            // The web prevents the key even when this letter isn't in the
            // pile; an unavailable letter is a quiet no-op, never a system
            // beep or menu command.
            return true

        case .gap:
            addGap()
            return true

        case .backspace:
            if selectedKey != nil {
                deleteSelected(.back)
                return true
            }
            guard !picks.isEmpty else { return false }
            setPicks(Array(picks.dropLast()))
            return true

        case .deleteForward:
            guard selectedKey != nil else { return false }
            deleteSelected(.forward)
            return true

        case .escape:
            guard canCancel else { return false }
            clearFocus()
            return true

        case .confirm:
            guard let target, !picks.isEmpty else { return false }
            commit(target.key, target.dir)
            return true

        case let .direction(dir):
            guard case let .place(anchor, _, picks) = interaction else { return false }
            let allowed = startableDirections(
                board: board, bounds: bounds, cell: parseKey(anchor))
            guard allowed.contains(dir) else { return false }
            lastDir = dir
            interaction = .place(anchor: anchor, dir: dir, picks: picks)
            return true
        }
    }

    /// Claim a pile tile for the current word, or release it (App.tsx:1941–1953).
    func togglePick(_ index: Int) {
        let current = picks
        if let at = current.firstIndex(of: index) {
            setPicks(current.enumerated().filter { $0.offset != at }.map(\.element))
        } else {
            setPicks(current + [index])
        }
    }

    /// Claim the first unclaimed matching pile tile (App.tsx:1955–1965).
    func typeLetter(_ letter: String) {
        let index = findAvailable(rack: rack, letter: letter, taken: Set(picks))
        guard index != -1 else { return }
        setPicks(picks + [index])
    }

    /// Stage a hole that must land on a letter already on the board.
    func addGap() {
        setPicks(picks + [GAP])
    }

    /// Remove one staged letter/gap by its position in the word
    /// (WordBar.tsx:102–119).
    func removePick(at position: Int) {
        setPicks(picks.enumerated().filter { $0.offset != position }.map(\.element))
    }

    /// Put the board back to nothing chosen (App.tsx:1296–1300).
    func clearFocus() {
        selection = nil
        highlightedWord = nil
        interaction = .idle
    }

    /// Flip the chosen cell between across and down (App.tsx:2257–2264).
    func rotateDirection() {
        guard case let .place(anchor, dir, picks) = interaction else { return }
        let next: Direction = dir == .across ? .down : .across
        lastDir = next
        interaction = .place(anchor: anchor, dir: next, picks: picks)
    }

    /// Follow the pointer, but only while a word is waiting and nothing is
    /// being dragged (App.tsx:1213–1219).
    func setHover(_ key: CellKey?) {
        let wanted = !picks.isEmpty && drag == nil ? key : nil
        if hoverCell != wanted { hoverCell = wanted }
    }

    // MARK: Taps (routed from the gesture machine)

    /// Tap an empty cell: staged letters ride along to the new anchor
    /// (App.tsx onCellClick, 2279–2306).
    func cellClick(_ key: CellKey) {
        selection = nil
        // A single letter reads the same across as down — clicking the cell
        // is the whole gesture.
        if pickList.count == 1, board[key] == nil {
            commit(key, .across)
            return
        }
        guard let dir = assumeDir(key) else {
            interaction = .idle
            return
        }
        interaction = .place(anchor: key, dir: dir, picks: picks)
    }

    /// Tap a placed tile (App.tsx selectTile, 2229–2254).
    func selectTile(_ key: CellKey) {
        if !picks.isEmpty {
            _ = commitThroughLetter(key)
            return
        }
        if !boardLocked {
            let runs = wordsByCell[key]
            let dir: Direction = runs?.contains { $0.direction == .across } == true ? .across : .down
            selection = Selection(key: key, dir: dir)
        }
        let startDir = assumeDir(key)
        interaction = startDir.map { .place(anchor: key, dir: $0, picks: []) } ?? .idle
    }

    /// Double-press on a board tile: turn the word about its first letter, or
    /// return the letter to the pile (App.tsx:2567–2584).
    func doubleTapBoardTile(_ key: CellKey) {
        let leads = (wordsByCell[key] ?? []).filter { $0.cells.first == key }
        if !leads.isEmpty {
            let word =
                leads.first { $0.direction == .across && canRotate($0) }
                ?? leads.first { canRotate($0) }
            if let word {
                rotateWord(word)
            } else {
                rejectToast("No room to turn \(leads[0].word.uppercased())")
            }
            return
        }
        returnToRack(key)
    }

    /// Place the staged word so its first gap sits on the letter at `key`
    /// (App.tsx commitThroughLetter, 2168–2217).
    @discardableResult
    func commitThroughLetter(_ key: CellKey) -> Bool {
        guard board[key] != nil else { return false }
        guard pickList.contains(where: { $0.letter == nil }) else { return false }

        let cell = parseKey(key)
        // Crossing the word the clicked letter already reads in is the
        // likelier intent, so that direction goes first.
        let runDirs = Set((wordsByCell[key] ?? []).map(\.direction))
        let ordered: [Direction] =
            runDirs.contains(.across) == runDirs.contains(.down)
            ? (lastDir == .across ? [.across, .down] : [.down, .across])
            : (runDirs.contains(.across) ? [.down, .across] : [.across, .down])

        let fits: [(anchor: Cell, dir: Direction, plan: PlacementPlan)] = ordered.compactMap { dir in
            guard
                let anchor = anchorForGapTarget(
                    board: board, bounds: bounds, target: cell, dir: dir, picks: pickList)
            else { return nil }
            let plan = planPlacement(
                board: board, bounds: bounds, anchor: anchor, dir: dir, picks: pickList)
            return plan.complete && !plan.steps.isEmpty ? (anchor, dir, plan) : nil
        }
        guard !fits.isEmpty else {
            rejectToast("That word doesn’t fit over this letter.")
            return false
        }

        // When the word fits both ways, prefer the way that spells real words.
        let best =
            fits.first { fit in
                guard let dictionary else { return false }
                var next = board
                for step in fit.plan.steps { next[step.key] = step.letter }
                var placed = Set(fit.plan.steps.map(\.key))
                placed.insert(key)
                return extractRuns(next)
                    .filter { $0.cells.contains { placed.contains($0) } }
                    .allSatisfy { $0.word.count >= MIN_WORD_LENGTH && dictionary.contains($0.word) }
            } ?? fits[0]

        commit(keyOf(best.anchor.row, best.anchor.col), best.dir)
        return true
    }

    // MARK: Commit — every landing goes through it (App.tsx:2024–2145)

    func commit(_ anchor: CellKey, _ dir: Direction, picksToPlace: [Pick]? = nil) {
        let picksToPlace = picksToPlace ?? pickList
        guard !picksToPlace.isEmpty else { return }
        let result = planPlacement(
            board: board, bounds: bounds, anchor: parseKey(anchor), dir: dir, picks: picksToPlace)
        guard !result.steps.isEmpty, result.complete else { return }

        var next = board
        for step in result.steps { next[step.key] = step.letter }
        let placed = Set(result.steps.map(\.key))
        let newRuns = extractRuns(next).filter { $0.cells.contains { placed.contains($0) } }

        // On a locked board a placement is forever, so only real words are
        // allowed down.
        if boardLocked {
            guard let dictionary else {
                rejectToast("Hold on — the dictionary is still loading.")
                return
            }
            if newRuns.isEmpty {
                rejectToast("A lone letter has to join a word.")
                return
            }
            let bad = newRuns.filter {
                $0.word.count < MIN_WORD_LENGTH || !dictionary.contains($0.word)
            }
            if !bad.isEmpty {
                let words = bad.map { $0.word.uppercased() }
                rejectToast(
                    words.count == 1
                        ? "\(words[0]) isn’t a word"
                        : "\(words.joined(separator: ", ")) aren’t words")
                return
            }
        }

        // The tutorial runs to a script, and its last step is about the gap
        // tile. The word that step asks for only counts when a gap played it —
        // typing straight over the letter on the board gets the same word by
        // the wrong road, so it's refused before anything lands
        // (App.tsx:2064–2081).
        let wanted = tutorial?.wantedWord
        let madeStepWord = wanted.map { word in newRuns.contains { $0.word == word } } ?? false
        if let tutorial, tutorial.needsGap, madeStepWord,
            !picksToPlace.contains(where: { $0.letter == nil })
        {
            rejectToast(
                "Spell \(wanted?.uppercased() ?? "") with a gap tile — press Space where the "
                    + "borrowed letter goes.")
            return
        }

        // Battle attacks join this funnel in phase 4 — it stays the one road
        // every landing takes.
        // Noted before the board changes: "place an 8-letter word" is about
        // what went down, not what survives on the board at the end.
        if picksToPlace.contains(where: { $0.letter == nil }) { usedGapTile = true }
        if let dictionary {
            let placedLengths = newRuns
                .filter { $0.word.count >= MIN_WORD_LENGTH && dictionary.contains($0.word) }
                .map(\.word.count)
            longestWordPlaced = max(longestWordPlaced, placedLengths.max() ?? 0)
        }

        // Captured before the board changes: an attack is priced against the
        // words that were already down.
        let oldRuns = mode == .battle ? extractRuns(board) : []

        remember()
        setBoard(next)
        let spent = Set(result.steps.map(\.rackIndex))
        rack = rack.enumerated().filter { !spent.contains($0.offset) }.map(\.element)
        lastDir = dir
        clearFocus()
        cues?.play(.commit)
        soundOverflow()

        // Battle: the word that just landed hits the field. Only the growth
        // counts — a word extended or bridged from words already down is
        // worth the difference, not the whole word again — and the
        // best-paying word the placement made is the one that counts
        // (App.tsx:2098–2122).
        if mode == .battle, !spectating {
            let attack = newRuns.reduce(0) { top, run in
                let cells = Set(run.cells)
                // The runs this word swallowed: same direction, every cell now
                // inside it. Anything merely crossed keeps its cells outside.
                let grewFrom = oldRuns
                    .filter { $0.direction == run.direction && $0.cells.allSatisfy(cells.contains) }
                    .map { $0.word.count }
                return max(
                    top,
                    battleAttackTiles(
                        wordLength: run.word.count, round: battleRound, grewFrom: grewFrom))
            }
            if attack > 0 {
                onBattleAttack?(attack)
                rejectToast(
                    "Sent \(attack) tile\(attack == 1 ? "" : "s") across your rivals!")
            }
        }

        // The step's word is on the board — deal the next one's tiles.
        if madeStepWord { advanceTutorial(placedDir: dir) }
    }

    // MARK: The tutorial's script (App.tsx:1990–2017, 2147–2160)

    /// Move the lesson on: call out the word that just landed and deal the
    /// next step's tiles. Every step crosses the one before it, so guessing
    /// the other way round next aims the following word right without a
    /// rotate. Returns true when the whole script is finished.
    @discardableResult
    private func advanceTutorial(placedDir: Direction) -> Bool {
        guard var run = tutorial else { return false }
        let (done, deal) = run.advance()
        tutorial = run
        lastDir = placedDir == .across ? .down : .across

        // Skipped from end to end: hand the player on rather than park them
        // on a finish button for a lesson they plainly opted out of.
        if deal == nil, run.skippedEverything {
            onTutorialWalkedOut?()
            return true
        }
        if let done { rejectToast(done) }
        guard let deal else {
            // The lesson is finished. It has no score and no summary, so it
            // never goes through `finishGame` — but it is the one thing that
            // earns the tutorial badge, so it reports through the same funnel.
            reportTutorialFinished()
            return true
        }
        appendDealtTiles(deal)
        return false
    }

    /// A completed lesson, down the one funnel every ending uses. Guarded by
    /// the same flag as `finishGame`, so walking out and back can't report it
    /// twice.
    private func reportTutorialFinished() {
        guard mode == .tutorial, tutorialFinished, !finishRecorded else { return }
        finishRecorded = true
        onFinish?(outcome)
    }

    /// Skip the step in hand: the tutorial plays the step's word itself, so
    /// the next step's instructions still describe the board in front of the
    /// player. A board with nowhere left to play that word just moves on —
    /// skipping should never be the thing that gets stuck.
    func skipTutorialStep() {
        guard var run = tutorial, let step = run.current else { return }
        run.countSkip()
        tutorial = run
        if let played = scriptedPlacement(board: board, bounds: bounds, step: step, rack: rack) {
            commit(keyOf(played.anchor.row, played.anchor.col), played.dir,
                picksToPlace: played.picks)
        } else {
            advanceTutorial(placedDir: lastDir)
        }
    }

    /// A player who skipped every step is walked out rather than parked on a
    /// finish button; the router decides where they land.
    var onTutorialWalkedOut: (() -> Void)?

    // MARK: Dragging (App.tsx:2418–2533)

    func beginDrag(_ source: GestureMachine.DragSource, at location: CGPoint) {
        let letter: String
        switch source {
        case let .rack(_, l), let .board(_, l): letter = l
        }
        hoverCell = nil
        drag = TileDrag(letter: letter, source: source, location: location)
    }

    func dragMoved(to location: CGPoint) {
        drag?.location = location
    }

    func endDrag() {
        drag = nil
    }

    enum DropRegion: Equatable {
        case cell(Cell)
        case rack
        case none
    }

    /// Apply a real drop (the machine already ruled out taps).
    func applyDrop(_ region: DropRegion) {
        guard let drag else { return }
        self.drag = nil
        let source = drag.source

        switch region {
        case let .cell(cell):
            let key = keyOf(cell.row, cell.col)
            // A drop onto a locked board goes through the same commit flow as
            // a typed word, so dictionary judging still applies.
            if boardLocked {
                if case let .rack(index, letter) = source, board[key] == nil {
                    commit(key, .across, picksToPlace: [Pick(letter: letter, rackIndex: index)])
                }
                return
            }
            let sourceKey: CellKey? = {
                if case let .board(cell, _) = source { return keyOf(cell.row, cell.col) }
                return nil
            }()
            let sameCell = sourceKey == key
            guard sameCell || board[key] == nil else { return }
            remember()
            var next = board
            if let sourceKey { next[sourceKey] = nil }
            next[key] = drag.letter
            setBoard(next)
            switch source {
            case let .rack(index, _):
                rack.remove(at: index)
                interaction = .idle
            case .board:
                // The tile moved, so the old cell is no longer what's selected.
                if selection?.key == sourceKey { selection = nil }
            }

        case .rack:
            if case let .board(cell, letter) = source {
                remember()
                var next = board
                next[keyOf(cell.row, cell.col)] = nil
                setBoard(next)
                rack.append(letter)
                if selection?.key == keyOf(cell.row, cell.col) { selection = nil }
            }

        case .none:
            break
        }
    }

    /// The hold fired: a held anchor lets the preview follow the finger again
    /// (App.tsx:2645–2652).
    func beginPreviewDrag() {
        if case let .place(_, _, picks) = interaction {
            interaction = picks.isEmpty ? .idle : .spell(picks: picks)
        }
    }

    // MARK: Board words (App.tsx:1766–1852)

    func canRotate(_ word: WordRun) -> Bool {
        planWordCells(
            board: board, bounds: bounds, length: word.cells.count, own: word.cells,
            dir: word.direction == .across ? .down : .across, start: parseKey(word.cells[0]))
            != nil
    }

    /// Move a word's tiles so its first letter lands on `start`.
    @discardableResult
    func moveWord(_ word: WordRun, to start: CellKey, dir: Direction) -> Bool {
        guard !boardLocked else { return false }
        guard
            let targets = planWordCells(
                board: board, bounds: bounds, length: word.cells.count, own: word.cells,
                dir: dir, start: parseKey(start))
        else { return false }
        let letters = word.cells.compactMap { board[$0] }
        guard letters.count == word.cells.count else { return false }
        remember()
        selection = nil
        highlightedWord = nil
        var next = board
        for key in word.cells { next[key] = nil }
        for (i, key) in targets.enumerated() { next[key] = letters[i] }
        setBoard(next)
        return true
    }

    /// Turn a word about its first letter, which stays put.
    func rotateWord(_ word: WordRun) {
        let pivot = word.cells[0]
        let dir: Direction = word.direction == .across ? .down : .across
        guard moveWord(word, to: pivot, dir: dir) else { return }
        selection = Selection(key: pivot, dir: dir)
    }

    /// Send the tile back to the pile (App.tsx returnToRack, 2535–2549).
    func returnToRack(_ key: CellKey) {
        guard !boardLocked else { return }
        guard let letter = board[key] else { return }
        remember()
        var next = board
        next[key] = nil
        setBoard(next)
        rack.append(letter)
        if selection?.key == key { selection = nil }
    }

    /// Return every tile in a run to the pile (WordControls.tsx remove).
    func removeWord(_ word: WordRun) {
        guard !boardLocked else { return }
        let letters = word.cells.compactMap { board[$0] }
        guard letters.count == word.cells.count else { return }
        remember()
        var next = board
        for key in word.cells { next[key] = nil }
        setBoard(next)
        rack.append(contentsOf: letters)
        clearFocus()
    }

    enum DeleteStep { case back, forward }

    /// Remove the selected tile and step along its word, so key repeat eats a
    /// run backward (Backspace) or forward (Delete), App.tsx:1898–1932.
    func deleteSelected(_ step: DeleteStep) {
        guard !boardLocked, let selection else { return }
        let key = selection.key
        guard let letter = board[key] else {
            self.selection = nil
            return
        }
        let cell = parseKey(key)
        let delta = step == .back ? -1 : 1
        let nextKey = selection.dir == .across
            ? keyOf(cell.row, cell.col + delta)
            : keyOf(cell.row + delta, cell.col)

        remember()
        var next = board
        next[key] = nil
        setBoard(next)
        rack.append(letter)
        self.selection = board[nextKey] == nil ? nil : Selection(key: nextKey, dir: selection.dir)
    }

    func setHighlightedWord(_ word: WordRun?) {
        highlightedWord = word
    }

    // MARK: Whole-word dragging (WordControls.tsx grab)

    func beginWordDrag(_ word: WordRun, at location: CGPoint) {
        guard !boardLocked else { return }
        let letters = word.cells.compactMap { board[$0] }
        guard letters.count == word.cells.count else { return }
        highlightedWord = nil
        wordDrag = WordDrag(word: word, letters: letters, location: location)
    }

    func wordDragMoved(to location: CGPoint) {
        wordDrag?.location = location
    }

    func endWordDrag(at cell: Cell?) {
        guard let wordDrag else { return }
        self.wordDrag = nil
        guard let cell else { return }
        _ = moveWord(wordDrag.word, to: keyOf(cell.row, cell.col), dir: wordDrag.word.direction)
    }

    func cancelWordDrag() {
        wordDrag = nil
    }

    // MARK: Undo / redo (App.tsx:935–998)

    func undo() {
        guard !boardLocked, let previous = history.popLast() else { return }
        future.append(snapshot())
        restore(previous)
    }

    func redo() {
        guard !boardLocked, let next = future.popLast() else { return }
        history.append(snapshot())
        if history.count > Self.undoDepth { history.removeFirst() }
        restore(next)
    }

    /// Reshuffle the pile and drop the staged word (App.tsx:2602–2605).
    func shufflePile() {
        rack.shuffle()
        interaction = .idle
    }

    /// A refusal that changes nothing on screen reads as a bug, so it always
    /// gets a banner (App.tsx rejectToast, 1979–1981).
    func rejectToast(_ text: String) {
        toastSerial += 1
        toast = GameToast(text: text, serial: toastSerial)
    }

    /// Say so when a game earns something. The toast is the game's only
    /// "well done" channel, and it's the right one here: Game Center's own
    /// achievement banner needs an account, and this has to work without one.
    func announceAchievements(_ ids: [AchievementID]) {
        guard let first = ids.first else { return }
        rejectToast(
            ids.count == 1
                ? "Achievement: \(first.title)"
                : "Achievement: \(first.title) +\(ids.count - 1) more")
    }

    func clearToast(serial: Int) {
        if toast?.serial == serial { toast = nil }
    }

    // MARK: Solo deals

    /// Grow a guaranteed-playable batch off the board and append it to every
    /// remembered pile. Clock deals must survive undo/redo of unrelated moves.
    private func dealBonusTiles(_ count: Int, message: String?) {
        guard count > 0 else { return }
        let rng = seededRng("\(seed)/solo/\(dealSerial)")
        dealSerial += 1
        guard
            let deal = try? extendPuzzle(
                board: board, bounds: bounds, wordPool: commonWords,
                tileCount: count, rng: rng)
        else {
            rejectToast("Couldn’t deal the next tiles.")
            return
        }

        appendDealtTiles(deal.letters)
        if let message { rejectToast(message) }
    }

    /// Tiles arriving from anywhere the player didn't put them: a clock drip,
    /// a board clear, the next tutorial step. They join every remembered pile
    /// too — undoing a move must take back the move alone, never disappear
    /// tiles that were dealt (App.tsx:1451–1459).
    private func appendDealtTiles(_ letters: [String]) {
        guard !letters.isEmpty else { return }
        rack.append(contentsOf: letters)
        for index in history.indices {
            history[index].rack.append(contentsOf: letters)
        }
        for index in future.indices {
            future[index].rack.append(contentsOf: letters)
        }
        cues?.play(.deal)
        soundOverflow()
    }

    // MARK: Surviving process death (plan §6.1)

    /// The in-progress game as a serializable blob, or nil when there's
    /// nothing worth restoring (a finished game, an untouched opening board,
    /// or the tutorial — which is a lesson, not a run to lose).
    func savedGame(at now: Date = .now) -> SavedSoloGame? {
        guard mode == .endless || mode == .daily, !isComplete else { return nil }
        // A daily is worth saving from the moment it's dealt: it's one attempt
        // a day, so losing an untouched board to a phone call would cost the
        // player the whole day.
        guard mode == .daily || !board.isEmpty || bankedBonus > 0 || phase == .drip else {
            return nil
        }
        return SavedSoloGame(
            seed: seed,
            mode: mode.rawValue,
            dailyDay: daily?.day,
            pace: pace.rawValue,
            board: board,
            rack: rack,
            phase: phase == .drip ? "drip" : "initial",
            dripsElapsed: dripsElapsed,
            bankedBonus: bankedBonus,
            remainingSeconds: solo.remaining(at: now),
            dealSerial: dealSerial,
            savedAt: now.timeIntervalSince1970)
    }

    /// Put a saved game back on the board. The clock comes back **held**, like
    /// any board behind a readable overlay, and starts when the player
    /// dismisses the resume card — a game must never lose seconds to being
    /// away, nor resume already expired.
    func restore(_ saved: SavedSoloGame, now: Date = .now) {
        seed = saved.seed
        mode = saved.gameMode
        tutorial = nil
        daily = saved.deal
        // A daily has no clock to come back held, so it comes back straight
        // onto the board — there is nothing a resume card would be holding.
        solo = mode == .daily
            ? SoloSession(dailyAt: now)
            : SoloSession(
                restoring: saved.soloPace,
                phase: saved.soloPhase,
                dripsElapsed: saved.dripsElapsed,
                remaining: saved.remainingSeconds)
        gameSerial += 1
        setBoard(saved.board)
        rack = saved.rack
        resetPlayState()
        bankedBonus = saved.bankedBonus
        dealSerial = saved.dealSerial
    }

    private func clearTransientInput() {
        drag = nil
        wordDrag = nil
        hoverCell = nil
        highlightedWord = nil
    }

    // MARK: Board mutation

    private func setBoard(_ next: TileMap) {
        board = next
        refreshBoardCaches()
    }

    private func refreshBoardCaches() {
        bounds = boardBounds(board)
        tileBounds = tileBox(of: board)
        validation = dictionary.map { validateBoard(board, dictionary: $0) }

        var byCell: [CellKey: [WordRun]] = [:]
        for run in extractRuns(board) where run.cells.count > 1 {
            for cell in run.cells { byCell[cell, default: []].append(run) }
        }
        wordsByCell = byCell

        // Worst problem wins: invalid > isolated > disconnected > valid
        // (App.tsx:1140–1152).
        var feedback: [CellKey: CellFeedback] = [:]
        if let validation {
            for key in validation.disconnectedTiles { feedback[key] = .disconnected }
            for run in validation.runs {
                for cell in run.cells {
                    if !run.valid {
                        feedback[cell] = .invalid
                    } else if feedback[cell] == nil {
                        feedback[cell] = .valid
                    }
                }
            }
            for key in validation.isolatedTiles { feedback[key] = .isolated }
        }
        cellFeedback = feedback
    }

    private func snapshot() -> GameSnapshot {
        GameSnapshot(board: board, rack: rack, picks: picks)
    }

    /// Remember before a move. A fresh move forks the timeline, exactly like
    /// the web; battles never record because their placed tiles are permanent.
    private func remember() {
        guard !boardLocked else { return }
        history.append(snapshot())
        if history.count > Self.undoDepth { history.removeFirst() }
        future = []
    }

    /// Undo restores staged picks as a loose spell: the move came off its old
    /// cell, so its preview must not remain anchored there.
    private func restore(_ snapshot: GameSnapshot) {
        board = snapshot.board
        rack = snapshot.rack
        interaction = snapshot.picks.isEmpty ? .idle : .spell(picks: snapshot.picks)
        selection = nil
        highlightedWord = nil
        drag = nil
        wordDrag = nil
        hoverCell = nil
        refreshBoardCaches()
    }
}
