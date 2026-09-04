import Foundation
import Observation
import WordBoard
import WordCore

/// The pile's hard limit, the same in Solo and Battle: the moment it holds
/// this many tiles the game is over. It is also the pile's size on screen —
/// three rows of eight — so a full pile *looks* like the end.
let PILE_LIMIT = 24

/// Tiles in the opening Solo deal, and in the opening Battle deal.
///
/// The app's own numbers rather than `WordCore.ENDLESS_START_TILES` and
/// `BATTLE_START_TILES`, which are the web game's and are held byte-identical
/// to it by the parity fixtures. The phone's pile is smaller, so its opening
/// hands are too — each keeps exactly the share of the pile it had before
/// (Solo two thirds, Battle a half), so both modes open with the same room to
/// work in that they had at thirty.
let SOLO_START_TILES = 16
let BATTLE_OPENING_TILES = 12

/// Where the gauge turns amber: past Solo's opening deal, so a fresh hand
/// reads as room to work rather than as trouble.
let PILE_WARN = 17

/// …and where it turns red: one more Solo batch could end the game.
let PILE_URGENT = 20

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

/// What the word row says about the word in hand, before anything is aimed
/// or landed. The answer a player would otherwise only get by trying it.
enum WordVerdict: Equatable {
    /// Nothing to say yet: no letters, no dictionary, or too few letters to
    /// be a word at all.
    case unjudged
    /// It reads, and there is somewhere it could go.
    case good
    /// It isn't a word — or, with a gap in it, there is no letter on the
    /// board it could borrow that would make it one.
    case bad
}

/// The staged word, held over a board letter and not yet let go of: where
/// every one of its letters would land, and whether that spells real words.
///
/// This is what press-and-hold shows. It is deliberately *not* a commit —
/// aiming can wander from letter to letter without anything landing, and a
/// word that doesn't read stays visible in red long enough to be read before
/// it is taken back.
struct AimPreview: Equatable {
    /// The board letter the gap is sitting on.
    var through: CellKey
    /// Every cell the word would occupy, borrowed letter included, so the
    /// whole word lights up as one thing.
    var cells: [CellKey: String]
    /// The words this placement would make or change that aren't in the
    /// dictionary. Empty means it's good to land.
    var badWords: [String]
    /// Bumped when a rejected aim is put up, so its red second is timed once.
    var serial = 0

    var isGood: Bool { badWords.isEmpty }
}

/// A finished game, frozen — what the stats funnel and Game Center are
/// handed. Carrying the whole report rather than just a score is what lets
/// one funnel serve Solo and Battle.
struct GameOutcome: Equatable {
    /// What the game saw.
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

/// Occupy's side of the model: whose seat this is, the host's board, and the
/// words let go of that the host hasn't answered for yet.
///
/// The board a player looks at is the host's latest snapshot with their own
/// unanswered words laid over it (`view`), so a word appears the moment it's
/// let go of — and is taken back, tiles and all, if the host says someone got
/// there first. The rules that lay it over are the host's own (`occupyApply`),
/// so the two can only disagree about a square someone else reached first.
struct OccupyRun: Equatable {
    var seed: String
    var selfID: String
    var seat: Int?
    /// The host's latest word on the board.
    var host: OccupyState?
    /// What's drawn: `host` with `pending` laid over it.
    var view: OccupyState?
    /// When the deal arrived here, for the match clock.
    var startedAt: Date
    /// When the board last changed here, for the stall countdown.
    var lastChangeAt: Date
    var serial = 0
    var refillSerial = 0
    var pending: [PendingPlacement] = []

    var players: Int { host?.seats.count ?? OCCUPY_MIN_PLAYERS }
}

/// A word let go of, and everything needed to take it back.
struct PendingPlacement: Equatable {
    var serial: Int
    var placement: OccupyPlacement
    /// The letters it took from the pile, and the ones dealt in their place.
    var spent: [String]
    var refill: [String]
    /// The word as it was typed — gaps nil — to put back in the row.
    var typed: [String?]
}

/// How long a word that doesn't read stays on the board in red before it's
/// taken back. Long enough to read what you spelled — which is the whole
/// point of showing it — and short enough not to be a punishment.
let REJECTED_AIM_SECONDS = 1.0

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
    private(set) var picks: [Int] = [] {
        didSet { judgeWord() }
    }
    /// Whether the word in hand reads — recomputed whenever the word or the
    /// board changes, rather than per render: judging a gapped word means
    /// trying it against every letter on the board, which is far too much to
    /// do four times a second behind the clock.
    private(set) var wordVerdict: WordVerdict = .unjudged
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

    /// Which mode is being played: Solo (`endless`), Battle, or Occupy.
    private(set) var mode: GameMode = .endless

    /// Occupy's shared board and seat, while `mode == .occupy`.
    private(set) var occupy: OccupyRun?
    /// Which seat owns each tile on the board, in Occupy. Empty otherwise.
    private(set) var owners: [CellKey: Int] = [:]
    /// The words this player put down in an Occupy game, each worth what it
    /// gained — the results screen's list.
    private(set) var occupyWords: [ScoredWord] = []
    /// A fixed board, for the modes that have one; nil lets the board grow.
    private var fixedBounds: Bounds?

    /// A word let go of in Occupy, for the session to send the host.
    var onOccupyPlace: ((Int, OccupyPlacement) -> Void)?

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

    // What this game has seen, for the record a finished game reports.
    private(set) var usedGapTile = false
    private(set) var longestWordPlaced = 0
    private(set) var boardClears = 0
    private(set) var recoveredFromOverLimit = false

    /// The word being aimed through a board letter by press-and-hold, or the
    /// red one being held up for a second before it's taken back.
    private(set) var aim: AimPreview?
    /// Set while a refused aim is showing in red; the view times it out.
    private(set) var aimRejected = false

    private var toastSerial = 0
    private var aimSerial = 0
    private var dealSerial = 0
    private var finishRecorded = false

    /// The square the first word starts from, heading across. The camera
    /// parks it two cells in from the left edge so a long opener fits.
    static let startCell = Cell(row: BOARD_SIZE / 2, col: BOARD_SIZE / 2)
    static var startKey: CellKey { keyOf(startCell.row, startCell.col) }

    /// This game's start square: the middle of a growing board, or this
    /// seat's corner of an Occupy board.
    var startCell: Cell {
        if let occupy, let seat = occupy.seat, let view = occupy.view {
            return view.startCell(seat: seat)
        }
        return Self.startCell
    }

    /// Where the opener would start from, heading across. Occupy's right-hand
    /// seats head left toward the middle, so their anchor is worked back from
    /// the start square; nil when the word wouldn't fit.
    var openerAnchor: Cell? {
        guard mode == .occupy else { return Self.startCell }
        guard let seat = occupy?.seat else { return nil }
        return occupyOpenerAnchor(
            board: board, bounds: bounds, start: startCell,
            headsRight: occupyOpenerHeadsRight(seat: seat), picks: pickList)
    }

    // MARK: Derived word-building state

    var pickList: [Pick] {
        picks
            .filter { $0 == GAP || rack.indices.contains($0) }
            .map { $0 == GAP ? Pick(letter: nil, rackIndex: GAP) : Pick(letter: rack[$0], rackIndex: $0) }
    }

    /// Whether the staged word borrows a letter from the board.
    var hasGap: Bool { picks.contains(GAP) }

    /// The board is empty: the word in hand is the opener. In Occupy it's
    /// *this seat's* board that counts — everyone opens from their own corner
    /// however much is already down elsewhere.
    var isFirstWord: Bool {
        guard mode == .occupy else { return board.isEmpty }
        guard let occupy, let seat = occupy.seat, let view = occupy.view else { return true }
        return !view.opened[seat]
    }

    var isOccupy: Bool { mode == .occupy }

    /// Where the opener would land, laid out from the start square. Nil once
    /// anything is on the board — later words have no home until a letter is
    /// tapped.
    var plan: PlacementPlan? {
        guard isFirstWord, !pickList.isEmpty, let anchor = openerAnchor else { return nil }
        return planPlacement(
            board: board, bounds: bounds, anchor: anchor, dir: .across, picks: pickList)
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
        let runs = runsTouching(plan.steps.map(\.key), in: next)
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
    /// board to borrow from — anyone's board, in Occupy.
    var canAddGap: Bool { mode == .occupy ? !board.isEmpty : !isFirstWord }

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
    /// but cannot be changed after the summary is dismissed. The second a
    /// refused word is held up in red counts too: it is the game answering,
    /// and a tap landing in the middle of it would be answering back.
    var canAcceptInput: Bool {
        !isComplete && !isPaused && splash == nil && !showSummary && !spectating && !aimRejected
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

    var score: Int { isComplete ? finalScore : liveScore }

    /// What the game is worth right now: the words down, or in Occupy the
    /// value of the tiles this seat holds.
    private var liveScore: Int {
        mode == .occupy ? occupyScore : runningScore
    }

    var isBattle: Bool { mode == .battle }

    // MARK: Occupy, as seen from this seat

    /// Every seat's value on the board as drawn — the host's board with this
    /// player's unanswered words on it.
    var occupyScores: [Int] { occupy?.view?.scores ?? [] }

    var occupySeat: Int? { occupy?.seat }

    var occupyScore: Int {
        guard let seat = occupy?.seat, occupyScores.indices.contains(seat) else { return 0 }
        return occupyScores[seat]
    }

    /// Seconds left on the match clock, or nil when there isn't one running.
    func occupySecondsLeft(at now: Date) -> Int? {
        guard mode == .occupy, !isComplete, let occupy else { return nil }
        let total = Double(occupySeconds(players: occupy.players))
        return Int(ceil(max(0, total - now.timeIntervalSince(occupy.startedAt))))
    }

    /// Seconds until the stall rule ends the game, once that's close enough
    /// to show. Read off this screen's own clocks: they trail the host's by
    /// a message's flight, which is close enough for a warning.
    func occupyStallSecondsLeft(at now: Date) -> Int? {
        guard mode == .occupy, !isComplete, let occupy else { return nil }
        return WordCore.occupyStallSecondsLeft(
            elapsed: now.timeIntervalSince(occupy.startedAt),
            sinceLastWord: now.timeIntervalSince(occupy.lastChangeAt)
        ).map { Int(ceil($0)) }
    }

    /// How many tiles are in hand — the gauge, and the only thing that can
    /// end a game.
    var pileCount: Int { rack.count }

    var pileTone: PileTone {
        // A full pile is the normal state of an Occupy hand, not a warning.
        if mode == .occupy { return .ok }
        if rack.count >= PILE_URGENT { return .urgent }
        if rack.count >= PILE_WARN { return .warn }
        return .ok
    }

    var boardClearReady: Bool {
        !isComplete && boardScore.bonusEarned
    }

    /// Seconds until the next batch lands, whichever clock is running.
    func secondsToNextTiles(at now: Date) -> Int? {
        if mode == .occupy { return nil }
        if let battle {
            return isComplete ? nil : battle.secondsToNextDrip(at: now)
        }
        return solo.remaining(at: now).map { Int(ceil($0)) }
    }

    /// How many tiles that batch will bring — the other half of the header's
    /// "5 tiles in 24s". Both clocks size the *next* batch from the position
    /// they're about to move to, which is what makes the number the player
    /// sees the number they get.
    var nextTileCount: Int? {
        guard !isComplete, !spectating, mode != .occupy else { return nil }
        if let battle {
            return battleDripTilesAt(dripIndex: battle.dripIndex)
        }
        guard countdown != nil else { return nil }
        return endlessDripTiles(phase == .drip ? dripsElapsed + 1 : 0, pace)
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
            wordPool: commonWords, tileCount: SOLO_START_TILES, rng: seededRng(seed))
        rack = puzzle?.letters ?? []
        resetPlayState()
    }

    /// The host said go. Grow the shared deal from the seed and dive in. The
    /// opening batch is `BATTLE_OPENING_TILES` for everyone, which is what keeps
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
        rack = spectating ? [] : stream.next(BATTLE_OPENING_TILES)
        resetPlayState()
    }

    /// The host said go on an Occupy board. The seat, the board's size and
    /// the opening hand all wait on the host's first snapshot, which may
    /// already be here (the host's own `state` lands before its `start`) or
    /// be one message behind (a client's `start` comes first) — either order
    /// ends up in the same place.
    func newOccupy(
        seed: String, selfID: String, state: OccupyState? = nil, spectating: Bool = false,
        now: Date = .now
    ) {
        self.seed = seed
        mode = .occupy
        clearBattle()
        self.spectating = spectating
        solo = SoloSession(battleAt: now)
        gameSerial += 1
        occupy = OccupyRun(seed: seed, selfID: selfID, startedAt: now, lastChangeAt: now)
        owners = [:]
        setBoard(TileMap())
        rack = []
        resetPlayState()
        if let state { adoptOccupy(state, now: now) }
    }

    /// The host's latest board. The first one to name this player's seat also
    /// fixes the board's size and deals the opening hand; every one after it
    /// is laid under whatever words are still waiting on an answer.
    func adoptOccupy(_ state: OccupyState, now: Date = .now) {
        guard mode == .occupy, var run = occupy else { return }
        let changed = run.host?.board != state.board || run.host?.owners != state.owners
        run.host = state
        if changed { run.lastChangeAt = now }
        if run.seat == nil, let seat = state.seat(of: run.selfID) {
            run.seat = seat
            spectating = false
            fixedBounds = state.bounds
            // The board just took its real shape: the camera has to look again.
            gameSerial += 1
        } else if run.seat == nil {
            // Not dealt in — joined mid-game, watching this one out.
            spectating = true
        }
        occupy = run
        refreshOccupyView()
        if let seat = run.seat, rack.isEmpty, !isComplete {
            rack = occupyRefill(count: OCCUPY_HAND, seat: seat)
        }
    }

    /// The host put the word numbered `serial` down. It's already on the
    /// board here, so nothing moves — it just stops being provisional. The
    /// snapshot carrying it lands first under ordered delivery; should the
    /// answer ever arrive alone, the word is folded into the host's board
    /// rather than vanishing until the next snapshot.
    func confirmPlacement(serial: Int) {
        guard var run = occupy, let index = run.pending.firstIndex(where: { $0.serial == serial })
        else { return }
        let confirmed = run.pending.remove(at: index)
        if let host = run.host, let seat = run.seat,
            let folded = try? occupyApply(
                confirmed.placement, seat: seat, at: 0, to: host, isWord: { _ in true })
        {
            run.host = folded
        }
        occupy = run
        refreshOccupyView()
    }

    /// The host turned the word numbered `serial` away: take it back off
    /// the board, put its letters back in the pile in place of the ones
    /// dealt for them, and — if nothing else has been typed since — back
    /// into the row, ready to try somewhere else.
    func refusePlacement(serial: Int, reason: String) {
        guard var run = occupy, let index = run.pending.firstIndex(where: { $0.serial == serial })
        else { return }
        let refused = run.pending.remove(at: index)
        occupy = run

        var pile = rack
        for letter in refused.refill {
            if let at = pile.firstIndex(of: letter) { pile.remove(at: at) }
        }
        pile.append(contentsOf: refused.spent)
        rack = pile
        refreshOccupyView()
        rejectToast(reason)

        guard picks.isEmpty else { return }
        var taken = Set<Int>()
        var restored: [Int] = []
        for letter in refused.typed {
            guard let letter else {
                restored.append(GAP)
                continue
            }
            let at = findAvailable(rack: rack, letter: letter, taken: taken)
            guard at != -1 else { continue }
            taken.insert(at)
            restored.append(at)
        }
        picks = restored
    }

    /// The board is decided. Whatever was still waiting on an answer is
    /// dropped — the host's final board is the only one that counts.
    func finishOccupy(won: Bool, players: Int) {
        guard mode == .occupy else { return }
        battlePlayerCount = players
        if var run = occupy {
            run.pending = []
            occupy = run
            refreshOccupyView()
        }
        guard !isComplete else {
            showSummary = true
            return
        }
        battleWon = won
        finishGame(reason: .battleOver)
    }

    /// Redraw the board as this player sees it: the host's latest snapshot
    /// with every unanswered word laid over it by the host's own rules. A
    /// word the host has since put down lays over as nothing; one the host
    /// will refuse shows until the refusal lands.
    private func refreshOccupyView() {
        guard var run = occupy, let host = run.host else { return }
        var view = host
        if let seat = run.seat {
            for pending in run.pending {
                guard
                    let next = try? occupyApply(
                        pending.placement, seat: seat, at: 0, to: view, isWord: { _ in true })
                else { continue }
                view = next
            }
        }
        run.view = view
        occupy = run
        owners = view.owners
        setBoard(view.board)
    }

    /// Deal an Occupy hand back up to `OCCUPY_HAND`: letters grown off the
    /// board as it stands — anyone's letters — so every one of them has a
    /// known way onto it. Private to the seat and numbered, so a refused word
    /// puts back exactly what was dealt for it.
    private func occupyRefill(count: Int, seat: Int) -> [String] {
        guard count > 0, var run = occupy else { return [] }
        let serial = run.refillSerial
        run.refillSerial += 1
        occupy = run
        let rng = seededRng("\(seed)/occupy/\(seat)/\(serial)")
        var letters: [String] = []
        if let deal = try? extendPuzzle(
            board: board, bounds: bounds, wordPool: commonWords, tileCount: count, rng: rng)
        {
            letters = Array(deal.letters.prefix(count))
        }
        if letters.count < count {
            let stream = TileStream(seed: "\(seed)/occupy/\(seat)/\(serial)/more")
            letters += stream.next(count - letters.count)
        }
        return letters
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
        occupy = nil
        owners = [:]
        occupyWords = []
        fixedBounds = nil
    }

    /// Everything a fresh board resets, whatever dealt it.
    private func resetPlayState() {
        picks = []
        aim = nil
        aimRejected = false
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
        // Occupy's clocks are the host's; nothing lands from them here.
        if mode == .occupy { return }
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
        guard !isComplete, mode != .occupy else {
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
        guard !isComplete, !spectating, mode != .occupy, rack.count >= PILE_LIMIT else { return }
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
        finalScore = liveScore
        finalTilesLeft = rack.count
        finalBonusEarned = boardScore.bonusEarned
        finalWords =
            mode == .occupy
            ? occupyWords
            : (validation?.runs ?? [])
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
        clearAim()
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
        guard canConfirm, let anchor = openerAnchor else { return }
        commit(keyOf(anchor.row, anchor.col), .across)
    }

    /// Tap a placed letter: the staged word lands with its gap on it. A word
    /// with no gap has nowhere to borrow from, and says so rather than doing
    /// nothing (App.tsx selectTile).
    ///
    /// A word that fits but doesn't read gets the same answer a held one
    /// does — itself, in red, on the board — rather than a bare banner: the
    /// two gestures are the same move, so they say the same thing.
    func selectTile(_ key: CellKey) {
        guard let letter = board[key] else { return }
        guard !picks.isEmpty else { return }
        guard hasGap else {
            rejectToast("Put a gap in your word where the \(letter.uppercased()) goes.")
            return
        }
        guard let fit = fitThroughLetter(key) else {
            rejectToast("That word doesn’t fit over this letter.")
            return
        }
        guard fit.isGood else {
            rejectAim(preview(of: fit, through: key))
            return
        }
        commit(keyOf(fit.anchor.row, fit.anchor.col), fit.dir)
    }

    /// One way the staged word can lie over a board letter, and what it would
    /// spell if it did.
    private struct Fit {
        var anchor: Cell
        var dir: Direction
        var plan: PlacementPlan
        /// Runs this placement would make or change that aren’t words.
        var badWords: [String]

        var isGood: Bool { badWords.isEmpty }
    }

    /// Where the staged word would lie with its first gap on the letter at
    /// `key`, or nil when it can’t lie there at all.
    ///
    /// Both the aim preview and the landing itself come through here, so what
    /// press-and-hold shows is by construction the placement that a release
    /// would commit — the preview can never promise one thing and do another.
    private func fitThroughLetter(_ key: CellKey) -> Fit? {
        guard board[key] != nil else { return nil }
        guard pickList.contains(where: { $0.letter == nil }) else { return nil }

        let cell = parseKey(key)
        // Crossing the word the clicked letter already reads in is the
        // likelier intent, so that direction goes first.
        let runDirs = Set((wordsByCell[key] ?? []).map(\.direction))
        let ordered: [Direction] =
            runDirs.contains(.across) == runDirs.contains(.down)
            ? [.across, .down]
            : (runDirs.contains(.across) ? [.down, .across] : [.across, .down])

        let fits: [Fit] = ordered.compactMap { dir in
            guard
                let anchor = anchorForGapTarget(
                    board: board, bounds: bounds, target: cell, dir: dir, picks: pickList)
            else { return nil }
            let plan = planPlacement(
                board: board, bounds: bounds, anchor: anchor, dir: dir, picks: pickList)
            guard plan.complete, !plan.steps.isEmpty else { return nil }
            return Fit(anchor: anchor, dir: dir, plan: plan, badWords: badWords(of: plan, through: key))
        }
        // When the word fits both ways, prefer the way that spells real words.
        return fits.first(where: \.isGood) ?? fits.first
    }

    /// The runs a plan would make or change that aren’t in the dictionary.
    /// A dictionary that hasn’t loaded judges nothing — `commit` refuses
    /// separately rather than calling a real word fake.
    private func badWords(of plan: PlacementPlan, through key: CellKey?) -> [String] {
        guard let dictionary else { return [] }
        var next = board
        for step in plan.steps { next[step.key] = step.letter }
        var placed = plan.steps.map(\.key)
        if let key { placed.append(key) }
        return runsTouching(placed, in: next)
            .filter { $0.word.count < MIN_WORD_LENGTH || !dictionary.contains($0.word) }
            .map(\.word)
    }

    /// Place the staged word so its first gap sits on the letter at `key`
    /// (App.tsx commitThroughLetter, 2168–2217).
    @discardableResult
    func commitThroughLetter(_ key: CellKey) -> Bool {
        guard board[key] != nil else { return false }
        guard pickList.contains(where: { $0.letter == nil }) else { return false }
        guard let fit = fitThroughLetter(key) else {
            rejectToast("That word doesn’t fit over this letter.")
            return false
        }
        return commit(keyOf(fit.anchor.row, fit.anchor.col), fit.dir)
    }

    // MARK: Judging the word in hand

    /// Answer the word row's one question — is this a word? — the same way
    /// landing it would, so the colour a player is looking at is a promise
    /// about what the board would do.
    private func judgeWord() {
        wordVerdict = judgedWord()
    }

    private func judgedWord() -> WordVerdict {
        guard let dictionary else { return .unjudged }
        let staged = pickList
        guard staged.count >= MIN_WORD_LENGTH else { return .unjudged }

        // The opener has one home — the start square, heading across — so it
        // is judged exactly where it would land.
        if isFirstWord { return verdictOK == true ? .good : .bad }

        // A gap is a letter the board has to supply, and which letter that is
        // decides whether this is a word at all: PL_NT is PLANT over an A and
        // nothing over an E. So the question isn't whether the letters spell
        // something, it's whether *any* letter down there would make them —
        // which is the same search the release of a hold does, run over the
        // whole board instead of the one letter under the finger.
        if hasGap {
            return board.keys.contains { fitThroughLetter($0)?.isGood == true } ? .good : .bad
        }

        // No gap: there is nowhere for it to go yet, so all that can be
        // judged is whether the letters picked spell a word.
        let typed = staged.compactMap(\.letter).joined()
        return dictionary.contains(typed) ? .good : .bad
    }

    // MARK: Aiming — press and hold to see where the word goes

    /// Hold the staged word over the letter at `key` without landing it: the
    /// whole word appears on the board, green if it reads and red if it
    /// doesn’t. Aiming somewhere it can’t lie simply shows nothing, so a
    /// finger sliding across the board isn’t chased by refusals.
    func aimThroughLetter(_ key: CellKey) {
        // `canAcceptInput` is what holds the red second still: it goes false
        // the moment a word is refused, so the finger can't re-aim over the
        // answer.
        guard canAcceptInput else { return }
        guard let fit = fitThroughLetter(key) else {
            aim = nil
            return
        }
        let next = preview(of: fit, through: key)
        // A finger held still re-reports the same letter many times a second;
        // writing the same preview back would redraw the board each time.
        guard aim != next else { return }
        aim = next
    }

    /// What a fit looks like on the board: every cell the word would occupy,
    /// with the borrowed letter among them so the whole word lights up as one
    /// thing rather than a word with a hole in it.
    private func preview(of fit: Fit, through key: CellKey) -> AimPreview {
        var cells = Dictionary(uniqueKeysWithValues: fit.plan.steps.map { ($0.key, $0.letter) })
        cells[key] = board[key]
        return AimPreview(through: key, cells: cells, badWords: fit.badWords)
    }

    /// Put a word that doesn't read up in red and start its second. Every
    /// road to a refused word — tapped or held — ends here.
    private func rejectAim(_ preview: AimPreview) {
        aimSerial += 1
        aim = preview
        aim?.serial = aimSerial
        aimRejected = true
    }

    /// Fingers up on an aimed word. A word that reads lands; one that doesn’t
    /// stays up in red, and `finishRejectedAim` takes it back a second later.
    /// Nothing aimed means the hold wandered off the board — fall back on the
    /// tap, which says why.
    func releaseAim(over key: CellKey?) {
        guard let aim else {
            // Nothing was aimed, so there is no preview to clear — and
            // clearing here would wipe the red answer the tap just put up.
            if let key { selectTile(key) }
            return
        }
        guard aim.isGood else {
            rejectAim(aim)
            return
        }
        // The dictionary being mid-load is the one way a good aim can still
        // refuse, and `commit` says so itself.
        commitThroughLetter(aim.through)
        clearAim()
    }

    /// The red second is up: take the word back and say what was wrong with
    /// it. The word itself never left the row, so there is nothing to undo.
    func finishRejectedAim(serial: Int) {
        guard aimRejected, aim?.serial == serial else { return }
        let words = aim?.badWords.map { $0.uppercased() } ?? []
        clearAim()
        guard let first = words.first else { return }
        rejectToast(
            words.count == 1
                ? "\(first) isn’t a real word"
                : "\(words.joined(separator: ", ")) aren’t real words")
    }

    func clearAim() {
        aim = nil
        aimRejected = false
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
        let newRuns = runsTouching(result.steps.map(\.key), in: next)

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

        if mode == .occupy {
            return commitOccupy(
                anchor: parseKey(anchor), dir: dir, plan: result, picks: picksToPlace,
                newRuns: newRuns, dictionary: dictionary)
        }

        // Captured before the board changes: an attack is priced against the
        // words that were already down.
        let oldRuns = mode == .battle ? extractRuns(board) : []

        // Emptied before the board changes, so the word row has nothing left
        // to judge against a board it is no longer waiting on.
        picks = []
        setBoard(next)
        let spent = Set(result.steps.map(\.rackIndex))
        rack = rack.enumerated().filter { !spent.contains($0.offset) }.map(\.element)
        clearAim()
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

    /// Occupy's landing: the word goes on this screen's board at once and
    /// off to the host, with the pile refilled behind it. The host's answer
    /// (`confirmPlacement` / `refusePlacement`) settles it.
    private func commitOccupy(
        anchor: Cell, dir: Direction, plan: PlacementPlan, picks: [Pick], newRuns: [WordRun],
        dictionary: Set<String>
    ) -> Bool {
        guard var run = occupy, let seat = run.seat, let view = run.view else {
            rejectToast("Waiting for the board…")
            return false
        }
        let tiles = Dictionary(uniqueKeysWithValues: plan.steps.map { ($0.key, $0.letter) })
        let borrowed = gapCells(board: board, bounds: bounds, anchor: anchor, dir: dir, picks: picks)
        let placement = OccupyPlacement(tiles: tiles, borrowed: borrowed)

        // Judged by the host's own rules before it's shown — the one thing
        // this can't know is whether someone else got there first.
        let landed: OccupyState
        do {
            landed = try occupyApply(
                placement, seat: seat, at: Date.now.timeIntervalSince1970, to: view,
                isWord: { dictionary.contains($0) })
        } catch let refusal as OccupyRefusal {
            rejectToast(refusal.message)
            return false
        } catch {
            return false
        }

        let before = view.scores[seat]
        let typed: [String?] = picks.map(\.letter)
        let spentIndices = Set(plan.steps.map(\.rackIndex))
        let spent = plan.steps.map(\.letter)
        let captured = borrowed.filter { view.owners[$0] != seat }.count

        run.serial += 1
        let serial = run.serial
        occupy = run
        // Emptied before the board changes, so the word row has nothing left
        // to judge against a board it is no longer waiting on.
        self.picks = []
        rack = rack.enumerated().filter { !spentIndices.contains($0.offset) }.map(\.element)
        let refill = occupyRefill(count: OCCUPY_HAND - rack.count, seat: seat)
        rack.append(contentsOf: refill)

        guard var updated = occupy else { return false }
        updated.pending.append(
            PendingPlacement(
                serial: serial, placement: placement, spent: spent, refill: refill, typed: typed))
        occupy = updated
        refreshOccupyView()
        clearAim()
        cues?.play(.commit)

        let gained = landed.scores[seat] - before
        let word = newRuns.max { $0.word.count < $1.word.count }?.word ?? ""
        occupyWords.append(ScoredWord(word: word, points: gained))
        if captured > 0 {
            rejectToast("Captured \(captured) tile\(captured == 1 ? "" : "s")!")
        }
        onOccupyPlace?(serial, placement)
        return true
    }

    // MARK: Toasts

    /// A refusal that changes nothing on screen reads as a bug, so it always
    /// gets a banner (App.tsx rejectToast, 1979–1981).
    func rejectToast(_ text: String) {
        toastSerial += 1
        toast = GameToast(text: text, serial: toastSerial)
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
        bounds = fixedBounds ?? boardBounds(board)
        tileBounds = tileBox(of: board)
        validation = dictionary.map { validateBoard(board, dictionary: $0) }

        var byCell: [CellKey: [WordRun]] = [:]
        for run in extractRuns(board) where run.cells.count > 1 {
            for cell in run.cells { byCell[cell, default: []].append(run) }
        }
        wordsByCell = byCell

        // A word in hand is only as good as the board it would join, so a
        // board that changed — or a dictionary that just arrived — re-asks.
        judgeWord()
    }
}
