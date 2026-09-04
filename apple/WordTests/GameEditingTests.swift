import WordCore
import XCTest

@testable import Word

/// Building and landing words under the redesign's rules: the opener lands
/// from the start square by confirm, every later word borrows a letter
/// through a gap, only real words land, and nothing on the board ever moves.
@MainActor
final class GameEditingTests: XCTestCase {
    private func makeGame(seed: String = "phase-2b-editing") async -> GameModel {
        let model = GameModel()
        model.newGame(seed: seed)
        await model.loadDictionary()
        return model
    }

    func testKeyboardClaimsOnlyAvailableRackLetters() async {
        let model = await makeGame()
        let letter = try! XCTUnwrap(model.rack.first)

        XCTAssertTrue(model.handle(.letter(letter.uppercased())))
        XCTAssertEqual(model.picks, [0])

        let impossible = "abcdefghijklmnopqrstuvwxyz".map(String.init).first { wanted in
            !model.rack.contains { $0.caseInsensitiveCompare(wanted) == .orderedSame }
        }
        if let impossible {
            XCTAssertTrue(model.handle(.letter(impossible)))
            XCTAssertEqual(model.picks, [0])
        }
    }

    func testBackspaceEscapeAndTappingAStagedTileEditTheWord() async {
        let model = await makeGame()
        model.togglePick(0)
        model.togglePick(1)
        model.togglePick(2)
        XCTAssertEqual(model.picks, [0, 1, 2])

        XCTAssertTrue(model.handle(.backspace))
        XCTAssertEqual(model.picks, [0, 1])

        model.removePick(at: 0)
        XCTAssertEqual(model.picks, [1])

        // Picking a claimed tile again releases it.
        model.togglePick(1)
        XCTAssertTrue(model.picks.isEmpty)
        XCTAssertFalse(model.handle(.escape), "nothing to clear")

        model.togglePick(0)
        XCTAssertTrue(model.handle(.escape))
        XCTAssertTrue(model.picks.isEmpty)
    }

    func testTheOpenerLandsFromTheStartSquareHeadingAcross() async throws {
        let model = await makeGame()
        let tiles = model.rack.count
        XCTAssertTrue(model.isFirstWord)

        let word = try TestPlays.placeOpener(on: model)

        XCTAssertFalse(model.isFirstWord)
        XCTAssertTrue(model.picks.isEmpty, "the word left the row when it landed")
        XCTAssertEqual(model.rack.count, tiles - word.count)
        for (offset, letter) in word.enumerated() {
            let key = keyOf(GameModel.startCell.row, GameModel.startCell.col + offset)
            XCTAssertEqual(model.board[key], String(letter), "letter \(offset) of \(word)")
        }
        XCTAssertFalse(model.canConfirm, "confirm is only for the opener")
    }

    func testTheOpenerPreviewsFromTheStartSquareWhileTyped() async throws {
        let model = await makeGame()
        guard let (word, indices) = TestPlays.spellableWord(in: model) else {
            throw XCTSkip("this rack can't spell an opener")
        }
        for index in indices { model.togglePick(index) }
        XCTAssertEqual(model.preview.count, word.count)
        XCTAssertEqual(model.preview[GameModel.startKey], String(word.first!))
        XCTAssertEqual(model.verdictOK, true)
    }

    func testTheOpenerMustBeARealWord() async throws {
        let model = await makeGame()
        guard let (word, indices) = TestPlays.spellableWord(in: model) else {
            throw XCTSkip("this rack can't spell an opener")
        }
        // The same letters backwards are very unlikely to be a word; skip the
        // rare rack where they are.
        let reversed = String(word.reversed())
        try XCTSkipIf(model.dictionary?.contains(reversed) == true)
        for index in indices.reversed() { model.togglePick(index) }

        XCTAssertEqual(model.verdictOK, false)
        XCTAssertFalse(model.canConfirm)
        XCTAssertFalse(model.handle(.confirm))
        XCTAssertTrue(model.board.isEmpty, "nothing that isn't a word gets down")
        XCTAssertEqual(model.picks.count, word.count, "and the word stays in the row")
    }

    func testAGapIsRefusedBeforeTheOpener() async {
        let model = await makeGame()
        XCTAssertFalse(model.canAddGap)
        model.addGap()
        XCTAssertTrue(model.picks.isEmpty)
        XCTAssertNotNil(model.toast, "a refusal that changes nothing on screen says why")
    }

    func testALaterWordMustBorrowALetterThroughAGap() async throws {
        let model = await makeGame()
        try TestPlays.placeOpener(on: model)
        let placed = model.board
        guard let (_, indices) = TestPlays.spellableWord(in: model) else {
            throw XCTSkip("this rack can't spell a second word")
        }
        for index in indices { model.togglePick(index) }

        // No gap: nothing to borrow with. Tapping a board letter refuses and
        // says so, and there is no confirm button any more.
        XCTAssertFalse(model.canConfirm)
        XCTAssertFalse(model.handle(.confirm))
        model.selectTile(placed.keys[0])
        XCTAssertEqual(model.board, placed)
        XCTAssertTrue(model.toast?.text.contains("gap") ?? false)
        XCTAssertEqual(model.picks.count, indices.count, "the word is still in hand")
    }

    func testAWordLandsThroughItsGapOnATappedLetter() async throws {
        let model = await makeGame()
        let opener = try TestPlays.placeOpener(on: model)
        let tiles = model.rack.count

        let (word, through) = try TestPlays.attachWord(on: model)

        XCTAssertEqual(model.board.count, opener.count + word.count - 1, "one letter was borrowed")
        XCTAssertEqual(model.rack.count, tiles - (word.count - 1))
        XCTAssertTrue(model.picks.isEmpty)
        XCTAssertTrue(model.usedGapTile)
        let runs = extractRuns(model.board)
        XCTAssertTrue(runs.contains { $0.word == word }, "\(word) should read on the board")
        XCTAssertTrue(
            runs.first { $0.word == word }?.cells.contains(through) ?? false,
            "and it runs through the tapped letter")
        XCTAssertTrue(isConnected(model.board), "everything attaches to the crossword")
    }

    func testAGapOnTheWrongLetterIsRefused() async throws {
        let model = await makeGame()
        try TestPlays.placeOpener(on: model)
        let placed = model.board
        // A gap followed by every rack tile: it lies over the letter, but it
        // is nobody's idea of a word.
        model.addGap()
        for index in model.rack.indices { model.togglePick(index) }
        let staged = model.picks

        model.selectTile(placed.keys[0])

        XCTAssertEqual(model.board, placed)
        XCTAssertEqual(model.picks, staged, "a refusal never discards the word")
        // The refusal is the word itself, in red, for a second — then the
        // reason, in the usual banner.
        XCTAssertTrue(model.aimRejected)
        XCTAssertEqual(model.aim?.isGood, false)
        model.finishRejectedAim(serial: try XCTUnwrap(model.aim?.serial))
        XCTAssertNil(model.aim)
        XCTAssertEqual(model.picks, staged, "and it comes back to the row")
        XCTAssertNotNil(model.toast)
    }

    func testShufflingThePileKeepsTheStagedWord() async {
        let model = await makeGame()
        model.togglePick(0)
        model.togglePick(3)
        model.togglePick(5)
        let staged = model.pickList.map(\.letter)
        let before = model.rack

        model.shufflePile()

        XCTAssertEqual(model.rack.sorted(), before.sorted())
        XCTAssertEqual(model.pickList.map(\.letter), staged)
        XCTAssertEqual(Set(model.picks).count, 3, "three distinct tiles are still claimed")
    }

    func testNothingOnTheBoardCanComeBackOff() async throws {
        let model = await makeGame()
        try TestPlays.placeOpener(on: model)
        let placed = model.board
        let rack = model.rack

        // Tapping a placed letter with nothing in hand does nothing at all —
        // no selection, no lift, no return to the pile.
        model.selectTile(placed.keys[0])
        XCTAssertEqual(model.board, placed)
        XCTAssertEqual(model.rack, rack)
        XCTAssertNil(model.toast)
    }

    func testAFullPileEndsASoloGameOnTheSpot() {
        let model = GameModel()
        let start = Date(timeIntervalSince1970: 1_000)
        model.newGame(seed: "buried", pace: .fast, now: start)
        model.dismissSplash(at: start)
        XCTAssertEqual(model.pileTone, .ok)

        var now = start.addingTimeInterval(Double(endlessInitialSeconds(.fast)) + 1)
        var deals = 0
        while !model.isComplete, deals < 40 {
            model.advanceClock(at: now)
            now = now.addingTimeInterval(Double(endlessDripSeconds(model.dripsElapsed, .fast)) + 1)
            deals += 1
        }

        XCTAssertTrue(model.isComplete)
        XCTAssertEqual(model.endReason, .buried)
        XCTAssertGreaterThanOrEqual(model.rack.count, PILE_LIMIT)
        XCTAssertTrue(model.showSummary)
        XCTAssertFalse(model.canAcceptInput)
        XCTAssertNil(model.countdown, "the clock stops with the game")
    }

    func testTheGaugeStartsCalmAndTurnsRedShortOfTheLimit() {
        let model = GameModel()
        let start = Date(timeIntervalSince1970: 1_000)
        model.newGame(seed: "gauge", pace: .regular, now: start)
        model.dismissSplash(at: start)
        XCTAssertEqual(model.pileCount, SOLO_START_TILES)
        XCTAssertEqual(model.pileTone, .ok, "a fresh deal is room to work, not trouble")

        // One tile past the opening deal turns it amber…
        model.togglePick(0)
        XCTAssertEqual(model.pileTone, .ok, "picking doesn't change what's in hand")
        model.clearWord()

        // …and one regular batch lands five: twenty-one is in the red.
        model.advanceClock(at: start.addingTimeInterval(Double(endlessInitialSeconds(.regular)) + 1))
        XCTAssertEqual(model.pileCount, SOLO_START_TILES + ENDLESS_SMALL_BATCH)
        XCTAssertEqual(model.pileTone, .urgent)
        XCTAssertFalse(model.isComplete, "red is a warning; only a full pile ends it")
        XCTAssertEqual(PILE_WARN, SOLO_START_TILES + 1, "amber starts one tile past the opening deal")
        XCTAssertLessThan(PILE_URGENT, PILE_LIMIT, "red has to have somewhere to warn from")
        XCTAssertEqual(
            PILE_LIMIT, Spacing.columns * Spacing.pileRows,
            "the pile on screen is the limit — a full field means a full pile")
        // Both modes open on the share of the pile they were tuned at. A
        // limit that moves without these moving with it deals a game that
        // starts nearly buried.
        XCTAssertEqual(Double(SOLO_START_TILES) / Double(PILE_LIMIT), 2.0 / 3, accuracy: 0.02)
        XCTAssertEqual(Double(BATTLE_OPENING_TILES) / Double(PILE_LIMIT), 0.5, accuracy: 0.02)
    }
}
