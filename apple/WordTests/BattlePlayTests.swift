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

    /// A clock the test moves by hand, shared by both sessions and both
    /// boards — the same instant everywhere, which is what lets a whole
    /// battle play out in milliseconds.
    private final class TestClock: @unchecked Sendable {
        var now = Date(timeIntervalSinceReferenceDate: 0)
    }

    /// A host and a client wired to one mesh, each with its own board.
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
        XCTAssertEqual(table.hostModel.rack.count, BATTLE_OPENING_TILES)
        XCTAssertEqual(
            table.hostModel.rack, table.clientModel.rack,
            "one seed, one shared stream — the whole point")
        XCTAssertEqual(table.hostModel.mode, .battle)
        XCTAssertEqual(table.host.position, 1, "everyone starts level")
        XCTAssertEqual(table.client.position, 1)
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

    func testAWordSendsTilesToTheRivalWithoutPuttingLettersOnTheWire() async throws {
        let table = table()
        table.host.start()
        let before = table.clientModel.rack.count

        // The host plays a word worth an attack.
        try await playWord(on: table.hostModel, length: 5)
        advance(table, by: 1)

        XCTAssertGreaterThan(
            table.clientModel.rack.count, before, "the rival's pile grew")
        XCTAssertGreaterThan(table.hostModel.attackTilesSent, 0)
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
        table.clientModel.receiveAttack(PILE_LIMIT)

        XCTAssertTrue(table.clientModel.isComplete)
        XCTAssertEqual(table.clientModel.endReason, .buried)
        XCTAssertFalse(table.hostModel.isComplete, "the battle plays on for everyone else")
    }

    func testABuriedPlayerBecomesASpectatorAndTakesNoMoreTiles() {
        let table = table()
        table.host.start()
        table.clientModel.receiveAttack(PILE_LIMIT)
        XCTAssertTrue(table.client.isSpectating)

        let buriedPile = table.clientModel.rack.count
        table.clientModel.receiveAttack(5)
        XCTAssertEqual(table.clientModel.rack.count, buriedPile, "a dead board takes no tiles")
    }

    func testTheHostSeesTheRivalFallAndDeclaresAWinner() {
        let table = table()
        table.host.start()

        table.clientModel.receiveAttack(PILE_LIMIT)
        advance(table, by: 1)

        let seat = table.host.state?.players.first { $0.id == "client" }
        XCTAssertEqual(seat?.buried, true)
        XCTAssertEqual(table.host.state?.phase, .finished)
        XCTAssertEqual(table.host.state?.winnerId, "host")
    }

    func testADecidedBattleFinishesTheWinnersBoardToo() {
        let table = table()
        table.host.start()

        table.clientModel.receiveAttack(PILE_LIMIT)
        advance(table, by: 1)

        // The winner's board is frozen and reported as a win; the loser's
        // stays the burial it already was.
        XCTAssertTrue(table.hostModel.isComplete)
        XCTAssertEqual(table.hostModel.endReason, .battleOver)
        XCTAssertTrue(table.hostModel.battleWon)
        XCTAssertTrue(table.hostModel.outcome.report.battleWon)
        XCTAssertEqual(table.hostModel.outcome.report.battlePlayers, 2)
        XCTAssertEqual(table.clientModel.endReason, .buried)
        XCTAssertFalse(table.clientModel.battleWon)

        // The placings the results show.
        XCTAssertEqual(table.host.position, 1)
        XCTAssertEqual(table.client.position, 2)
        XCTAssertTrue(table.host.selfWon)
        XCTAssertTrue(table.host.canRestart, "two seats are still filled")
        XCTAssertFalse(table.client.canRestart, "only the host deals again")
    }

    func testTheHostCanDealAnotherGameFromTheResults() {
        let table = table()
        table.host.start()
        table.clientModel.receiveAttack(PILE_LIMIT)
        advance(table, by: 1)
        XCTAssertEqual(table.host.state?.phase, .finished)

        table.host.restart()

        XCTAssertEqual(table.host.state?.phase, .playing)
        XCTAssertFalse(table.hostModel.isComplete)
        XCTAssertFalse(table.clientModel.isComplete)
        XCTAssertEqual(table.hostModel.rack, table.clientModel.rack)
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
        XCTAssertNil(table.hostModel.battle)
    }

    // MARK: A match nobody opened

    /// A random match's field: every session starts as a client on one mesh,
    /// with the rule that will deal it and the short claim window.
    @MainActor
    private struct Field {
        var mesh: MemoryMesh
        var clock: TestClock
        var sessions: [PlayerID: BattleSession]
        var models: [PlayerID: GameModel]
        var starts: [PlayerID: Int]
        var countdowns: [PlayerID: Int]
        var abandoned: [PlayerID: Int]

        var hosts: [PlayerID] { sessions.filter { $0.value.isHost }.map(\.key).sorted() }
        subscript(_ id: PlayerID) -> BattleSession { sessions[id]! }
    }

    private func field(
        _ rule: AutoStartRule, ids: [PlayerID], seed: String = "random-seed"
    ) -> Field {
        var field = Field(
            mesh: MemoryMesh(), clock: TestClock(), sessions: [:], models: [:],
            starts: [:], countdowns: [:], abandoned: [:])
        // The order of `ids` is the order of arrival; the mesh is connected
        // in that order too, once every session exists.
        for id in ids { seat(id, in: &field, rule: rule, seed: seed) }
        for id in ids { field.mesh.connect(id) }
        return field
    }

    /// A session that arrives at an existing field — a party's late arrival.
    private func arrive(_ id: PlayerID, in field: inout Field, rule: AutoStartRule) {
        seat(id, in: &field, rule: rule, seed: "random-seed")
        field.mesh.connect(id)
    }

    private func seat(_ id: PlayerID, in field: inout Field, rule: AutoStartRule, seed: String) {
        let transport = field.mesh.add(id)
        let model = GameModel()
        let clock = field.clock
        let session = BattleSession(
            role: .client, transport: transport, model: model,
            displayName: { $0.capitalized }, makeSeed: { seed },
            clock: { clock.now }, autoStart: rule,
            announceTimeout: HOST_CLAIM_TIMEOUT_SECONDS)
        field.sessions[id] = session
        field.models[id] = model
        field.starts[id] = 0
        field.countdowns[id] = 0
        field.abandoned[id] = 0
    }

    /// Wire the counters up. Done after the field is built so the closures
    /// can write into a box rather than a struct copy.
    private final class Tally {
        var starts: [PlayerID: Int] = [:]
        var countdowns: [PlayerID: Int] = [:]
        var abandoned: [PlayerID: Int] = [:]
    }

    private func tally(_ field: Field) -> Tally {
        let tally = Tally()
        for (id, session) in field.sessions {
            session.onGameStart = { tally.starts[id, default: 0] += 1 }
            session.onCountdownBegin = { tally.countdowns[id, default: 0] += 1 }
            session.onAbandoned = { tally.abandoned[id, default: 0] += 1 }
        }
        return tally
    }

    /// Run every session's clock forward together in half-second ticks, the
    /// cadence of the app's heartbeat — the claim window, the re-announce
    /// and the countdown are all tick-driven.
    private func advance(_ field: Field, by seconds: Double) {
        var elapsed = 0.0
        while elapsed < seconds {
            let step = min(0.5, seconds - elapsed)
            elapsed += step
            let now = field.clock.now.addingTimeInterval(step)
            field.clock.now = now
            for id in field.sessions.keys.sorted() {
                field.sessions[id]?.tick(at: now)
                field.models[id]?.advanceClock(at: now)
            }
        }
    }

    func testTwoClientsElectAHostWithoutAnAnnouncement() {
        let field = field(.duel, ids: ["bea", "ann"])
        XCTAssertTrue(field.hosts.isEmpty, "nobody opened this room")

        advance(field, by: HOST_CLAIM_TIMEOUT_SECONDS + 0.5)

        XCTAssertEqual(field.hosts, ["ann"], "the lowest id takes the chair")
        XCTAssertEqual(field["bea"].hostID, "ann")
        XCTAssertEqual(field["ann"].state?.players.map(\.id).sorted(), ["ann", "bea"])
        XCTAssertEqual(field["bea"].state?.players.count, 2)
        XCTAssertFalse(field["ann"].canStart, "a random match has no START")
    }

    func testADuelDealsItselfAfterTheCountdown() {
        let field = field(.duel, ids: ["bea", "ann"])
        let tally = tally(field)

        advance(field, by: HOST_CLAIM_TIMEOUT_SECONDS + 0.5)
        XCTAssertEqual(field["ann"].countdown, START_COUNTDOWN_SECONDS)
        XCTAssertEqual(field["bea"].countdown, START_COUNTDOWN_SECONDS, "both screens count")

        advance(field, by: Double(START_COUNTDOWN_SECONDS))
        XCTAssertEqual(field["ann"].state?.phase, .playing)
        XCTAssertEqual(tally.starts["ann"], 1)
        XCTAssertEqual(tally.starts["bea"], 1)
        XCTAssertEqual(field.models["ann"]?.mode, .battle)
        XCTAssertEqual(
            field.models["ann"]?.rack, field.models["bea"]?.rack,
            "one seed, one shared stream")
        XCTAssertNil(field["ann"].countdown)
    }

    func testCountdownBeginFiresOnceOnEveryDevice() {
        let field = field(.duel, ids: ["bea", "ann"])
        let tally = tally(field)
        advance(field, by: HOST_CLAIM_TIMEOUT_SECONDS + Double(START_COUNTDOWN_SECONDS) + 1)
        XCTAssertEqual(tally.countdowns["ann"], 1)
        XCTAssertEqual(tally.countdowns["bea"], 1)
    }

    func testAPartyHoldsTheDoorTwentySecondsAfterTheLastArrival() {
        var field = field(.party, ids: ["cal", "ann", "bea"])
        advance(field, by: HOST_CLAIM_TIMEOUT_SECONDS + 0.5)
        XCTAssertEqual(field.hosts, ["ann"])
        XCTAssertEqual(field["ann"].state?.players.count, 3)
        XCTAssertNil(field["ann"].countdown, "the door is open")

        // Someone else lands twelve seconds in: the clock restarts.
        advance(field, by: 12)
        arrive("dan", in: &field, rule: .party)
        advance(field, by: 0.5)
        XCTAssertEqual(field["dan"].hostID, "ann", "told who referees on arrival")
        XCTAssertEqual(field["ann"].state?.players.count, 4)

        advance(field, by: PARTY_IDLE_SECONDS - 1.5)
        XCTAssertNil(field["ann"].countdown)
        advance(field, by: 1.5)
        XCTAssertEqual(field["ann"].countdown, START_COUNTDOWN_SECONDS)
        XCTAssertEqual(field["dan"].countdown, START_COUNTDOWN_SECONDS)

        advance(field, by: Double(START_COUNTDOWN_SECONDS))
        XCTAssertEqual(field["ann"].state?.phase, .playing)
        XCTAssertEqual(field["dan"].state?.phase, .playing)
        XCTAssertEqual(field.models["dan"]?.rack, field.models["cal"]?.rack)
    }

    func testTheCountdownCancelsWhenAnOpponentLeavesAndTheHostIsThenAbandoned() {
        let field = field(.duel, ids: ["bea", "ann"])
        let tally = tally(field)
        advance(field, by: HOST_CLAIM_TIMEOUT_SECONDS + 0.5)
        XCTAssertNotNil(field["ann"].countdown)

        field["bea"].leave()
        advance(field, by: 0.5)
        XCTAssertNil(field["ann"].countdown)
        XCTAssertEqual(field["ann"].state?.phase, .lobby)
        XCTAssertEqual(field["ann"].state?.players.map(\.id), ["ann"])

        // Alone with the door shut: the app is told once to search again.
        advance(field, by: BattleSession.aloneSeconds - 1)
        XCTAssertEqual(tally.abandoned["ann"], nil)
        advance(field, by: 2)
        XCTAssertEqual(tally.abandoned["ann"], 1)
        advance(field, by: 10)
        XCTAssertEqual(tally.abandoned["ann"], 1, "told once")
        XCTAssertEqual(tally.starts["ann"], nil, "never dealt a game against no one")
    }

    func testAHostLeavingTheLobbyIsReplaced() {
        let field = field(.party, ids: ["ann", "bea", "cal"])
        advance(field, by: HOST_CLAIM_TIMEOUT_SECONDS + 0.5)
        XCTAssertEqual(field.hosts, ["ann"])

        field["ann"].leave()
        advance(field, by: HOST_CLAIM_TIMEOUT_SECONDS + 0.5)

        // Ann's session is gone from the mesh; the app drops it. Of those
        // still in the room, exactly one referees.
        XCTAssertEqual(field.hosts.filter { $0 != "ann" }, ["bea"], "the lowest id left takes over")
        XCTAssertEqual(field["cal"].hostID, "bea")
        XCTAssertEqual(field["bea"].state?.players.map(\.id).sorted(), ["bea", "cal"])
        XCTAssertFalse(field["cal"].isReconnecting, "a lobby loss is not a reconnection")
    }

    func testTwoHostsConvergeOnTheLowestID() {
        // The race a party's backfill can lose: a newcomer with a lower id
        // claims the chair before it hears the established host. Lowest id
        // wins on every device, so the two lobbies fold into one.
        let mesh = MemoryMesh()
        let clock = TestClock()
        let seed = "random-seed"
        func session(_ id: PlayerID, role: BattleSession.Role) -> BattleSession {
            BattleSession(
                role: role, transport: mesh.add(id), model: GameModel(),
                displayName: { $0 }, makeSeed: { seed }, clock: { clock.now },
                autoStart: .party, announceTimeout: HOST_CLAIM_TIMEOUT_SECONDS)
        }
        let mmm = session("mmm", role: .host)
        let zzz = session("zzz", role: .client)
        mesh.connect("mmm")
        mesh.connect("zzz")
        XCTAssertEqual(zzz.hostID, "mmm")

        // A newcomer that already believes it's hosting.
        let aaa = session("aaa", role: .host)
        mesh.connect("aaa")
        for _ in 0..<6 {
            clock.now = clock.now.addingTimeInterval(0.5)
            for s in [aaa, mmm, zzz] { s.tick(at: clock.now) }
        }

        XCTAssertTrue(aaa.isHost)
        XCTAssertFalse(mmm.isHost, "the higher id stood down")
        XCTAssertEqual(mmm.hostID, "aaa")
        XCTAssertEqual(zzz.hostID, "aaa", "the client followed the lower announcer")
        XCTAssertEqual(aaa.state?.players.map(\.id).sorted(), ["aaa", "mmm", "zzz"])
        XCTAssertEqual(zzz.state?.players.count, 3)
    }

    func testLeavingDisconnectsTheTransport() {
        let field = field(.duel, ids: ["bea", "ann"])
        advance(field, by: HOST_CLAIM_TIMEOUT_SECONDS + 0.5)

        field["bea"].leave()
        XCTAssertFalse(
            field.mesh.transport(for: "ann")?.remotePlayerIDs.contains("bea") ?? true,
            "everyone else sees the seat empty at once")
        XCTAssertEqual(field["ann"].state?.players.map(\.id), ["ann"])
    }

    // MARK: Helpers

    /// Play any real word of `length` from the model's rack as the opener.
    private func playWord(on model: GameModel, length: Int) async throws {
        // The dictionary has to be in before anything is allowed down.
        await model.loadDictionary()
        guard let (_, indices) = TestPlays.spellableWord(in: model, lengths: [length]) else {
            throw XCTSkip("this rack can't spell a \(length)-letter word")
        }
        for index in indices { model.togglePick(index) }
        XCTAssertTrue(model.handle(.confirm))
        XCTAssertEqual(model.board.count, length)
    }
}
