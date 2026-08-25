import Foundation
import WordCore
import WordNet
import XCTest

@testable import Word

/// A whole battle, played. Two `BattleSession`s over a `MemoryMesh` are two
/// devices in a match — which is what makes the GKMatch adapter a drop-in
/// rather than the thing everything else waits on (plan §7.5).
@MainActor
final class BattlePlayTests: XCTestCase {

    /// A host and a client wired to one mesh, each with its own board.
    /// A clock the test moves by hand, shared by both sessions and both
    /// boards — the same instant everywhere, which is what lets a whole
    /// battle play out in milliseconds.
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

    private func table(seed: String = "battle-seed-1") -> Table {
        let mesh = MemoryMesh()
        let clock = TestClock()
        let hostTransport = mesh.add("host")
        let clientTransport = mesh.add("client")

        let hostModel = GameModel()
        let clientModel = GameModel()
        let host = BattleSession(
            role: .host, transport: hostTransport, model: hostModel,
            displayName: { $0 == "host" ? "Ada" : "Grace" }, makeSeed: { seed },
            clock: { clock.now })
        let client = BattleSession(
            role: .client, transport: clientTransport, model: clientModel,
            clock: { clock.now })

        mesh.connect("host")
        mesh.connect("client")
        return Table(
            mesh: mesh, clock: clock, host: host, client: client,
            hostModel: hostModel, clientModel: clientModel)
    }

    /// Run both clocks forward together, the way the app's heartbeat does.
    private func advance(_ table: Table, by seconds: Double) {
        let now = table.clock.now.addingTimeInterval(seconds)
        table.clock.now = now
        table.host.tick(at: now)
        table.client.tick(at: now)
        table.hostModel.advanceClock(at: now)
        table.clientModel.advanceClock(at: now)
    }

    // MARK: The lobby

    func testTheClientFindsTheHostAndTakesASeat() {
        let table = table()
        XCTAssertEqual(table.client.hostID, "host", "the announcement names the referee")
        XCTAssertEqual(table.host.state?.players.count, 2)
        XCTAssertEqual(table.client.state?.players.count, 2)
        XCTAssertEqual(table.client.selfSeat?.name, "Grace")
        XCTAssertTrue(table.host.isHost)
        XCTAssertFalse(table.client.isHost)
    }

    func testABattleNeedsTwoBeforeItCanStart() {
        let mesh = MemoryMesh()
        let transport = mesh.add("host")
        let model = GameModel()
        let host = BattleSession(role: .host, transport: transport, model: model)
        mesh.connect("host")
        XCTAssertFalse(host.canStart, "one player is not a battle")

        let clientTransport = mesh.add("client")
        // Held: a discarded session deallocates, and its transport handlers go
        // weak with it, so the seat would never be claimed.
        let client = BattleSession(
            role: .client, transport: clientTransport, model: GameModel())
        mesh.connect("client")
        XCTAssertTrue(host.canStart)
        XCTAssertEqual(client.state?.players.count, 2)
    }

    // MARK: The deal

    func testStartingDealsBothPlayersTheSameLetters() {
        let table = table()
        table.host.start()

        XCTAssertEqual(table.host.state?.phase, .playing)
        XCTAssertEqual(table.hostModel.rack.count, BATTLE_START_TILES)
        XCTAssertEqual(
            table.hostModel.rack, table.clientModel.rack,
            "one seed, one shared stream — the whole point")
        XCTAssertEqual(table.hostModel.mode, .battle)
        XCTAssertTrue(table.hostModel.boardLocked, "words are permanent in a battle")
    }

    func testTheDripLandsTheSameBatchOnBothBoards() {
        let table = table()
        table.host.start()
        let opening = table.hostModel.rack.count

        advance(table, by: Double(BATTLE_DRIP_SECONDS) + 1)

        XCTAssertGreaterThan(table.hostModel.rack.count, opening)
        XCTAssertEqual(
            table.hostModel.rack, table.clientModel.rack,
            "drip k is drip k on every screen")
    }

    func testADripIsIndexedSoADelayedClientStaysInStep() {
        // A backgrounded player gets one batch, not every batch they missed —
        // and still draws the same letters, because the size is pure in the
        // index rather than the wall clock.
        var run = BattleRun(startedAt: Date(timeIntervalSinceReferenceDate: 0))
        let first = run.advance(at: Date(timeIntervalSinceReferenceDate: 1_000))
        XCTAssertEqual(first, battleDripTilesAt(dripIndex: 0))
        XCTAssertEqual(run.dripIndex, 1)
        let second = run.advance(at: Date(timeIntervalSinceReferenceDate: 1_001))
        XCTAssertNil(second, "one drip per tick, however long the gap")
    }

    // MARK: Attacks

    func testAWordSendsTilesToTheRivalWithoutPuttingLettersOnTheWire() throws {
        let table = table()
        table.host.start()
        let before = table.clientModel.rack.count

        // The host plays a word worth an attack.
        try playWord(on: table.hostModel, length: 5)
        advance(table, by: 1)

        XCTAssertGreaterThan(
            table.clientModel.rack.count, before, "the rival's pile grew")
        // The letters were drawn locally from a private stream, so they are
        // *not* the host's letters.
        let hostAttackStream = TileStream(seed: "battle-seed-1/attacks/client")
        let expected = hostAttackStream.next(table.clientModel.rack.count - before)
        XCTAssertEqual(Array(table.clientModel.rack.suffix(expected.count)), expected)
    }

    func testExtendingAWordOnlyPaysForTheGrowth() {
        // HEART → HEARTS earns the S, not the whole word again. Priced by the
        // pure rule; this pins that the model passes `grewFrom` at all.
        let full = battleAttackTiles(wordLength: 6, round: 1, grewFrom: [])
        let grown = battleAttackTiles(wordLength: 6, round: 1, grewFrom: [5])
        XCTAssertGreaterThan(full, grown)
    }

    // MARK: Burial

    func testOverflowingThePileEndsThatPlayersGame() {
        let table = table()
        table.host.start()

        // Bury the client under a heavy attack.
        table.clientModel.receiveAttack(BATTLE_PILE_LIMIT)

        XCTAssertTrue(table.clientModel.isComplete)
        XCTAssertEqual(table.clientModel.endReason, .buried)
        XCTAssertFalse(table.hostModel.isComplete, "the battle plays on for everyone else")
    }

    func testABuriedPlayerBecomesASpectatorAndTakesNoMoreTiles() {
        let table = table()
        table.host.start()
        table.clientModel.receiveAttack(BATTLE_PILE_LIMIT)
        XCTAssertTrue(table.client.isSpectating)

        let buriedPile = table.clientModel.rack.count
        table.clientModel.receiveAttack(5)
        XCTAssertEqual(table.clientModel.rack.count, buriedPile, "a dead board takes no tiles")
    }

    func testTheHostSeesTheRivalFallAndDeclaresAWinner() {
        let table = table()
        table.host.start()

        table.clientModel.receiveAttack(BATTLE_PILE_LIMIT)
        advance(table, by: 1)

        let seat = table.host.state?.players.first { $0.id == "client" }
        XCTAssertEqual(seat?.buried, true)
        XCTAssertEqual(table.host.state?.phase, .finished)
        XCTAssertEqual(table.host.state?.winnerId, "host")
    }

    // MARK: Spectating

    func testAPlayerJoiningMidGameWaitsOutTheRound() {
        let table = table()
        table.host.start()

        let lateTransport = table.mesh.add("late")
        let lateModel = GameModel()
        let late = BattleSession(role: .client, transport: lateTransport, model: lateModel)
        table.mesh.connect("late")

        XCTAssertEqual(late.selfSeat?.waiting, true, "seated, but not for this game")
    }

    // MARK: Leaving

    func testLeavingStopsTheClockAndUnhooksTheBoard() {
        let table = table()
        table.host.start()
        table.client.leave()
        XCTAssertNil(table.clientModel.onBattleAttack)
    }

    func testAnotherModeClearsTheBattleBehindIt() {
        let table = table()
        table.host.start()
        XCTAssertTrue(table.hostModel.isBattle)

        table.hostModel.newGame(pace: .regular)
        XCTAssertFalse(table.hostModel.isBattle)
        XCTAssertFalse(table.hostModel.boardLocked, "solo boards are editable again")
        XCTAssertNil(table.hostModel.battle)
    }

    // MARK: Helpers

    /// Play any real word of `length` from the model's rack. Battle boards are
    /// locked, so only real words land — which makes this the honest way to
    /// exercise the attack path.
    private func playWord(on model: GameModel, length: Int) throws {
        // The dictionary has to be in before a locked board will accept
        // anything.
        let expectation = expectation(description: "dictionary")
        Task { await model.loadDictionary(); expectation.fulfill() }
        wait(for: [expectation], timeout: 10)
        let dictionary = try XCTUnwrap(model.dictionary)

        let rack = model.rack
        for combo in orderedPicks(from: Array(rack.indices), choose: length) {
            let word = combo.map { rack[$0] }.joined()
            guard dictionary.contains(word) else { continue }
            for index in combo { model.togglePick(index) }
            if model.handle(.confirm), model.board.count >= length { return }
            model.handle(.escape)
        }
        throw XCTSkip("this rack can't spell a \(length)-letter word")
    }

    private func orderedPicks(from items: [Int], choose k: Int) -> [[Int]] {
        guard k > 0 else { return [[]] }
        var result: [[Int]] = []
        for (offset, item) in items.enumerated() {
            var rest = items
            rest.remove(at: offset)
            for tail in orderedPicks(from: rest, choose: k - 1) {
                result.append([item] + tail)
                if result.count > 3_000 { return result }
            }
        }
        return result
    }
}
