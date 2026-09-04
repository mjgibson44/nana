import WordCore
import XCTest

@testable import Word

/// Press-and-hold on a placed letter: the staged word appears where it would
/// land, green when it reads and red when it doesn't. Nothing about it is a
/// commit until the fingers come up, and a word that doesn't read is held up
/// long enough to be read before it's taken back.
@MainActor
final class AimPreviewTests: XCTestCase {
    private func gameWithABoard(seed: String = "aim") async throws -> GameModel {
        let model = GameModel()
        model.newGame(seed: seed)
        model.dismissSplash()
        await model.loadDictionary()
        try TestPlays.placeOpener(on: model)
        return model
    }

    /// Stage a word that reads through one of the letters already down,
    /// without landing it: the picks and the letter it aims at.
    private func stageAttachableWord(on model: GameModel) throws -> CellKey {
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
                        model.aimThroughLetter(key)
                        guard model.aim?.isGood == true else {
                            model.clearWord()
                            continue
                        }
                        model.clearAim()
                        return key
                    }
                }
            }
        }
        throw XCTSkip("no word in this rack attaches to the board")
    }

    func testHoldingAGoodWordOverALetterShowsItWithoutLandingIt() async throws {
        let model = try await gameWithABoard()
        let key = try stageAttachableWord(on: model)
        let board = model.board
        let picks = model.picks

        model.aimThroughLetter(key)

        let aim = try XCTUnwrap(model.aim)
        XCTAssertTrue(aim.isGood, "the word reads, so it shows amber")
        XCTAssertEqual(aim.through, key)
        XCTAssertEqual(aim.cells[key], board[key], "the borrowed letter is part of the word aimed")
        XCTAssertGreaterThan(aim.cells.count, 1)
        XCTAssertEqual(model.board, board, "aiming never lands anything")
        XCTAssertEqual(model.picks, picks, "and never spends the word")
    }

    func testLettingGoOfAGoodAimLandsTheWord() async throws {
        let model = try await gameWithABoard()
        let key = try stageAttachableWord(on: model)
        let placed = model.board.count
        let staged = model.pickList.filter { $0.letter != nil }.count

        model.aimThroughLetter(key)
        model.releaseAim(over: key)

        XCTAssertNil(model.aim)
        XCTAssertEqual(model.board.count, placed + staged, "every letter but the borrowed one")
        XCTAssertTrue(model.picks.isEmpty, "the word left the row")
        XCTAssertTrue(model.usedGapTile)
    }

    func testAWordThatIsNotAWordShowsRedThenComesBackWithTheReason() async throws {
        let model = try await gameWithABoard()
        let board = model.board
        let key = board.keys[0]
        let borrowed = board[key]!

        // Every rack tile in pile order after a gap: a long nonsense run
        // through the borrowed letter, which fits but doesn't read.
        model.addGap()
        for index in model.rack.indices.prefix(3) { model.togglePick(index) }
        model.aimThroughLetter(key)
        let aim = try XCTUnwrap(model.aim, "it fits over the letter, so it previews")
        try XCTSkipIf(aim.isGood, "this rack happens to spell a real word here")

        XCTAssertFalse(aim.isGood)
        XCTAssertFalse(aim.badWords.isEmpty)
        XCTAssertTrue(
            aim.badWords.contains { $0.contains(borrowed) },
            "the run it can't spell goes through the borrowed letter")

        let staged = model.picks
        model.releaseAim(over: key)
        XCTAssertTrue(model.aimRejected, "the red word stays up")
        XCTAssertNotNil(model.aim)
        XCTAssertEqual(model.board, board, "nothing landed")
        XCTAssertFalse(model.canAcceptInput, "and the board is deaf while it says so")

        model.finishRejectedAim(serial: try XCTUnwrap(model.aim?.serial))
        XCTAssertNil(model.aim, "the second is up; the word comes back")
        XCTAssertFalse(model.aimRejected)
        XCTAssertEqual(model.picks, staged, "and it's still in the row, ready to fix")
        let toast = try XCTUnwrap(model.toast?.text)
        XCTAssertTrue(toast.contains("real word"), "toast said: \(toast)")
        XCTAssertTrue(
            toast.uppercased().contains(aim.badWords[0].uppercased()),
            "the toast names the word: \(toast)")
    }

    func testAStaleTimeoutCannotTakeBackALaterAim() async throws {
        let model = try await gameWithABoard()
        let key = model.board.keys[0]
        model.addGap()
        for index in model.rack.indices.prefix(3) { model.togglePick(index) }
        model.aimThroughLetter(key)
        try XCTSkipIf(model.aim?.isGood != false, "this rack spells a real word here")
        model.releaseAim(over: key)
        let serial = try XCTUnwrap(model.aim?.serial)

        model.finishRejectedAim(serial: serial - 1)

        XCTAssertNotNil(model.aim, "an older timeout is not this word's")
        XCTAssertTrue(model.aimRejected)
    }

    func testAimingAtAnEmptySquareShowsNothing() async throws {
        let model = try await gameWithABoard()
        let key = try stageAttachableWord(on: model)
        model.aimThroughLetter(key)
        XCTAssertNotNil(model.aim)

        // A finger sliding off the word onto bare board: there is no letter
        // to borrow, so the preview goes away rather than sticking.
        let empty = keyOf(GameModel.startCell.row - 3, GameModel.startCell.col)
        XCTAssertNil(model.board[empty], "this square really is empty")
        model.aimThroughLetter(empty)

        XCTAssertNil(model.aim, "nothing to show is shown as nothing, not as a refusal")
        XCTAssertNil(model.toast, "and a finger sliding across the board isn't told off")
    }

    func testAWordWithNoGapCannotBeAimedAtAll() async throws {
        let model = try await gameWithABoard()
        guard let (_, indices) = TestPlays.spellableWord(in: model) else {
            throw XCTSkip("this rack can't spell a second word")
        }
        for index in indices { model.togglePick(index) }
        XCTAssertFalse(model.hasGap)

        model.aimThroughLetter(model.board.keys[0])

        XCTAssertNil(model.aim, "there is nowhere for a gapless word to lie over a letter")
        XCTAssertNil(model.toast)
    }

    func testLettingGoWithNothingAimedFallsBackOnTheTap() async throws {
        let model = try await gameWithABoard()
        let key = model.board.keys[0]
        model.addGap()
        for index in model.rack.indices { model.togglePick(index) }
        let staged = model.picks

        // The hold never found a letter, so releasing over one is just a tap
        // on it — and a tap answers the same way a hold does.
        model.releaseAim(over: key)

        XCTAssertEqual(model.picks, staged, "a refusal never discards the word")
        if model.aimRejected {
            XCTAssertEqual(model.aim?.isGood, false, "the word is up in red")
            model.finishRejectedAim(serial: try XCTUnwrap(model.aim?.serial))
        }
        XCTAssertNil(model.aim)
        XCTAssertNotNil(model.toast, "and it says why, the way tapping does")
    }

    func testATappedNonWordGetsTheSameRedAnswerAsAHeldOne() async throws {
        let model = try await gameWithABoard()
        let key = model.board.keys[0]
        model.addGap()
        for index in model.rack.indices.prefix(3) { model.togglePick(index) }
        // What the hold would show…
        model.aimThroughLetter(key)
        let held = try XCTUnwrap(model.aim)
        try XCTSkipIf(held.isGood, "this rack spells a real word here")
        model.clearAim()

        // …is what the tap puts up.
        model.selectTile(key)

        XCTAssertTrue(model.aimRejected)
        XCTAssertEqual(model.aim?.cells, held.cells)
        XCTAssertEqual(model.aim?.badWords, held.badWords)
    }

    func testClearingTheWordClearsWhateverWasAimedWithIt() async throws {
        let model = try await gameWithABoard()
        let key = try stageAttachableWord(on: model)
        model.aimThroughLetter(key)
        XCTAssertNotNil(model.aim)

        model.clearWord()

        XCTAssertNil(model.aim)
    }
}
