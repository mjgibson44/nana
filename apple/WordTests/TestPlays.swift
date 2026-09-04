import WordCore
import XCTest

@testable import Word

/// Ways of playing real words through the real model. Only real words are
/// allowed down, so a test that wants tiles on the board has to find some —
/// and every game is seeded, so what it finds is the same every run.
@MainActor
enum TestPlays {
    /// The longest real word the rack can spell, with the rack indices that
    /// spell it. Brute force over short combinations — the rack is at most
    /// thirty tiles and this runs a handful of times.
    static func spellableWord(
        in model: GameModel, lengths: [Int] = [5, 4, 3]
    ) -> (word: String, indices: [Int])? {
        guard let dictionary = model.dictionary else { return nil }
        let rack = model.rack
        for length in lengths {
            for combo in permutations(of: Array(rack.indices), choose: length) {
                let word = combo.map { rack[$0] }.joined()
                if dictionary.contains(word) { return (word, combo) }
            }
        }
        return nil
    }

    /// Spell the opener and confirm it. Returns the word.
    @discardableResult
    static func placeOpener(on model: GameModel) throws -> String {
        XCTAssertNotNil(model.dictionary, "load the dictionary first")
        guard let (word, indices) = spellableWord(in: model) else {
            throw XCTSkip("this rack can't spell an opener")
        }
        for index in indices { model.togglePick(index) }
        XCTAssertTrue(model.canConfirm, "\(word) should be confirmable")
        XCTAssertTrue(model.handle(.confirm))
        XCTAssertEqual(model.board.count, word.count)
        return word
    }

    /// Land a second word through a gap on a letter already on the board:
    /// the only way anything but the opener ever gets down. Returns the word
    /// and the letter it borrowed.
    @discardableResult
    static func attachWord(on model: GameModel) throws -> (word: String, through: CellKey) {
        guard let dictionary = model.dictionary else {
            throw XCTSkip("load the dictionary first")
        }
        XCTAssertFalse(model.board.isEmpty, "nothing to attach to")
        for key in model.board.keys {
            let borrowed = model.board[key]!
            for length in [3, 4] {
                for gapAt in 0..<length {
                    for combo in permutations(of: Array(model.rack.indices), choose: length - 1) {
                        var letters = combo.map { model.rack[$0] }
                        letters.insert(borrowed, at: gapAt)
                        let word = letters.joined()
                        guard dictionary.contains(word) else { continue }

                        var picks = combo.makeIterator()
                        for position in 0..<length {
                            if position == gapAt {
                                model.addGap()
                            } else {
                                model.togglePick(picks.next()!)
                            }
                        }
                        if model.commitThroughLetter(key) { return (word, key) }
                        model.clearWord()
                    }
                }
            }
        }
        throw XCTSkip("no word in this rack attaches to the board")
    }

    /// Ordered picks of `k` from `items`, capped so a big rack can't blow up
    /// a test's runtime.
    static func permutations(of items: [Int], choose k: Int, cap: Int = 6_000) -> [[Int]] {
        guard k > 0 else { return [[]] }
        var result: [[Int]] = []
        for (offset, item) in items.enumerated() {
            var rest = items
            rest.remove(at: offset)
            for tail in permutations(of: rest, choose: k - 1, cap: cap) {
                result.append([item] + tail)
                if result.count >= cap { return result }
            }
        }
        return result
    }
}
