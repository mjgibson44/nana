import Foundation
import WordCore
import WordNet
import XCTest

@testable import Word

/// A whole Occupy game, played: two `BattleSession`s over a `MemoryMesh`,
/// one shared board, every word going through the host and coming back to
/// both screens.
@MainActor
final class OccupyPlayTests: XCTestCase {

    private final class TestClock: @unchecked Sendable {
        var now = Date(timeIntervalSinceReferenceDate: 0)
    }

    private struct Table {
        var mesh: MemoryMesh
        var clock: TestClock
        var host: BattleSession
        var client: BattleSession
        var hostModel: GameModel
        var clientModel: GameModel
    }

    private func table(seed: String = "occupy-seed-1") -> Table {
        let mesh = MemoryMesh()
        let clock = TestClock()
        let hostTransport = mesh.add("host")
        let clientTransport = mesh.add("client")

        let hostModel = GameModel()
        let clientModel = GameModel()
        let host = BattleSession(
            role: .host, mode: .occupy, transport: hostTransport, model: hostModel,
            displayName: { $0 == "host" ? "Ada" : "Grace" }, makeSeed: { seed },
            clock: { clock.now })
        let client = BattleSession(
            role: .client, mode: .occupy, transport: clientTransport, model: clientModel,
            clock: { clock.now })

        mesh.connect("host")
        mesh.connect("client")
        return Table(
            mesh: mesh, clock: clock, host: host, client: client,
            hostModel: hostModel, clientModel: clientModel)
    }

    /// A dealt game with both dictionaries in — the host's judges every
    /// word, the client's judges its own before sending.
    private func dealt(seed: String = "occupy-seed-1") async -> Table {
        let table = table(seed: seed)
        await table.hostModel.loadDictionary()
        await table.clientModel.loadDictionary()
        table.host.start()
        return table
    }

    /// Run the clocks forward together in short steps, so the host's pings
    /// keep both links fresh across a long stretch.
    private func advance(_ table: Table, by seconds: Double) {
        var left = seconds
        while left > 0 {
            let jump = min(5, left)
            let now = table.clock.now.addingTimeInterval(jump)
            table.clock.now = now
            table.host.tick(at: now)
            table.client.tick(at: now)
            table.hostModel.advanceClock(at: now)
            table.clientModel.advanceClock(at: now)
            left -= jump
        }
    }

    /// Spell any real word from the model's pile and confirm it as the
    /// opener, on a board that may already hold the other seat's words.
    @discardableResult
    private func open(on model: GameModel) throws -> String {
        guard let (word, indices) = TestPlays.spellableWord(in: model) else {
            throw XCTSkip("this pile can't spell an opener")
        }
        for index in indices { model.togglePick(index) }
        XCTAssertTrue(model.canConfirm, "\(word) should be confirmable")
        XCTAssertTrue(model.handle(.confirm))
        return word
    }

    // MARK: The lobby and the deal

    func testTheLobbyIsAnOccupyLobby() {
        let table = table()
        XCTAssertTrue(table.host.isOccupy)
        XCTAssertEqual(table.host.state?.mode, .occupy)
        XCTAssertEqual(table.client.state?.mode, .occupy)
        XCTAssertTrue(table.host.canStart, "two is enough")
    }

    func testStartingSeatsBothPlayersDiagonalWithFullHands() async {
        let table = await dealt()

        XCTAssertEqual(table.hostModel.mode, .occupy)
        XCTAssertEqual(table.clientModel.mode, .occupy)
        XCTAssertEqual(table.hostModel.occupySeat, 0)
        XCTAssertEqual(table.clientModel.occupySeat, 1)
        XCTAssertEqual(table.hostModel.bounds, Bounds(size: OCCUPY_SMALL_BOARD))
        XCTAssertEqual(table.clientModel.bounds, Bounds(size: OCCUPY_SMALL_BOARD))
        XCTAssertEqual(table.hostModel.startCell, Cell(row: 3, col: 3))
        XCTAssertEqual(
            table.clientModel.startCell, Cell(row: 3, col: 3),
            "the board is turned so every seat opens from its own top-left")
        XCTAssertEqual(table.hostModel.occupy?.rotation, .upright)
        XCTAssertEqual(table.clientModel.occupy?.rotation, .half)
        XCTAssertEqual(table.hostModel.rack.count, OCCUPY_HAND)
        XCTAssertEqual(table.clientModel.rack.count, OCCUPY_HAND)
        XCTAssertNotEqual(table.hostModel.rack, table.clientModel.rack, "private deals")
        XCTAssertTrue(table.hostModel.isFirstWord)
        XCTAssertTrue(table.clientModel.isFirstWord)
        XCTAssertNil(table.hostModel.secondsToNextTiles(at: table.clock.now), "no drip")
        XCTAssertEqual(table.hostModel.occupySecondsLeft(at: table.clock.now), OCCUPY_SHORT_SECONDS)
    }

    // MARK: Words on the shared board

    func testTheOpenerLandsOnBothBoardsInTheHostsColourAndRefillsThePile() async throws {
        let table = await dealt()
        let word = try open(on: table.hostModel)

        XCTAssertEqual(table.hostModel.board.count, word.count)
        XCTAssertEqual(
            table.clientModel.occupy?.view?.board, table.hostModel.occupy?.view?.board, "one board")
        XCTAssertEqual(
            table.clientModel.board, table.hostModel.board.rotated(size: OCCUPY_SMALL_BOARD, by: .half),
            "turned for the other seat")
        XCTAssertNotNil(table.hostModel.board[keyOf(3, 3)], "from the start square")
        XCTAssertNotNil(table.clientModel.board[keyOf(11, 11)], "bottom-right on the other screen")
        XCTAssertEqual(Set(table.clientModel.owners.values), [0], "the host's, on both screens")
        XCTAssertEqual(table.hostModel.occupy?.view?.owners, table.clientModel.occupy?.view?.owners)
        XCTAssertEqual(table.hostModel.rack.count, OCCUPY_HAND, "refilled on the spot")
        XCTAssertEqual(table.hostModel.occupy?.pending.count, 0, "answered")
        XCTAssertEqual(table.hostModel.score, word.count * word.count, "each tile worth its word")
        XCTAssertEqual(table.clientModel.occupyScores, table.hostModel.occupyScores)
        XCTAssertFalse(table.hostModel.isFirstWord)
        XCTAssertTrue(table.clientModel.isFirstWord, "the client still has to open")
        XCTAssertEqual(table.host.position, 1)
        XCTAssertEqual(table.client.position, 2)
    }

    func testTheOtherSeatsOpenerReadsForwardAtHomeAndBackwardOnTheHost() async throws {
        let table = await dealt()
        let word = try open(on: table.clientModel)

        // On the client's own screen: from its top-left start, heading right.
        for (offset, letter) in word.enumerated() {
            XCTAssertEqual(
                table.clientModel.board[keyOf(3, 3 + offset)], String(letter),
                "letter \(offset) of \(word), heading right at home")
        }
        // On the host's: from the bottom-right start, heading toward the
        // middle — which reads backwards there.
        for (offset, letter) in word.enumerated() {
            XCTAssertEqual(
                table.hostModel.board[keyOf(11, 11 - offset)], String(letter),
                "letter \(offset) of \(word), heading left on the host's board")
        }
        XCTAssertEqual(
            table.hostModel.occupy?.view?.board, table.clientModel.occupy?.view?.board, "one board")
        XCTAssertEqual(Set(table.hostModel.owners.values), [1])
        XCTAssertEqual(table.client.position, 1, "and it counts")
    }

    func testBorrowingARivalsLetterCapturesIt() async throws {
        let table = await dealt()
        try open(on: table.hostModel)
        let before = table.hostModel.score

        let (word, through) = try TestPlays.attachWord(on: table.clientModel)

        XCTAssertEqual(table.clientModel.owners[through], 1, "captured")
        XCTAssertEqual(
            table.hostModel.owners[rotateKey(through, size: OCCUPY_SMALL_BOARD, by: .half)], 1,
            "and the host agrees, on its own frame of the board")
        XCTAssertEqual(table.hostModel.occupy?.view?.board, table.clientModel.occupy?.view?.board)
        XCTAssertLessThan(table.hostModel.score, before, "the host lost the tile's value")
        XCTAssertGreaterThan(table.clientModel.score, 0)
        XCTAssertEqual(table.clientModel.rack.count, OCCUPY_HAND)
        XCTAssertEqual(table.clientModel.occupyWords.last?.word, word)
        XCTAssertFalse(table.clientModel.isFirstWord, "borrowing counts as opening")
    }

    // MARK: Clocks

    func testNothingDripsAndNobodyIsBuried() async {
        let table = await dealt()
        advance(table, by: 40)
        XCTAssertEqual(table.hostModel.rack.count, OCCUPY_HAND)
        XCTAssertFalse(table.hostModel.isComplete)
        XCTAssertEqual(table.hostModel.pileTone, .ok, "a full hand is normal here")
        XCTAssertEqual(table.hostModel.occupySecondsLeft(at: table.clock.now), OCCUPY_SHORT_SECONDS - 40)
    }

    func testTheStallCountdownShowsOnceTheBoardHasBeenQuiet() async {
        let table = await dealt()
        advance(table, by: 30)
        XCTAssertNil(table.hostModel.occupyStallSecondsLeft(at: table.clock.now), "the grace just ended")
        advance(table, by: 15)
        XCTAssertNil(table.hostModel.occupyStallSecondsLeft(at: table.clock.now), "45 left: not shown yet")
        advance(table, by: 30)
        XCTAssertEqual(table.hostModel.occupyStallSecondsLeft(at: table.clock.now), 15)
        XCTAssertEqual(table.clientModel.occupyStallSecondsLeft(at: table.clock.now), 15)
    }

    func testAStuckBoardEndsTheGameAndTheStandingsReadTheBoard() async throws {
        let table = await dealt()
        try open(on: table.hostModel)

        advance(table, by: OCCUPY_GRACE_SECONDS + OCCUPY_STALL_SECONDS - 1)
        XCTAssertFalse(table.hostModel.isComplete)
        advance(table, by: 1)

        XCTAssertEqual(table.host.state?.phase, .finished)
        XCTAssertEqual(table.host.state?.occupy?.end, .stall)
        XCTAssertTrue(table.hostModel.isComplete)
        XCTAssertTrue(table.clientModel.isComplete)
        XCTAssertEqual(table.hostModel.endReason, .battleOver)
        XCTAssertTrue(table.hostModel.battleWon)
        XCTAssertFalse(table.clientModel.battleWon)
        XCTAssertEqual(table.hostModel.outcome.report.battlePlayers, 2)
        XCTAssertEqual(table.hostModel.outcome.mode, .occupy)
        XCTAssertEqual(table.host.position, 1)
        XCTAssertEqual(table.client.position, 2)
        XCTAssertEqual(table.host.occupyStandings.map(\.player.id), ["host", "client"])
        XCTAssertEqual(table.host.occupyStandings.first?.value, table.hostModel.score)
        XCTAssertTrue(table.host.canRestart)
        XCTAssertEqual(table.hostModel.finalWords.count, 1, "the host's one word")
    }

    func testTheHostCanDealAnotherGameFromTheResults() async throws {
        let table = await dealt()
        try open(on: table.hostModel)
        advance(table, by: OCCUPY_GRACE_SECONDS + OCCUPY_STALL_SECONDS)
        XCTAssertEqual(table.host.state?.phase, .finished)

        table.host.restart()

        XCTAssertEqual(table.host.state?.phase, .playing)
        XCTAssertTrue(table.hostModel.board.isEmpty)
        XCTAssertTrue(table.clientModel.board.isEmpty)
        XCTAssertEqual(table.hostModel.rack.count, OCCUPY_HAND)
        XCTAssertFalse(table.hostModel.isComplete)
    }

    // MARK: Leaving

    func testLeavingUnhooksTheBoard() async {
        let table = await dealt()
        table.client.leave()
        XCTAssertNil(table.clientModel.onOccupyPlace)
        XCTAssertEqual(table.host.state?.phase, .finished, "the field emptied")
        XCTAssertEqual(table.host.state?.occupy?.end, .field)
        XCTAssertTrue(table.hostModel.battleWon)
    }

    func testAnotherModeClearsOccupyBehindIt() async {
        let table = await dealt()
        XCTAssertTrue(table.hostModel.isOccupy)
        table.hostModel.newGame(pace: .regular)
        XCTAssertFalse(table.hostModel.isOccupy)
        XCTAssertNil(table.hostModel.occupy)
        XCTAssertTrue(table.hostModel.owners.isEmpty)
        XCTAssertEqual(table.hostModel.bounds, boardBounds(TileMap()), "the board grows again")
    }
}

/// The model's own half of Occupy, without a network: a word shows the moment
/// it's let go of, and comes back off — tiles and all — if the host says no.
@MainActor
final class OccupyModelTests: XCTestCase {
    /// A seat-0 model on a fresh two-player board, with nobody to answer it.
    private func seated(seed: String = "occupy-model") async -> GameModel {
        let model = GameModel()
        model.newOccupy(
            seed: seed, selfID: "me", state: OccupyState(size: OCCUPY_SMALL_BOARD, seats: ["me", "them"]))
        await model.loadDictionary()
        return model
    }

    func testTheSeatDealsAFullHandOnTheFirstSnapshot() async {
        let model = await seated()
        XCTAssertEqual(model.occupySeat, 0)
        XCTAssertEqual(model.rack.count, OCCUPY_HAND)
        XCTAssertEqual(model.bounds, Bounds(size: OCCUPY_SMALL_BOARD))
        XCTAssertFalse(model.spectating)
    }

    func testAWordShowsAtOnceAndWaitsForTheHost() async throws {
        let model = await seated()
        var sent: [(Int, OccupyPlacement)] = []
        model.onOccupyPlace = { sent.append(($0, $1)) }

        let word = try TestPlays.placeOpener(on: model)

        XCTAssertEqual(model.board.count, word.count, "on the board already")
        XCTAssertEqual(model.occupy?.pending.count, 1, "but not answered for")
        XCTAssertEqual(sent.count, 1)
        XCTAssertEqual(sent.first?.1.tiles.count, word.count)
        XCTAssertTrue(sent.first?.1.borrowed.isEmpty == true)
        XCTAssertEqual(model.rack.count, OCCUPY_HAND, "refilled without waiting")
        XCTAssertEqual(model.score, word.count * word.count)

        model.confirmPlacement(serial: 1)
        XCTAssertEqual(model.occupy?.pending.count, 0)
        XCTAssertEqual(model.board.count, word.count, "nothing moved")
    }

    func testARefusedWordComesBackOffTheBoardAndIntoThePile() async throws {
        let model = await seated()
        let pileBefore = model.rack.sorted()
        let word = try TestPlays.placeOpener(on: model)
        XCTAssertNotEqual(model.rack.sorted(), pileBefore)

        model.refusePlacement(serial: 1, reason: "Someone got there first.")

        XCTAssertTrue(model.board.isEmpty, "taken back")
        XCTAssertEqual(model.occupy?.pending.count, 0)
        XCTAssertEqual(model.rack.count, OCCUPY_HAND)
        XCTAssertEqual(model.rack.sorted(), pileBefore, "the dealt letters went back, the spent ones returned")
        XCTAssertEqual(model.toast?.text, "Someone got there first.")
        XCTAssertEqual(model.pickList.compactMap(\.letter).joined(), word, "back in the row to try again")
        XCTAssertEqual(model.score, 0)
        XCTAssertTrue(model.isFirstWord)
    }

    func testTheHostsBoardShowsUnderThisSeatsWaitingWords() async throws {
        let model = await seated()
        let word = try TestPlays.placeOpener(on: model)

        // Meanwhile the rival opened from their corner; the host's snapshot
        // carries their word and not ours yet.
        var theirs = OccupyState(size: OCCUPY_SMALL_BOARD, seats: ["me", "them"])
        for (offset, letter) in "star".enumerated() {
            theirs.board[keyOf(11, 8 + offset)] = String(letter)
            theirs.owners[keyOf(11, 8 + offset)] = 1
        }
        theirs.opened = [false, true]
        theirs.scores = [0, 16]
        model.adoptOccupy(theirs)

        XCTAssertEqual(model.board.count, word.count + 4, "theirs under ours")
        XCTAssertEqual(model.owners[keyOf(11, 11)], 1)
        XCTAssertEqual(model.owners[keyOf(3, 3)], 0)
        XCTAssertEqual(model.occupyScores, [word.count * word.count, 16])
        XCTAssertFalse(model.isFirstWord, "our opener is still counted, pending or not")
    }

    func testASeatSeesTheBoardTurnedSoItsCornerIsTopLeft() async throws {
        // Seat 1: bottom-right on the host's board, top-left on this screen.
        let model = GameModel()
        model.newOccupy(
            seed: "occupy-turned", selfID: "me",
            state: OccupyState(size: OCCUPY_SMALL_BOARD, seats: ["them", "me"]))
        await model.loadDictionary()
        var sent: [(Int, OccupyPlacement)] = []
        model.onOccupyPlace = { sent.append(($0, $1)) }
        XCTAssertEqual(model.occupySeat, 1)
        XCTAssertEqual(model.occupy?.rotation, .half)
        XCTAssertEqual(model.startCell, Cell(row: 3, col: 3), "everyone opens from their own top-left")

        let word = try TestPlays.placeOpener(on: model)
        for (offset, letter) in word.enumerated() {
            XCTAssertEqual(model.board[keyOf(3, 3 + offset)], String(letter), "rightward at home")
        }
        let placement = try XCTUnwrap(sent.first?.1)
        XCTAssertEqual(
            placement.tiles[keyOf(11, 11)], String(word.first!),
            "sent in the host's frame: on the start square, heading toward the middle")
        XCTAssertEqual(placement.tiles[keyOf(11, 11 - (word.count - 1))], String(word.last!))

        // Their STAR at the host's (3,3…6) shows bottom-right here, backwards.
        var theirs = OccupyState(size: OCCUPY_SMALL_BOARD, seats: ["them", "me"])
        for (offset, letter) in "star".enumerated() {
            theirs.board[keyOf(3, 3 + offset)] = String(letter)
            theirs.owners[keyOf(3, 3 + offset)] = 0
        }
        theirs.opened = [true, false]
        theirs.scores = [16, 0]
        model.adoptOccupy(theirs)

        XCTAssertEqual(model.board[keyOf(11, 11)], "s")
        XCTAssertEqual(model.board[keyOf(11, 8)], "r")
        XCTAssertEqual(model.owners[keyOf(11, 11)], 0)
        XCTAssertEqual(model.owners[keyOf(3, 3)], 1, "ours, still pending, top-left")
        XCTAssertEqual(model.board.count, word.count + 4)
    }

    func testASeatNotDealtInWatches() {
        let model = GameModel()
        model.newOccupy(
            seed: "watch", selfID: "late",
            state: OccupyState(size: OCCUPY_SMALL_BOARD, seats: ["a", "b"]))
        XCTAssertTrue(model.spectating)
        XCTAssertNil(model.occupySeat)
        XCTAssertTrue(model.rack.isEmpty)
    }

    func testAnOccupyGameIsNeverSaved() {
        let model = GameModel()
        model.newOccupy(seed: "occupy", selfID: "me")
        XCTAssertNil(model.savedGame(), "host-driven; nothing to come back to")
    }
}
