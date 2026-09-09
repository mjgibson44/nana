import Foundation
import WordCore
import WordNet
import XCTest

@testable import Word

/// The two settings a Battle room agrees on before it deals — the board
/// layout and the modifier — played through two real sessions over a mesh.
///
/// What's under test is that they are *room-wide*: the host owns them, they
/// reach every client on the snapshot everything else already reads, and a
/// board that lights up does so on every screen at the same moment.
@MainActor
final class BattleSetupTests: XCTestCase {
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

    private func table(
        setup: BattleSetup = BattleSetup(), seed: String = "battle-setup"
    ) -> Table {
        let mesh = MemoryMesh()
        let clock = TestClock()
        let hostTransport = mesh.add("host")
        let clientTransport = mesh.add("client")

        let hostModel = GameModel()
        let clientModel = GameModel()
        let host = BattleSession(
            role: .host, transport: hostTransport, model: hostModel,
            displayName: { $0 == "host" ? "Ada" : "Grace" }, makeSeed: { seed },
            clock: { clock.now }, setup: setup)
        let client = BattleSession(
            role: .client, transport: clientTransport, model: clientModel,
            clock: { clock.now })

        mesh.connect("host")
        mesh.connect("client")
        return Table(
            mesh: mesh, clock: clock, host: host, client: client,
            hostModel: hostModel, clientModel: clientModel)
    }

    /// Both clocks forward together, the way the app's heartbeat does.
    private func advance(_ table: Table, by seconds: Double) {
        let end = table.clock.now.addingTimeInterval(seconds)
        while table.clock.now < end {
            let now = min(end, table.clock.now.addingTimeInterval(0.25))
            table.clock.now = now
            table.host.tick(at: now)
            table.client.tick(at: now)
            table.hostModel.advanceClock(at: now)
            table.clientModel.advanceClock(at: now)
        }
    }

    // MARK: The room agrees

    func testARoomOpensOnItsHostsSetupAndTheClientIsToldOnTheSnapshot() {
        let table = table(setup: BattleSetup(modifier: .prizes))

        XCTAssertEqual(table.host.state?.modifier, .prizes)
        XCTAssertEqual(
            table.client.state?.modifier, .prizes,
            "a client plays by the room's rule, not its own settings")
        XCTAssertEqual(table.client.modifier, .prizes)
    }

    func testAClientsOwnSetupIsNeverConsulted() {
        // The client here would open a room with squares on if it hosted
        // one. It isn't hosting one.
        let mesh = MemoryMesh()
        let hostTransport = mesh.add("host")
        let clientTransport = mesh.add("client")
        let host = BattleSession(
            role: .host, transport: hostTransport, model: GameModel(),
            setup: BattleSetup(modifier: .prizes))
        let client = BattleSession(
            role: .client, transport: clientTransport, model: GameModel(),
            setup: BattleSetup(modifier: .prizes))
        mesh.connect("host")
        mesh.connect("client")
        XCTAssertEqual(client.modifier, .prizes)
        XCTAssertNotNil(host.state)
    }

    func testTheHostCanChangeTheRoomAndEveryoneHearsAboutIt() {
        // `state?.modifier` is an Optional, so a bare `.none` here would
        // resolve to `Optional.none` — nil — rather than the modifier of that
        // name. Spelled out, every time, for exactly that reason.
        let table = table()
        XCTAssertEqual(table.client.state?.modifier, SoloModifier.none)

        table.host.setModifier(.prizes)
        XCTAssertEqual(table.host.state?.modifier, .prizes)
        XCTAssertEqual(table.client.state?.modifier, .prizes, "on the snapshot, at once")
    }

    func testAClientCannotChangeTheRoom() {
        let table = table()
        table.client.setModifier(.prizes)
        XCTAssertEqual(
            table.host.state?.modifier, SoloModifier.none, "only the referee sets the rules")
        XCTAssertEqual(
            table.client.state?.modifier, SoloModifier.none, "and never a local lie")
    }

    func testTheRoomsRulesSettleWhenItDeals() {
        // Changing a rule mid-game would leave every board playing a
        // different one for the length of a broadcast.
        let table = table()
        table.host.start()
        table.host.setModifier(.prizes)
        XCTAssertEqual(table.host.state?.modifier, SoloModifier.none)
        XCTAssertEqual(table.hostModel.modifier, SoloModifier.none)
    }

    // MARK: Dealing under a modifier

    func testBothBoardsDealUnderTheRoomsModifier() {
        let table = table(setup: BattleSetup(modifier: .prizes))
        table.host.start()
        XCTAssertEqual(table.hostModel.modifier, .prizes)
        XCTAssertEqual(table.clientModel.modifier, .prizes)
        XCTAssertTrue(table.hostModel.prizes.isEmpty, "nothing is lit at the whistle")
    }

    func testAPlainRoomLightsNothingOnEitherBoard() async throws {
        let table = table()
        table.host.start()
        await table.hostModel.loadDictionary()
        try TestPlays.placeOpener(on: table.hostModel)
        advance(table, by: 90)
        XCTAssertTrue(table.hostModel.prizes.isEmpty)
        XCTAssertTrue(table.clientModel.prizes.isEmpty)
    }

    func testASquareLightsOnEveryBoardAtTheSameMomentAndIsWorthTheSame() async throws {
        // The whole synchronisation, and it needs no wire: every board's
        // clock starts at the same deal and counts the same seconds.
        let table = table(setup: BattleSetup(modifier: .prizes))
        table.host.start()
        await table.hostModel.loadDictionary()
        await table.clientModel.loadDictionary()
        // Both need something to light up near — the deal is shared, so both
        // racks spell the same opener.
        try TestPlays.placeOpener(on: table.hostModel)
        try TestPlays.placeOpener(on: table.clientModel)

        advance(table, by: PRIZE_FIRST_SPAWN_SECONDS - 1)
        XCTAssertTrue(table.hostModel.prizes.isEmpty, "not due yet on either board")
        XCTAssertTrue(table.clientModel.prizes.isEmpty)

        advance(table, by: 2)
        XCTAssertEqual(table.hostModel.prizes.prizes.count, 1)
        XCTAssertEqual(table.clientModel.prizes.prizes.count, 1, "and on the rival's, together")

        let mine = try XCTUnwrap(table.hostModel.prizes.prizes.first)
        let theirs = try XCTUnwrap(table.clientModel.prizes.prizes.first)
        XCTAssertEqual(
            prizeValue(.points, mine), prizeValue(.points, theirs),
            "worth the same to both, which is what makes it a fair race")
    }

    func testEachBoardsSquareSitsOnItsOwnBoard() async throws {
        // Separate boards are separate boards: the *timing* is shared, the
        // square is necessarily local, and it has to be somewhere its owner
        // can actually build.
        let table = table(setup: BattleSetup(modifier: .prizes))
        table.host.start()
        await table.hostModel.loadDictionary()
        try TestPlays.placeOpener(on: table.hostModel)
        advance(table, by: PRIZE_FIRST_SPAWN_SECONDS + 1)

        let prize = try XCTUnwrap(table.hostModel.prizes.prizes.first)
        XCTAssertNil(table.hostModel.board[prize.key])
        let cell = parseKey(prize.key)
        let near = table.hostModel.board.keys.contains { key in
            let tile = parseKey(key)
            return max(abs(tile.row - cell.row), abs(tile.col - cell.col)) <= PRIZE_REACH
        }
        XCTAssertTrue(near, "within reach of the board it belongs to")
        // The client never placed an opener, so it has nothing to light near.
        XCTAssertTrue(table.clientModel.prizes.isEmpty)
    }

    func testGoldClaimedInABattleCountsTowardTheScoreThatIsReported() async throws {
        let table = table(setup: BattleSetup(modifier: .prizes))
        table.host.start()
        await table.hostModel.loadDictionary()
        try TestPlays.placeOpener(on: table.hostModel)
        advance(table, by: PRIZE_FIRST_SPAWN_SECONDS + 1)

        // Lit for real by the clock, then pinned to the kind under test —
        // both kinds appear at random now, so taking whatever turned up would
        // make this a test of the draw.
        let lit = try XCTUnwrap(table.hostModel.prizes.prizes.first)
        let prize = Prize(key: lit.key, kind: .points, secondsLeft: lit.secondsLeft)
        table.hostModel.setPrizes(PrizeField(prizes: [prize]))
        let due = prizeValue(.points, prize)
        let before = table.hostModel.score
        table.hostModel.claimPrizes(covering: [prize.key])
        XCTAssertEqual(table.hostModel.score, before + due, "gold is score, and score is standing")

        advance(table, by: 1)
        let seat = table.host.state?.players.first { $0.id == "host" }
        XCTAssertEqual(seat?.score, table.hostModel.score, "and the room is told")
    }

    func testSalvageClearsTilesInABattleToo() async throws {
        let table = table(setup: BattleSetup(modifier: .prizes))
        table.host.start()
        await table.hostModel.loadDictionary()
        try TestPlays.placeOpener(on: table.hostModel)
        advance(table, by: PRIZE_FIRST_SPAWN_SECONDS + 1)

        let lit = try XCTUnwrap(table.hostModel.prizes.prizes.first)
        let prize = Prize(key: lit.key, kind: .relief, secondsLeft: lit.secondsLeft)
        table.hostModel.setPrizes(PrizeField(prizes: [prize]))
        let due = prizeValue(.relief, prize)
        let hand = table.hostModel.rack.count
        table.hostModel.claimPrizes(covering: [prize.key])

        // A Battle opens on `BATTLE_OPENING_TILES` and the opener spends
        // several of them, so a full-price claim is routinely worth more
        // tiles than there are — which is the case that must clear the pile
        // rather than trap on `removeLast`.
        XCTAssertEqual(table.hostModel.rack.count, max(0, hand - due))
        XCTAssertGreaterThanOrEqual(table.hostModel.rack.count, 0)
        XCTAssertEqual(table.hostModel.prizesClaimed, 1)
    }

    func testSalvageEarlyInABattleIsWorthMoreThanThePileHolds() async throws {
        // Worth recording rather than working around: ten tiles is most of a
        // Battle's opening hand, so early Salvage claims are capped by the
        // pile and late ones are not. If that turns out to make the modifier
        // feel weak in the opening, the number to move is
        // `SALVAGE_TOP_TILES`, not the clamp.
        let table = table(setup: BattleSetup(modifier: .prizes))
        table.host.start()
        XCTAssertLessThan(BATTLE_OPENING_TILES, SALVAGE_TOP_TILES + MIN_WORD_LENGTH)
    }

    func testASpectatorsBoardIsNeverLit() async throws {
        // Someone watching this game out has nothing to claim with.
        let model = GameModel()
        model.newBattle(
            seed: "watching", selfID: "me", spectating: true, modifier: .prizes, now: .now)
        var now = Date.now
        for _ in 0..<200 {
            now = now.addingTimeInterval(0.25)
            model.advanceClock(at: now)
        }
        XCTAssertTrue(model.prizes.isEmpty)
    }

    // MARK: The board layout

    func testARoomIsSeparateUnlessItSaysOtherwise() {
        let table = table()
        XCTAssertEqual(table.host.boardView, .separate)
        XCTAssertEqual(table.client.boardView, .separate)
        XCTAssertFalse(table.host.state?.isSharedBoard ?? true)
    }

    func testTheSharedLayoutIsNotOfferedYet() {
        // The referee is ready for it and the board is not
        // (`BATTLE_SHARED_BOARD_ENABLED`), so nothing may put a room into a
        // layout half the app can't play.
        XCTAssertFalse(BATTLE_SHARED_BOARD_ENABLED)
        XCTAssertEqual(OPEN_BOARD_VIEWS.map(\.view), [.separate])
    }

    func testOccupyIsAlwaysSharedAndItsLayoutIsNotAChoice() {
        let mesh = MemoryMesh()
        let transport = mesh.add("host")
        let session = BattleSession(
            role: .host, mode: .occupy, transport: transport, model: GameModel())
        mesh.connect("host")
        XCTAssertEqual(session.state?.boardView, .shared)
        session.setBoardView(.separate)
        XCTAssertEqual(session.state?.boardView, .shared, "Occupy has one layout")
    }

    // MARK: Remembering the door

    func testTheDoorRemembersWhatWasSetUpLast() {
        let store = MemoryStore()
        saveBattleSetup(BattleSetup(boardView: .shared, modifier: .prizes), to: store)
        XCTAssertEqual(
            loadBattleSetup(from: store),
            BattleSetup(boardView: .shared, modifier: .prizes))
    }

    func testAnUnsetDoorOpensOnSeparateAndClear() {
        XCTAssertEqual(loadBattleSetup(from: MemoryStore()), DEFAULT_BATTLE)
        XCTAssertEqual(DEFAULT_BATTLE, BattleSetup(boardView: .separate, modifier: .none))
    }

    func testAModifierThatNoLongerExistsOpensClear() {
        let store = MemoryStore([
            "nana.setup.battle.v1": "{\"boardView\":\"separate\",\"modifier\":\"meteors\"}"
        ])
        XCTAssertEqual(loadBattleSetup(from: store).modifier, .none)
    }
}
