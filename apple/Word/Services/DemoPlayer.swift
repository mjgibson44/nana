#if DEBUG
import Foundation
import WordCore

/// Plays a game by itself, at a watchable speed, for capturing store
/// screenshots and preview video. Debug builds only (`WORD_AUTOSTART=demo`,
/// and the rival in `WORD_AUTOSTART=battle-demo`).
///
/// It plays through the same public moves a finger makes — letters tapped
/// into the row one at a time, a gap where the borrowed letter goes, the
/// word held on that letter so its green preview shows, then let go — so
/// what's filmed is the real game, not a mock of it.
@MainActor
final class DemoPlayer {
    struct Config {
        /// Stop after this many shown words, with the next one built and held
        /// over the board — the frame a screenshot wants. Nil plays on.
        var stopAfter: Int?
        /// Seconds between taps, and the pauses around landing a word.
        var tap = 0.16
        var beat = 0.55
        /// Words played instantly before anything is shown, jumping the clock
        /// to the next deal whenever the pile has nothing left to play — a
        /// game minutes in, reached in a moment.
        var warmup = 0
        /// After the warm-up, take this many deals without playing them, so
        /// the game is filmed with a pile to work through.
        var fillDeals = 0
        /// After the warm-up, park the next deal this many seconds away.
        var parkAt: Int?
        /// Seconds to wait after the warm-up before playing on screen.
        var startDelay: Double?

        static func fromEnvironment(_ environment: [String: String]) -> Config {
            var config = Config()
            config.stopAfter = environment["WORD_DEMO_WORDS"].flatMap(Int.init)
            config.tap = environment["WORD_DEMO_TAP"].flatMap(Double.init) ?? config.tap
            config.beat = environment["WORD_DEMO_BEAT"].flatMap(Double.init) ?? config.beat
            config.warmup = environment["WORD_DEMO_WARMUP"].flatMap(Int.init) ?? 0
            config.parkAt = environment["WORD_DEMO_LEFT"].flatMap(Int.init)
            config.fillDeals = environment["WORD_DEMO_FILL"].flatMap(Int.init) ?? 0
            return config
        }
    }

    private let model: GameModel
    private let config: Config
    private var tap: Double { config.tap }
    private var beat: Double { config.beat }

    init(model: GameModel, config: Config) {
        self.model = model
        self.config = config
    }

    convenience init(model: GameModel) {
        self.init(model: model, config: .fromEnvironment(ProcessInfo.processInfo.environment))
    }

    /// A move found but not yet shown: which word, and through which letter
    /// (nil for the opener).
    private struct Move {
        var word: String
        var through: CellKey?
        var gapAt: Int?
    }

    func run() async {
        while model.dictionary == nil { await pause(0.2) }
        if config.warmup > 0 {
            // Straight past the opening card: the game is already underway.
            model.dismissSplash(at: .now)
            warmUp(config.warmup)
            for _ in 0..<config.fillDeals {
                guard model.mode == .endless, model.rack.count < model.pileLimit - 8,
                    let next = model.secondsToNextTiles(at: .now)
                else { break }
                model.debugTimeShift += Double(next) + 0.05
                model.advanceClock(at: .now)
            }
            // A deal taken here can raise the speed-up card, which holds the
            // clock; it belongs minutes ago, not in the opening frame.
            if model.splash != nil { model.dismissSplash(at: .now) }
            if let toast = model.toast { model.clearToast(serial: toast.serial) }
            model.debugRecentre()
            if let left = config.parkAt, let next = model.secondsToNextTiles(at: .now) {
                model.debugTimeShift += Double(next - left)
            }
        } else {
            // Let the opening card come and go first.
            while model.splash != nil { await pause(0.2) }
        }
        await pause(config.startDelay ?? beat)

        var played = 0
        while !model.isComplete {
            guard let move = findMove() else {
                // Nothing fits this pile: wait for the clock's next tiles.
                await pause(1)
                continue
            }
            let holdForever = config.stopAfter.map { played >= $0 } ?? false
            await show(move, hold: holdForever)
            if holdForever { return }
            played += 1
            await pause(beat * 1.6)
        }
    }

    /// Play `words` words with no pauses at all. When the pile has nothing
    /// that fits, jump the clock to the next deal (Solo only — a battle's
    /// clock is the room's) and carry on. Stops early rather than let the
    /// pile bury the game it is setting up.
    func warmUp(_ words: Int) {
        var placed = 0
        var tries = 0
        while placed < words, !model.isComplete, tries < 400 {
            tries += 1
            if model.boardClearReady { model.claimBoardClear() }
            if let move = findMove() {
                play(move)
                placed += 1
                continue
            }
            guard model.mode == .endless, model.rack.count < model.pileLimit - 6,
                let next = model.secondsToNextTiles(at: .now)
            else { break }
            model.debugTimeShift += Double(next) + 0.05
            model.advanceClock(at: .now)
        }
        model.clearWord()
    }

    /// Land `move` at once — the same moves `show` makes, without the waits.
    private func play(_ move: Move) {
        model.clearWord()
        var used = Set<Int>()
        for (offset, character) in move.word.enumerated() {
            if offset == move.gapAt {
                model.addGap()
            } else if let index = model.rack.indices.first(where: {
                model.rack[$0] == String(character) && !used.contains($0)
            }) {
                used.insert(index)
                model.togglePick(index)
            }
        }
        if let through = move.through {
            model.aimThroughLetter(through)
            model.releaseAim(over: through)
        } else {
            model.confirm()
        }
    }

    /// Play one word right now, shown at the usual pace. For a scripted beat
    /// in a capture — the rival's attack in the battle demo.
    /// `longest` reaches for the longest word that fits instead — the one
    /// that hits hardest in a battle.
    @discardableResult
    func showOne(longest: Bool = false) async -> Bool {
        guard let move = findMove(pool: longest ? Self.longestFirst : Self.pool) else { return false }
        await show(move, hold: false)
        return true
    }

    // MARK: Showing a move

    private func show(_ move: Move, hold: Bool) async {
        model.clearWord()
        var used = Set<Int>()
        for (offset, character) in move.word.enumerated() {
            if offset == move.gapAt {
                model.addGap()
            } else if let index = model.rack.indices.first(where: {
                model.rack[$0] == String(character) && !used.contains($0)
            }) {
                used.insert(index)
                model.togglePick(index)
            }
            await pause(tap)
        }
        await pause(beat)
        if let through = move.through {
            model.aimThroughLetter(through)
            if hold { return }
            await pause(beat * 1.4)
            model.releaseAim(over: through)
        } else {
            if hold { return }
            model.confirm()
        }
    }

    // MARK: Finding a move

    /// The longest common word this pile can play right now: the opener on
    /// an empty board, otherwise a word through a board letter that lands
    /// green. Searched silently — every trial is cleared before the screen
    /// gets a chance to draw it.
    private func findMove(pool: [String] = DemoPlayer.pool) -> Move? {
        let rack = model.rack
        let counts = rack.reduce(into: [Character: Int]()) { $0[Character($1), default: 0] += 1 }
        let candidates = pool.filter { $0.count <= rack.count + 1 }

        if model.isFirstWord {
            return candidates.first { Self.spellable($0, from: counts, skipping: nil) }
                .map { Move(word: $0, through: nil, gapAt: nil) }
        }

        let board = model.board
        var found: Move?
        search: for word in candidates where word.count >= 3 {
            let letters = Array(word)
            for (at, letter) in letters.enumerated() {
                guard Self.spellable(word, from: counts, skipping: at) else { continue }
                for (key, sitting) in board where sitting == String(letter) {
                    if fits(letters, gapAt: at, through: key) {
                        found = Move(word: word, through: key, gapAt: at)
                        break search
                    }
                }
            }
        }
        model.clearWord()
        return found
    }

    private func fits(_ letters: [Character], gapAt: Int, through key: CellKey) -> Bool {
        model.clearWord()
        var used = Set<Int>()
        for (offset, character) in letters.enumerated() {
            if offset == gapAt {
                model.addGap()
                continue
            }
            guard let index = model.rack.indices.first(where: {
                model.rack[$0] == String(character) && !used.contains($0)
            }) else { return false }
            used.insert(index)
            model.togglePick(index)
        }
        model.aimThroughLetter(key)
        let good = model.aim?.isGood == true
        model.clearAim()
        return good
    }

    private static func spellable(
        _ word: String, from counts: [Character: Int], skipping: Int?
    ) -> Bool {
        var left = counts
        for (offset, character) in word.enumerated() where offset != skipping {
            guard let have = left[character], have > 0 else { return false }
            left[character] = have - 1
        }
        return true
    }

    /// Common words, five letters first, then four and six: long enough to
    /// look like play, short enough that the pile isn't emptied in three
    /// moves and the board grows a word at a time.
    private static let preference = [5, 4, 6, 3, 7]
    private static let longestFirst: [String] = commonWords
        .filter { (4...8).contains($0.count) }
        .sorted { $0.count != $1.count ? $0.count > $1.count : $0 < $1 }
    private static let pool: [String] = commonWords
        .filter { preference.contains($0.count) }
        .sorted {
            let a = preference.firstIndex(of: $0.count)!
            let b = preference.firstIndex(of: $1.count)!
            return a != b ? a < b : $0 < $1
        }

    private func pause(_ seconds: Double) async {
        try? await Task.sleep(for: .milliseconds(Int(seconds * 1000)))
    }
}
#endif
