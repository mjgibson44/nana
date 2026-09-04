import Foundation
import Observation
import WordBoard
import WordCore

/// The pile's hard limit, the same in Solo and Battle: the moment it holds
/// this many tiles the game is over. It is also the pile's size on screen —
/// three rows of ten — so a full pile *looks* like the end.
let PILE_LIMIT = 30

/// Where the gauge turns amber: past Solo's opening twenty, so a fresh deal
/// reads as room to work rather than as trouble.
let PILE_WARN = 21

/// …and where it turns red: one more Solo batch could end the game.
let PILE_URGENT = 25

/// The single toast slot, keyed by serial so repeats replay (App.tsx:415).
struct GameToast: Equatable {
    var text: String
    var serial: Int
}

/// Keyboard vocabulary kept independent of SwiftUI's `KeyPress`, so the
/// hardware-keyboard behavior is unit-testable.
enum GameCommand: Equatable {
    case letter(String)
    case gap
    case backspace
    case escape
    case confirm
}

struct ScoredWord: Equatable {
    var word: String
    var points: Int
}

/// How full the pile is, for the gauge and the alarm.
enum PileTone: Equatable {
    case ok
    case warn
    case urgent
}

/// A finished game, frozen — what the stats funnel and Game Center are
/// handed. Carrying the whole report rather than just a score is what lets
/// one funnel serve Solo and Battle.
struct GameOutcome: Equatable {
    /// What the game saw, in the shape the achievement evaluator wants.
    var report: GameReport
    var words: Int
    var tilesLeft: Int
    var bonusEarned: Bool
    /// No mode deals one any more; kept so the progression funnel and its
    /// leaderboard queue stay whole (`Progression` reads it).
    var daily: DailyDeal? = nil

    var mode: GameMode { report.mode }
    var score: Int { report.score }
}

/// How many seconds before the tiles land the clock ticks. Three beats is
/// long enough to be a warning and short enough not to be a metronome.
let ENDLESS_TICK_FROM = 3

/// The game's interaction model, after the redesign.
///
/// There is one way to build a word and two ways to land it:
///
///  - **Building.** Pick letters from the pile (tap, or type on a hardware
///    keyboard); they line up in the word row in the order picked. A gap tile
///    stands for a letter already on the board.
///  - **The first word** lands from the start square heading across, with the
///    confirm button. It is the only word that's placed by fiat.
///  - **Every word after it** has to borrow a letter that's already down: put
///    a gap where the borrowed letter goes and tap that letter on the board.
///    The word arranges itself around it, across or down, whichever spells
///    real words.
///
/// Placed words are permanent. Nothing can be moved, turned, deleted or undone,
/// so only real words are allowed down — in every mode, not just Battle.
/// And the pile is the only pressure: let it reach `PILE_LIMIT` and you're
/// out, on the spot.
@Observable @MainActor
final class GameModel {
    private(set) var board = TileMap()
    private(set) var rack: [String] = []
    /// Pile indices claimed for the word, in picked order; `GAP` for a gap.
    private(set) var picks: [Int] = []
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
    /// Bumped per deal so the viewport knows to go home.
    private(set) var gameSerial = 0

    /// Which mode is being played: Solo (`endless`) or Battle.
    private(set) var mode: GameMode = .endless

    /// The battle's clock and deal position, while `mode == .battle`.
    private(set) var battle: BattleRun?
    /// Which round the battle is in, refreshed by the clock tick. Held rather
    /// than computed so `commit` — which has no clock of its own — values a
    /// word by the round it actually landed in.
    private(set) var battleRound = 1
    /// Watching rather than playing: buried already, or joined mid-game and
    /// waiting for the next start. A dead board takes no drips and can't be
    /// buried twice.
    var spectating = false
    /// The shared deal. Every player's stream is seeded identically, so drip
    /// *k* is the same letters on every screen.
    private var battleStream: TileStream?
    /// This player's private attack stream, seeded `<seed>/attacks/<selfID>`.
    /// Only counts cross the wire; the letters are drawn locally.
    private var attackStream: TileStream?
    /// Filled in by the session when the battle is decided.
    private(set) var battleWon = false
    private(set) var battlePlayerCount = 0
    private(set) var attackTilesSent = 0

    /// A word landed and owes the field tiles. The session splits and sends it.
    var onBattleAttack: ((Int) -> Void)?

    /// Who sounds the game's cues (audio + haptics). Optional so tests and
    /// previews stay silent, and so the model never imports AVFoundation.
    var cues: GameCueSink?

    /// The last tick sounded, keyed by round deadline and second so the 4Hz
    /// heartbeat plays each of the last three beats exactly once.
    private var tickedKey: String?
    /// Whether the pile is in the red. Dropping back out re-arms the alarm,
    /// so a player riding the limit is warned every time they near it.
    private var inTheRed = false

    // Recomputed once per board change rather than per render.
    private(set) var bounds = boardBounds(TileMap())
    private(set) var validation: BoardValidation?
    private(set) var wordsByCell: [CellKey: [WordRun]] = [:]
    private(set) var tileBounds: Bounds?

    // What this game has seen, for the achievement evaluator (plan §8.3).
    private(set) var usedGapTile = false
    private(set) var longestWordPlaced = 0
    private(set) var boardClears = 0
    private(set) var recoveredFromOverLimit = false

    private var toastSerial = 0
    private var dealSerial = 0
    private var finishRecorded = false

    /// The square the first word starts from, heading across. The camera
    /// parks it two cells in from the left edge so a long opener fits.
    static let startCell = Cell(row: BOARD_SIZE / 2, col: BOARD_SIZE / 2)
    static var startKey: CellKey { keyOf(startCell.row, startCell.col) }

    // MARK: Derived word-building state

    var pickList: [Pick] {
        picks
            .filter { $0 == GAP || rack.indices.contains($0) }
            .map { $0 == GAP ? Pick(letter: nil, rackIndex: GAP) : Pick(letter: rack[$0], rackIndex: $0) }
    }

    /// Whether the staged word borrows a letter from the board.
    var hasGap: Bool { picks.contains(GAP) }

    /// The board is empty: the word in hand is the opener.
    var isFirstWord: Bool { board.isEmpty }

    /// Where the opener would land, laid out from the start square. Nil once
    /// anything is on the board — later words have no home until a letter is
    /// tapped.
    var plan: PlacementPlan? {
        guard isFirstWord, !pickList.isEmpty else { return nil }
        return planPlacement(
            board: board, bounds: bounds, anchor: Self.startCell, dir: .across, picks: pickList)
    }

    /// Ghost letters on the board: the opener, previewing as it's typed.
    var preview: [CellKey: String] {
        guard let plan else { return [:] }
        return Dictionary(uniqueKeysWithValues: plan.steps.map { ($0.key, $0.letter) })
    }

    /// Live dictionary check on the opener. Later words can't be judged
    /// until they're aimed at a letter, and are judged then.
    var verdictOK: Bool? {
        guard let dictionary, let plan, plan.complete else { return nil }
        var next = board
        for step in plan.steps { next[step.key] = step.letter }
        let placed = Set(plan.steps.map(\.key))
        let runs = extractRuns(next).filter { $0.cells.contains { placed.contains($0) } }
        if runs.isEmpty { return nil }
        return runs.allSatisfy { $0.word.count >= MIN_WORD_LENGTH && dictionary.contains($0.word) }
    }

    /// The confirm button only exists for the opener, and only lights up for
    /// a real word.
    var canConfirm: Bool {
        guard isFirstWord, let plan else { return false }
        return plan.complete && !plan.steps.isEmpty && verdictOK == true
    }

    var canClearWord: Bool { !picks.isEmpty }
    var canBackspace: Bool { !picks.isEmpty }
    var canShuffle: Bool { rack.count > 1 }
    /// A gap borrows from the board, so it means nothing until there's a
    /// board to borrow from.
    var canAddGap: Bool { !isFirstWord }

    // MARK: Derived session state

    var pace: SoloPace { solo.pace }
    var phase: SoloPhase { solo.phase }
    var dripsElapsed: Int { solo.dripsElapsed }
    var countdown: SoloCountdown? { solo.countdown }
    var isPaused: Bool { solo.paused }
    var splash: SoloSplash? { solo.splash }
    var isComplete: Bool { solo.complete }
    var endReason: SoloEndReason? { solo.endReason }

    /// Overlays own input while visible. A finished board remains viewable
    /// but cannot be changed after the summary is dismissed.
    var canAcceptInput: Bool {
        !isComplete && !isPaused && splash == nil && !showSummary && !spectating
    }

    var canPause: Bool { mode == .endless && !isComplete && !isPaused && splash == nil }

    var boardScore: BoardScore {
        scoreBoard(validation, tilesLeft: rack.count)
    }

    /// Word points stay live; only the 25-point board-clear awards are banked.
    var runningScore: Int {
        bankedBonus + boardScore.words
            + (boardScore.bonusEarned ? ENDLESS_CONNECT_BONUS : 0)
    }

    var score: Int { isComplete ? finalScore : runningScore }

    var isBattle: Bool { mode == .battle }

    /// How many tiles are in hand — the gauge, and the only thing that can
    /// end a game.
    var pileCount: Int { rack.count }

    var pileTone: PileTone {
        if rack.count >= PILE_URGENT { return .urgent }
        if rack.count >= PILE_WARN { return .warn }
        return .ok
    }

    var boardClearReady: Bool {
        !isComplete && boardScore.bonusEarned
    }

    /// Seconds until the next batch lands, whichever clock is running.
    func secondsToNextTiles(at now: Date) -> Int? {
        if let battle {
            return isComplete ? nil : battle.secondsToNextDrip(at: now)
        }
        return solo.remaining(at: now).map { Int(ceil($0)) }
    }

    func remainingSeconds(at now: Date) -> Int? {
        solo.remaining(at: now).map { Int(ceil($0)) }
    }

    // MARK: Game lifecycle

    func newGame(
        seed: String = randomSeed(), pace: SoloPace = .regular, now: Date = .now
    ) {
        self.seed = seed
        mode = .endless
        clearBattle()
        solo = SoloSession(pace: pace, now: now)
        gameSerial += 1
        setBoard(TileMap())
        let puzzle = try? generatePuzzle(
            wordPool: commonWords, tileCount: ENDLESS_START_TILES, rng: seededRng(seed))
        rack = puzzle?.letters ?? []
        resetPlayState()
    }

    /// The host said go. Grow the shared deal from the seed and dive in. The
    /// opening batch is `BATTLE_START_TILES` for everyone, which is what keeps
    /// the shared stream in step — every client asks the stream for the same
    /// first number.
    func newBattle(
        seed: String, selfID: String, spectating: Bool = false, now: Date = .now
    ) {
        self.seed = seed
        mode = .battle
        self.spectating = spectating
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
    /// letters come off this player's private stream.
    func receiveAttack(_ count: Int) {
        guard mode == .battle, !isComplete, !spectating, count > 0,
            let attackStream
        else { return }
        let letters = attackStream.next(count)
        guard !letters.isEmpty else { return }
        // Sent tiles get their own voice — lower and falling, so incoming
        // trouble never sounds like tiles you earned.
        cues?.play(.attack)
        rejectToast(
            "Incoming! +\(letters.count) tile\(letters.count == 1 ? "" : "s") from a rival")
        appendDealtTiles(letters, cue: nil)
    }

    /// The battle is decided. A player still standing is finished here —
    /// as the winner, or as the loser of a draw — and a player already buried
    /// just learns how big the field was.
    func finishBattle(won: Bool, players: Int) {
        guard mode == .battle else { return }
        battlePlayerCount = players
        guard !isComplete else {
            showSummary = true
            return
        }
        battleWon = won
        finishGame(reason: .battleOver)
    }

    /// Leave battle behind — Solo deals its own way.
    private func clearBattle() {
        battle = nil
        battleStream = nil
        attackStream = nil
        battleRound = 1
        spectating = false
        battleWon = false
        battlePlayerCount = 0
        attackTilesSent = 0
    }

    /// Everything a fresh board resets, whatever dealt it.
    private func resetPlayState() {
        picks = []
        toast = nil
        bankedBonus = 0
        finalScore = 0
        finalTilesLeft = 0
        finalBonusEarned = false
        finalWords = []
        showSummary = false
        dealSerial = 0
        finishRecorded = false
        tickedKey = nil
        inTheRed = false
        usedGapTile = false
        longestWordPlaced = 0
        boardClears = 0
        recoveredFromOverLimit = false
    }

    func dismissSplash(at now: Date = .now) {
        solo.dismissSplash(at: now)
    }

    func pause(at now: Date = .now) {
        guard canPause else { return }
        solo.pause(at: now)
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
        if let tiles = solo.advance(at: now) {
            dealBonusTiles(tiles, message: "+\(tiles) tile\(tiles == 1 ? "" : "s")")
        }
        soundTick(at: now)
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
            rejectToast("+\(letters.count) tile\(letters.count == 1 ? "" : "s")")
            battle = run
            appendDealtTiles(letters)
            return
        }
        battle = run
    }

    /// The last few seconds before a batch tick, once a second, so the tiles
    /// about to land are heard coming. Keyed by deadline and second: the
    /// heartbeat runs at 4Hz, and a held clock is silent because a paused
    /// countdown reports no deadline.
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

    /// Entering the red sounds the alarm — a warning, not a verdict: the
    /// game ends only when the pile is actually full. Digging back out
    /// re-arms it, and is the comeback the badge is for.
    private func soundPileAlarm() {
        guard !isComplete else {
            inTheRed = false
            return
        }
        let red = pileTone == .urgent
        guard red != inTheRed else { return }
        if inTheRed, !red { recoveredFromOverLimit = true }
        inTheRed = red
        if red { cues?.play(.overflow) }
    }

    /// One rule, every mode: a full pile ends the game on the spot.
    private func checkBurial() {
        guard !isComplete, !spectating, rack.count >= PILE_LIMIT else { return }
        finishGame(reason: .buried)
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
        picks = []
        switch reason {
        case .buried:
            cues?.play(.lose)
        case .battleOver:
            cues?.play(battleWon ? .win : .lose)
        }
        // One funnel for every ending, so stats are recorded exactly once.
        onFinish?(outcome)
    }

    /// Everything a finished game is worth knowing about, frozen.
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
                battleWon: battleWon,
                battlePlayers: battlePlayerCount,
                battleReachedFinalRound: mode == .battle && battleRound >= BATTLE_ROUNDS,
                attackTilesSent: attackTilesSent),
            words: finalWords.count,
            tilesLeft: finalTilesLeft,
            bonusEarned: finalBonusEarned)
    }

    /// Called once per finished game — the single stats/leaderboard funnel
    /// every game end flows through.
    var onFinish: ((GameOutcome) -> Void)?

    func loadDictionary() async {
        guard dictionary == nil, let parsed = await WordDictionary.shared() else { return }
        dictionary = parsed
        refreshBoardCaches()
    }

    // MARK: Building the word

    /// The hardware-keyboard contract. `true` means the app consumed the key;
    /// callers return `.handled` so focus traversal and system beeps stay out.
    @discardableResult
    func handle(_ command: GameCommand) -> Bool {
        switch command {
        case let .letter(letter):
            guard letter.count == 1, letter.first?.isLetter == true else { return false }
            typeLetter(letter)
            // An unavailable letter is a quiet no-op, never a system beep.
            return true

        case .gap:
            addGap()
            return true

        case .backspace:
            guard !picks.isEmpty else { return false }
            picks.removeLast()
            return true

        case .escape:
            guard canClearWord else { return false }
            clearWord()
            return true

        case .confirm:
            guard canConfirm else { return false }
            confirmFirstWord()
            return true
        }
    }

    /// Claim a pile tile for the word, or release it.
    func togglePick(_ index: Int) {
        guard rack.indices.contains(index) else { return }
        if let at = picks.firstIndex(of: index) {
            picks.remove(at: at)
        } else {
            picks.append(index)
        }
    }

    /// Claim the first unclaimed matching pile tile.
    func typeLetter(_ letter: String) {
        let index = findAvailable(rack: rack, letter: letter, taken: Set(picks))
        guard index != -1 else { return }
        picks.append(index)
    }

    /// Stage a hole that will land on a letter already on the board.
    func addGap() {
        guard canAddGap else {
            rejectToast("Place your first word before borrowing a letter.")
            return
        }
        picks.append(GAP)
    }

    /// Remove one staged letter or gap by its position in the word.
    func removePick(at position: Int) {
        guard picks.indices.contains(position) else { return }
        picks.remove(at: position)
    }

    /// The trash button: put every picked tile back.
    func clearWord() {
        picks = []
    }

    /// Reshuffle the pile. The word in hand survives: it's re-found in the
    /// shuffled pile, so shuffling to see the letters differently never costs
    /// a half-typed word.
    func shufflePile() {
        let staged = pickList
        rack.shuffle()
        var taken = Set<Int>()
        var next: [Int] = []
        for pick in staged {
            guard let letter = pick.letter else {
                next.append(GAP)
                continue
            }
            let index = findAvailable(rack: rack, letter: letter, taken: taken)
            guard index != -1 else { continue }
            taken.insert(index)
            next.append(index)
        }
        picks = next
    }

    // MARK: Landing the word

    /// The opener: from the start square, heading across.
    func confirmFirstWord() {
        guard canConfirm else { return }
        commit(Self.startKey, .across)
    }

    /// Tap a placed letter: the staged word lands with its gap on it. A word
    /// with no gap has nowhere to borrow from, and says so rather than doing
    /// nothing (App.tsx selectTile).
    func selectTile(_ key: CellKey) {
        guard let letter = board[key] else { return }
        guard !picks.isEmpty else { return }
        guard hasGap else {
            rejectToast("Put a gap in your word where the \(letter.uppercased()) goes.")
            return
        }
        commitThroughLetter(key)
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
            ? [.across, .down]
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

        return commit(keyOf(best.anchor.row, best.anchor.col), best.dir)
    }

    // MARK: Commit — every landing goes through it (App.tsx:2024–2145)

    /// Land the staged word from `anchor` heading `dir`. Words are permanent,
    /// so only real ones are allowed down: every run the placement makes or
    /// changes has to be in the dictionary.
    @discardableResult
    func commit(_ anchor: CellKey, _ dir: Direction, picksToPlace: [Pick]? = nil) -> Bool {
        let picksToPlace = picksToPlace ?? pickList
        guard !picksToPlace.isEmpty else { return false }
        let result = planPlacement(
            board: board, bounds: bounds, anchor: parseKey(anchor), dir: dir, picks: picksToPlace)
        guard !result.steps.isEmpty, result.complete else { return false }

        var next = board
        for step in result.steps { next[step.key] = step.letter }
        let placed = Set(result.steps.map(\.key))
        let newRuns = extractRuns(next).filter { $0.cells.contains { placed.contains($0) } }

        guard let dictionary else {
            rejectToast("Hold on — the dictionary is still loading.")
            return false
        }
        if newRuns.isEmpty {
            rejectToast("A lone letter has to join a word.")
            return false
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
            return false
        }

        // Noted before the board changes: "place an 8-letter word" is about
        // what went down, not what survives on the board at the end.
        if picksToPlace.contains(where: { $0.letter == nil }) { usedGapTile = true }
        longestWordPlaced = max(longestWordPlaced, newRuns.map(\.word.count).max() ?? 0)

        // Captured before the board changes: an attack is priced against the
        // words that were already down.
        let oldRuns = mode == .battle ? extractRuns(board) : []

        setBoard(next)
        let spent = Set(result.steps.map(\.rackIndex))
        rack = rack.enumerated().filter { !spent.contains($0.offset) }.map(\.element)
        picks = []
        cues?.play(.commit)
        soundPileAlarm()

        // Battle: the word that just landed hits the field. Only the growth
        // counts — a word extended or bridged from words already down is
        // worth the difference, not the whole word again — and the
        // best-paying word the placement made is the one that counts.
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
                attackTilesSent += attack
                onBattleAttack?(attack)
                rejectToast(
                    "Sent \(attack) tile\(attack == 1 ? "" : "s") across your rivals!")
            }
        }
        return true
    }

    // MARK: Toasts

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

    // MARK: Deals

    /// Grow a guaranteed-playable batch off the board and add it to the pile.
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
        if let message { rejectToast(message) }
        appendDealtTiles(deal.letters)
    }

    /// Tiles arriving from anywhere the player didn't put them: a clock drip,
    /// a board clear, a rival's attack. The pile is the only thing that can
    /// end a game, so every arrival is where that's checked.
    private func appendDealtTiles(_ letters: [String], cue: GameSound? = .deal) {
        guard !letters.isEmpty else { return }
        rack.append(contentsOf: letters)
        if let cue { cues?.play(cue) }
        soundPileAlarm()
        checkBurial()
    }

    // MARK: Surviving process death (plan §6.1)

    /// The in-progress Solo game as a serializable blob, or nil when there's
    /// nothing worth restoring (a finished game, an untouched opening board,
    /// or a battle — which is host-driven).
    func savedGame(at now: Date = .now) -> SavedSoloGame? {
        guard mode == .endless, !isComplete else { return nil }
        guard !board.isEmpty || bankedBonus > 0 || phase == .drip else { return nil }
        return SavedSoloGame(
            seed: seed,
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
        mode = .endless
        clearBattle()
        solo = SoloSession(
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
        inTheRed = pileTone == .urgent
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
    }
}
