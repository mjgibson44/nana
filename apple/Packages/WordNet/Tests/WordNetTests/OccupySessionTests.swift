import Foundation
import Testing
import WordCore

@testable import WordNet

/// Occupy over the wire: the host seats everyone on one board, judges every
/// word against it, answers each sender after the snapshot, and ends the game
/// on its own two clocks. Played over a `MemoryMesh`, like the battle tests.

private let words: Set<String> = [
    "cat", "cats", "tea", "eat", "ate", "star", "stare", "rest", "art", "rat", "tar", "set",
]

/// A word laid across from `at`, as a placement.
private func across(_ word: String, from cell: Cell, borrowing: [CellKey] = []) -> OccupyPlacement {
    var tiles: [CellKey: String] = [:]
    for (offset, letter) in word.enumerated() {
        let key = keyOf(cell.row, cell.col + offset)
        if !borrowing.contains(key) { tiles[key] = String(letter) }
    }
    return OccupyPlacement(tiles: tiles, borrowed: borrowing)
}

private func down(_ word: String, from cell: Cell, borrowing: [CellKey] = []) -> OccupyPlacement {
    var tiles: [CellKey: String] = [:]
    for (offset, letter) in word.enumerated() {
        let key = keyOf(cell.row + offset, cell.col)
        if !borrowing.contains(key) { tiles[key] = String(letter) }
    }
    return OccupyPlacement(tiles: tiles, borrowed: borrowing)
}

@MainActor
final class OccupyLobby {
    let mesh = MemoryMesh()
    let host: HostSession
    let hostTransport: MemoryTransport
    private(set) var clients: [PlayerID: ClientSession] = [:]

    /// What each seat's game layer heard, in order: "state", "placed:N" or
    /// "refused:N:reason".
    private(set) var heard: [PlayerID: [String]] = [:]
    private(set) var rejections: [PlayerID: [String]] = [:]

    private let simulated = SimulatedClock(Date(timeIntervalSince1970: 1_000))

    var now: Date {
        get { simulated.now }
        set { simulated.now = newValue }
    }

    init() {
        hostTransport = mesh.add("host")
        host = HostSession(
            transport: hostTransport,
            displayName: { "Player \($0)" },
            makeSeed: { "occupy-seed" },
            clock: { [simulated] in simulated.now },
            rules: .occupy(isWord: { words.contains($0) }))
        host.events.onState = { [weak self] _ in self?.heard["host", default: []].append("state") }
        host.events.onPlaced = { [weak self] serial in
            self?.heard["host", default: []].append("placed:\(serial)")
        }
        host.events.onRefused = { [weak self] serial, reason in
            self?.heard["host", default: []].append("refused:\(serial):\(reason)")
        }
        mesh.connect("host")
        host.announceHost()
    }

    @discardableResult
    func addClient(_ id: PlayerID) -> ClientSession {
        let transport = mesh.add(id)
        let client = ClientSession(transport: transport, clock: { [simulated] in simulated.now })
        client.events.onState = { [weak self] _ in self?.heard[id, default: []].append("state") }
        client.events.onPlaced = { [weak self] serial in
            self?.heard[id, default: []].append("placed:\(serial)")
        }
        client.events.onRefused = { [weak self] serial, reason in
            self?.heard[id, default: []].append("refused:\(serial):\(reason)")
        }
        client.events.onRejected = { [weak self] reason in
            self?.rejections[id, default: []].append(reason)
        }
        clients[id] = client
        mesh.connect(id)
        return client
    }

    /// Run the clocks forward in short steps, so the host's pings keep every
    /// seat's link fresh — a single long jump would read as everyone gone
    /// stale, which is a different ending.
    func advance(_ seconds: TimeInterval, step: TimeInterval = 5) {
        var left = seconds
        while left > 0 {
            let jump = min(step, left)
            now = now.addingTimeInterval(jump)
            host.tick(at: now)
            for client in clients.values { client.tick(at: now) }
            left -= jump
        }
    }

    var occupy: OccupyState? { host.state.occupy }

    func seat(_ id: PlayerID) -> BattlePlayer? {
        host.state.players.first { $0.id == id }
    }

    /// A two-player game with the host's opener down: CAT across from its
    /// start square, (12,12).
    static func opened() -> OccupyLobby {
        let lobby = OccupyLobby()
        lobby.addClient("ann")
        lobby.host.start()
        lobby.host.placeSelf(serial: 1, placement: across("cat", from: Cell(row: 12, col: 12)))
        return lobby
    }
}

@Suite("Occupy: seats and the deal")
@MainActor
struct OccupyDealTests {
    @Test func theLobbyKnowsWhichGameItPlays() {
        let lobby = OccupyLobby()
        let ann = lobby.addClient("ann")
        #expect(lobby.host.state.mode == .occupy)
        #expect(ann.state?.mode == .occupy)
        #expect(lobby.host.state.occupy == nil, "no board until the deal")
    }

    @Test func startSeatsEveryoneOnOneBoard() {
        let lobby = OccupyLobby()
        let ann = lobby.addClient("ann")
        lobby.host.start()

        let occupy = try? #require(lobby.occupy)
        #expect(occupy?.frame == OCCUPY_FRAME)
        #expect(occupy?.seats == ["host", "ann"])
        #expect(occupy?.board.isEmpty == true)
        #expect(occupy?.zones.isEmpty == true, "no zones until the grace ends")
        #expect(ann.state?.occupy == occupy, "the client holds the same board")
    }

    @Test func fourPlayersShareTheSameFrameFurtherApart() {
        let lobby = OccupyLobby()
        lobby.addClient("ann")
        lobby.addClient("bea")
        lobby.addClient("cal")
        lobby.host.start()
        #expect(lobby.occupy?.frame == OCCUPY_FRAME)
        #expect(lobby.occupy?.seats.count == 4)
        #expect(lobby.occupy?.startCell(seat: 0) == Cell(row: 11, col: 11))
        #expect(lobby.occupy?.startCell(seat: 3) == Cell(row: 21, col: 11))
    }

    @Test func theFifthPlayerIsTurnedAway() {
        let lobby = OccupyLobby()
        for name in ["ann", "bea", "cal"] { lobby.addClient(name) }
        #expect(lobby.host.state.players.count == OCCUPY_MAX_PLAYERS)

        let fifth = lobby.addClient("dee")
        #expect(lobby.host.state.players.count == OCCUPY_MAX_PLAYERS)
        #expect(lobby.rejections["dee"] == ["That game is full."])
        #expect(fifth.isRejected)
    }

    @Test func stopClearsTheBoardAndRestartDealsAFreshOne() {
        let lobby = OccupyLobby.opened()
        #expect(lobby.occupy?.board.count == 3)

        lobby.host.stop()
        #expect(lobby.host.state.occupy == nil)

        lobby.host.start()
        #expect(lobby.occupy?.board.isEmpty == true)
        #expect(lobby.occupy?.opened == [false, false])
        #expect(lobby.host.state.game == 2)
    }
}

@Suite("Occupy: landing words over the wire")
@MainActor
struct OccupyPlacementTests {
    @Test func theHostsOwnWordLandsAndIsBroadcast() {
        let lobby = OccupyLobby()
        let ann = lobby.addClient("ann")
        lobby.host.start()

        lobby.host.placeSelf(serial: 1, placement: across("cat", from: Cell(row: 12, col: 12)))

        #expect(lobby.occupy?.board.count == 3)
        #expect(lobby.occupy?.owners[keyOf(12, 12)] == 0)
        #expect(lobby.occupy?.scores == [9, 0])
        #expect(lobby.seat("host")?.score == 9, "the roster reads the board")
        #expect(ann.state?.occupy?.board.count == 3)
        #expect(lobby.heard["host"]?.last == "placed:1")
    }

    @Test func aClientsWordIsAnsweredAfterTheSnapshotThatCarriesIt() {
        let lobby = OccupyLobby.opened()
        let ann = lobby.clients["ann"]!

        // TEA down through the T at (12,14), capturing it.
        ann.sendPlacement(serial: 7, placement: down("tea", from: Cell(row: 12, col: 14), borrowing: [keyOf(12, 14)]))

        #expect(lobby.occupy?.board.count == 5)
        #expect(lobby.occupy?.owners[keyOf(12, 14)] == 1, "captured")
        #expect(lobby.occupy?.scores == [6, 9])
        let heard = lobby.heard["ann"] ?? []
        #expect(heard.suffix(2) == ["state", "placed:7"], "the board first, then the answer")
        #expect(ann.state?.occupy?.board.count == 5)
    }

    @Test func aSquareSomeoneGotToFirstIsRefused() {
        let lobby = OccupyLobby.opened()
        let ann = lobby.clients["ann"]!
        let before = lobby.occupy

        // Ann's board didn't know (12,13) was taken.
        var clash = down("tea", from: Cell(row: 12, col: 14), borrowing: [keyOf(12, 14)])
        clash.tiles[keyOf(12, 13)] = "x"
        ann.sendPlacement(serial: 2, placement: clash)

        #expect(lobby.occupy == before, "nothing changed")
        #expect(lobby.heard["ann"]?.last == "refused:2:Someone got there first.")
    }

    @Test func aWordThatDoesntReadIsRefusedByName() {
        let lobby = OccupyLobby.opened()
        lobby.clients["ann"]?.sendPlacement(
            serial: 3, placement: down("tzz", from: Cell(row: 12, col: 14), borrowing: [keyOf(12, 14)]))
        #expect(lobby.heard["ann"]?.last == "refused:3:TZZ isn’t a word")
    }

    @Test func wordsOutsideAGameOrFromASpectatorAreRefused() {
        let lobby = OccupyLobby()
        let ann = lobby.addClient("ann")
        ann.sendPlacement(serial: 1, placement: across("cat", from: Cell(row: 12, col: 12)))
        #expect(lobby.heard["ann"]?.last == "refused:1:You’re not in this game.")

        lobby.host.start()
        let bea = lobby.addClient("bea")
        #expect(lobby.seat("bea")?.waiting == true)
        bea.sendPlacement(serial: 1, placement: across("cat", from: Cell(row: 12, col: 12)))
        #expect(lobby.heard["bea"]?.last == "refused:1:You’re not in this game.")
    }
}

@Suite("Occupy: the end")
@MainActor
struct OccupyEndTests {
    @Test func theClockEndsItAndTheMostValueWins() {
        let lobby = OccupyLobby.opened()
        // Words keep landing — one every twenty-five seconds, each borrowing
        // from the last, a staircase of TEA down and ART across that runs
        // clean off the frame — so the stall rule never gets a look in and
        // the clock is what ends it.
        var cursor = Cell(row: 12, col: 14)  // the T of CAT
        var serial = 10
        var words = 0
        var elapsed = 0.0
        while elapsed + 25 < Double(OCCUPY_SECONDS) {
            lobby.advance(25)
            elapsed += 25
            serial += 1
            let borrowed = keyOf(cursor.row, cursor.col)
            if words % 2 == 0 {
                lobby.clients["ann"]?.sendPlacement(
                    serial: serial, placement: down("tea", from: cursor, borrowing: [borrowed]))
                cursor = Cell(row: cursor.row + 2, col: cursor.col)
            } else {
                lobby.host.placeSelf(
                    serial: serial, placement: across("art", from: cursor, borrowing: [borrowed]))
                cursor = Cell(row: cursor.row, col: cursor.col + 2)
            }
            words += 1
            #expect(lobby.host.state.phase == .playing, "\(elapsed)s in")
        }
        #expect(lobby.occupy?.board.count == 3 + words * 2, "every word landed")
        #expect(cursor.row > OCCUPY_FRAME || cursor.col > OCCUPY_FRAME, "and ran past the frame")
        #expect(lobby.occupy?.zones.count == occupyZonesDue(elapsed: elapsed), "zones came as scheduled")

        // 575 seconds in: twenty-four more and it's still on; one more and it's time.
        lobby.advance(Double(OCCUPY_SECONDS) - elapsed - 1)
        #expect(lobby.host.state.phase == .playing)
        lobby.advance(1)
        #expect(lobby.host.state.phase == .finished)
        #expect(lobby.occupy?.end == .clock)

        let scores = lobby.occupy?.scores ?? []
        #expect(scores.count == 2)
        let leader: PlayerID? = scores[0] > scores[1] ? "host" : scores[1] > scores[0] ? "ann" : nil
        #expect(lobby.host.state.winnerId == leader)
        #expect(lobby.clients["ann"]?.state?.phase == .finished)
    }

    @Test func zonesAppearOnTheHostsClockAndRideTheSnapshot() {
        let lobby = OccupyLobby.opened()
        let ann = lobby.clients["ann"]!
        lobby.advance(OCCUPY_ZONE_FIRST_SECONDS - 1)
        #expect(lobby.occupy?.zones.isEmpty == true)
        lobby.advance(1)
        #expect(lobby.occupy?.zones.count == 1)
        #expect(ann.state?.occupy?.zones == lobby.occupy?.zones, "the client sees the same zone")

        let zone = lobby.occupy!.zones[0]
        #expect(zone.keys.allSatisfy { lobby.occupy?.board[$0] == nil }, "on empty ground")
        #expect(!zone.contains(Cell(row: 12, col: 12)) && !zone.contains(Cell(row: 20, col: 20)), "off the starts")

        // A word keeps the stall off; the next zone comes on the interval.
        lobby.advance(50)
        #expect(lobby.host.state.phase == .playing)
        lobby.clients["ann"]?.sendPlacement(
            serial: 2, placement: down("tea", from: Cell(row: 12, col: 14), borrowing: [keyOf(12, 14)]))
        #expect(lobby.occupy?.zones.count == 1)
        lobby.advance(OCCUPY_ZONE_INTERVAL_SECONDS - 50)
        #expect(lobby.host.state.phase == .playing)
        #expect(lobby.occupy?.zones.count == 2)
        if let zones = lobby.occupy?.zones, zones.count == 2 {
            #expect(!zones[0].overlaps(zones[1]))
        }

        // The same seed grows the same zones.
        let replay = OccupyLobby.opened()
        replay.advance(OCCUPY_ZONE_FIRST_SECONDS)
        #expect(replay.occupy?.zones == [zone])
    }

    @Test func theStallEndsItEarlyButNotDuringTheGrace() {
        let lobby = OccupyLobby()
        lobby.addClient("ann")
        lobby.host.start()

        // Silence from the deal: the stall clock starts when the grace ends.
        lobby.advance(OCCUPY_GRACE_SECONDS + OCCUPY_STALL_SECONDS - 1)
        #expect(lobby.host.state.phase == .playing)
        lobby.advance(1)
        #expect(lobby.host.state.phase == .finished)
        #expect(lobby.occupy?.end == .stall)
        #expect(lobby.host.state.winnerId == nil, "nothing on the board: a draw")
    }

    @Test func aWordResetsTheStallClock() {
        let lobby = OccupyLobby()
        lobby.addClient("ann")
        lobby.host.start()
        lobby.advance(OCCUPY_GRACE_SECONDS + 20)
        lobby.host.placeSelf(serial: 1, placement: across("cat", from: Cell(row: 12, col: 12)))

        lobby.advance(OCCUPY_STALL_SECONDS - 1)
        #expect(lobby.host.state.phase == .playing)
        lobby.advance(1)
        #expect(lobby.host.state.phase == .finished)
        #expect(lobby.occupy?.end == .stall)
        #expect(lobby.host.state.winnerId == "host")
    }

    @Test func theFieldEmptyingEndsItForTheOneLeft() {
        let lobby = OccupyLobby.opened()
        // Ann is ahead, then walks out: she can't win from the door.
        lobby.clients["ann"]?.sendPlacement(
            serial: 1, placement: down("tea", from: Cell(row: 12, col: 14), borrowing: [keyOf(12, 14)]))
        #expect(lobby.occupy?.scores == [6, 9])

        lobby.clients["ann"]?.leave()
        #expect(lobby.host.state.phase == .finished)
        #expect(lobby.occupy?.end == .field)
        #expect(lobby.host.state.winnerId == "host")
    }

    @Test func aClientsOpenerArrivesInTheHostsFrame() {
        // Ann sees the board turned so her corner is top-left and types CAT
        // rightward; what reaches the host is T-A-C ending on her start
        // square, and the referee reads a run either way.
        let lobby = OccupyLobby.opened()
        lobby.clients["ann"]?.sendPlacement(
            serial: 5, placement: across("tac", from: Cell(row: 20, col: 18)))
        #expect(lobby.occupy?.owners[keyOf(20, 20)] == 1)
        #expect(lobby.occupy?.scores == [9, 9])
        #expect(lobby.heard["ann"]?.last == "placed:5")
    }

    @Test func aFinishedBoardTakesNoMoreWords() {
        let lobby = OccupyLobby.opened()
        lobby.advance(Double(OCCUPY_SECONDS))
        #expect(lobby.host.state.phase == .finished)
        lobby.clients["ann"]?.sendPlacement(
            serial: 9, placement: down("tea", from: Cell(row: 12, col: 14), borrowing: [keyOf(12, 14)]))
        #expect(lobby.occupy?.board.count == 3)
        #expect(lobby.heard["ann"]?.last == "refused:9:You’re not in this game.")
    }
}
