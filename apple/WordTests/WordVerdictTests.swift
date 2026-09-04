import WordCore
import XCTest

@testable import Word

/// The word row's live answer to "is this a word?", and the one-line layout
/// that answer is painted on.
///
/// The interesting case is the gap. A gapped word doesn't spell anything on
/// its own — PL_NT is a word over an A and nothing over an E — so the verdict
/// has to ask the board, not the letters, and it has to agree with what
/// landing the word would actually do.
@MainActor
final class WordVerdictTests: XCTestCase {
    private func gameWithABoard(seed: String = "verdict") async throws -> GameModel {
        let model = GameModel()
        model.newGame(seed: seed)
        model.dismissSplash()
        await model.loadDictionary()
        try TestPlays.placeOpener(on: model)
        return model
    }

    // MARK: Nothing to judge yet

    func testAnEmptyRowSaysNothing() async throws {
        let model = try await gameWithABoard()
        XCTAssertEqual(model.wordVerdict, .unjudged)
    }

    func testTooFewLettersToBeAWordSaysNothing() async throws {
        let model = GameModel()
        model.newGame(seed: "verdict")
        await model.loadDictionary()
        model.togglePick(0)
        XCTAssertEqual(
            model.wordVerdict, .unjudged,
            "one letter isn't a word yet, and calling it wrong would be nagging")
    }

    // MARK: The opener

    func testTheOpenerIsGoodWhenItReads() async throws {
        let model = GameModel()
        model.newGame(seed: "verdict")
        await model.loadDictionary()
        guard let (_, indices) = TestPlays.spellableWord(in: model) else {
            throw XCTSkip("this pile can't spell an opener")
        }
        for index in indices { model.togglePick(index) }
        XCTAssertEqual(model.wordVerdict, .good)
        XCTAssertTrue(model.canConfirm, "the colour and the button have to agree")
    }

    func testAnOpenerThatIsntAWordIsBad() async throws {
        let model = GameModel()
        model.newGame(seed: "verdict")
        await model.loadDictionary()
        // Whatever the first three tiles are, they are almost never a word —
        // and if they happen to be one, the assert below says so rather than
        // passing vacuously.
        model.togglePick(0)
        model.togglePick(1)
        model.togglePick(2)
        let typed = model.pickList.compactMap(\.letter).joined()
        try XCTSkipIf(model.dictionary?.contains(typed) == true, "\(typed) is a word")
        XCTAssertEqual(model.wordVerdict, .bad)
        XCTAssertFalse(model.canConfirm)
    }

    // MARK: The gap — the reason this exists

    func testAGappedWordIsGoodWhenSomeBoardLetterWouldMakeItOne() async throws {
        let model = try await gameWithABoard()
        let key = try stageGoodGappedWord(on: model)
        XCTAssertEqual(
            model.wordVerdict, .good,
            "there is a letter on the board this reads over")
        // And the promise is kept: it really does land there.
        XCTAssertTrue(model.commitThroughLetter(key))
    }

    func testAGappedWordNoLetterOnTheBoardCanSaveIsBad() async throws {
        let model = try await gameWithABoard()
        // Some gap-and-two-letters this pile can build reads over nothing on
        // the board. Find the first, and hold the row to it.
        var found = false
        search: for first in model.rack.indices {
            for second in model.rack.indices where second != first {
                model.clearWord()
                model.addGap()
                model.togglePick(first)
                model.togglePick(second)
                if model.wordVerdict == .bad {
                    found = true
                    break search
                }
            }
        }
        try XCTSkipUnless(found, "every pair this pile builds reads over some letter")

        // And it is bad for the stated reason: every letter down there
        // refuses it, which is the same answer a hold would give.
        for key in model.board.keys {
            model.aimThroughLetter(key)
            XCTAssertNotEqual(
                model.aim?.isGood, true,
                "the row says no word, but \(key) would have made one")
            model.clearAim()
        }
    }

    func testTakingTheLastLetterBackReopensTheQuestion() async throws {
        let model = try await gameWithABoard()
        _ = try stageGoodGappedWord(on: model)
        XCTAssertEqual(model.wordVerdict, .good)
        model.clearWord()
        XCTAssertEqual(model.wordVerdict, .unjudged)
    }

    func testLandingAWordClearsTheVerdictWithTheRow() async throws {
        let model = try await gameWithABoard()
        let key = try stageGoodGappedWord(on: model)
        XCTAssertTrue(model.commitThroughLetter(key))
        XCTAssertTrue(model.picks.isEmpty)
        XCTAssertEqual(model.wordVerdict, .unjudged)
    }

    /// Stage a word that reads through some letter already down, and return
    /// the letter it reads through. Left staged, not landed.
    private func stageGoodGappedWord(on model: GameModel) throws -> CellKey {
        guard let dictionary = model.dictionary else { throw XCTSkip("no dictionary") }
        for key in model.board.keys {
            let borrowed = model.board[key]!
            for length in [3, 4] {
                for gapAt in 0..<length {
                    for combo in TestPlays.permutations(
                        of: Array(model.rack.indices), choose: length - 1)
                    {
                        var letters = combo.map { model.rack[$0] }
                        letters.insert(borrowed, at: gapAt)
                        guard dictionary.contains(letters.joined()) else { continue }
                        var picks = combo.makeIterator()
                        for position in 0..<length {
                            if position == gapAt {
                                model.addGap()
                            } else {
                                model.togglePick(picks.next()!)
                            }
                        }
                        guard model.wordVerdict == .good else {
                            model.clearWord()
                            continue
                        }
                        return key
                    }
                }
            }
        }
        throw XCTSkip("no word in this pile attaches to this board")
    }

    // MARK: One line, however long the word

    func testAShortWordUsesTheTilesThePileUses() {
        let layout = Spacing.wordRow(count: 5, fitting: 358, cap: 33)
        XCTAssertEqual(layout.size, 33, accuracy: 0.001)
        XCTAssertEqual(layout.gap, Spacing.tileGap)
    }

    func testALongWordShrinksRatherThanWrapping() {
        let width: CGFloat = 358
        for count in 1...PILE_LIMIT {
            let layout = Spacing.wordRow(count: count, fitting: width, cap: 33)
            let used = CGFloat(count) * layout.size + CGFloat(count - 1) * layout.gap
            XCTAssertLessThanOrEqual(
                used, width + 0.001,
                "\(count) tiles want \(used)pt of a \(width)pt row — that would wrap")
            XCTAssertLessThanOrEqual(layout.size, 33, "and never grow past a pile tile")
        }
    }

    func testAWordLongEnoughToGoTinyGivesUpItsGapsFirst() {
        let tight = Spacing.wordRow(count: PILE_LIMIT, fitting: 358, cap: 33)
        let roomy = Spacing.wordRow(count: 8, fitting: 358, cap: 33)
        XCTAssertLessThan(tight.gap, roomy.gap)
    }
}

/// The verdict is recomputed on every tap, and a gapped word's verdict asks
/// every letter on the board. A late-game board is big, so the cost of that
/// question is a gate, not an assumption.
@MainActor
final class WordVerdictCostTests: XCTestCase {
    /// A board the size a long Solo game reaches: 12 words of 12 letters,
    /// spaced so they don't run into each other.
    private func bigBoard() -> TileMap {
        var board = TileMap()
        let letters = Array("retinasolace")
        for (row, start) in stride(from: 6, to: 30, by: 2).enumerated() {
            for column in 0..<letters.count {
                board[keyOf(start, 6 + column)] = String(letters[(row + column) % letters.count])
            }
        }
        return board
    }

    private func modelOnABigBoard() async -> GameModel {
        let model = GameModel()
        model.newGame(seed: "cost")
        model.dismissSplash()
        await model.loadDictionary()
        model.restore(
            SavedSoloGame(
                seed: "cost", pace: SoloPace.regular.rawValue, board: bigBoard(),
                rack: Array(repeating: "e", count: 12), phase: "drip", dripsElapsed: 1,
                bankedBonus: 0, remainingSeconds: 60, dealSerial: 1,
                savedAt: Date.now.timeIntervalSince1970))
        return model
    }

    func testJudgingAGappedWordOnABigBoardIsFastEnoughForATap() async {
        let model = await modelOnABigBoard()
        XCTAssertGreaterThan(model.board.count, 130, "the premise: a big board")
        // A four-letter word with a gap in it: long enough to be judged, so
        // every letter on the board gets asked.
        model.addGap()
        model.togglePick(1)
        model.togglePick(2)
        XCTAssertEqual(model.wordVerdict, .bad, "the premise: the whole board was searched")

        let started = Date.now
        for _ in 0..<10 {
            model.togglePick(0)
            model.togglePick(0)
        }
        let each = Date.now.timeIntervalSince(started) / 20
        // Generous, and deliberately so: tests run unoptimized, so the real
        // app has far more room than this. The gate is here to catch an
        // order-of-magnitude regression — asking `extractRuns` about the
        // whole board once per letter, which is what this cost before
        // `runsTouching`, is 70ms right here.
        XCTAssertLessThan(
            each, 0.025,
            "judging the word took \(Int(each * 1_000))ms — a tap has one frame to answer in")
    }
}
