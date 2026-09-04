import Foundation
import Testing
import WordCore

@testable import WordNet

/// A whole lobby in memory: a host session, client sessions, and the mesh
/// between them. This is the phase-4 test rig the plan calls for — protocol
/// logic at unit-test speed, with only the GKMatch adapter left needing
/// devices (plan §7.5).
/// A clock the whole lobby shares, so sessions can be handed a reference to it
/// before the lobby itself finishes initializing.
final class SimulatedClock {
    var now: Date

    init(_ now: Date) {
        self.now = now
    }
}

@MainActor
final class Lobby {
    let mesh = MemoryMesh()
    let host: HostSession
    let hostTransport: MemoryTransport
    private(set) var clients: [PlayerID: ClientSession] = [:]
    private(set) var clientTransports: [PlayerID: MemoryTransport] = [:]

    /// What each client's game layer was told.
    private(set) var attacksReceived: [PlayerID: [Int]] = [:]
    private(set) var seedsReceived: [PlayerID: [String]] = [:]
    private(set) var rejections: [PlayerID: [String]] = [:]
    var hostAttacks: [Int] = []
    private(set) var hostSeeds: [String] = []

    private let simulated = SimulatedClock(Date(timeIntervalSince1970: 1_000))

    var now: Date {
        get { simulated.now }
        set { simulated.now = newValue }
    }

    init(
        hostID: PlayerID = "host", seed: String = "seedseedseed",
        autoStart: AutoStartRule? = nil,
        graceSeconds: TimeInterval = RECONNECT_GRACE_SECONDS,
        admitsMidGame: Bool = true
    ) {
        hostTransport = mesh.add(hostID)
        host = HostSession(
            transport: hostTransport,
            displayName: { "Player \($0)" },
            makeSeed: { seed },
            clock: { [simulated] in simulated.now },
            autoStart: autoStart,
            graceSeconds: graceSeconds,
            admitsMidGame: admitsMidGame)
        host.events.onAttack = { [weak self] count in self?.hostAttacks.append(count) }
        host.events.onStart = { [weak self] seed in self?.hostSeeds.append(seed) }
        mesh.connect(hostID)
        host.announceHost()
    }

    /// Bring a client in and let the announcement reach it.
    @discardableResult
    func addClient(_ id: PlayerID) -> ClientSession {
        let transport = mesh.add(id)
        let client = ClientSession(transport: transport, clock: { [simulated] in simulated.now })
        client.events.onAttack = { [weak self] count in
            self?.attacksReceived[id, default: []].append(count)
        }
        client.events.onStart = { [weak self] seed in
            self?.seedsReceived[id, default: []].append(seed)
        }
        client.events.onRejected = { [weak self] reason in
            self?.rejections[id, default: []].append(reason)
        }
        clients[id] = client
        clientTransports[id] = transport
        mesh.connect(id)
        return client
    }

    func advance(_ seconds: TimeInterval) {
        now = now.addingTimeInterval(seconds)
        host.tick(at: now)
        for client in clients.values { client.tick(at: now) }
    }

    func seat(_ id: PlayerID) -> BattlePlayer? {
        host.state.players.first { $0.id == id }
    }

    /// How many times the host has told `player` who referees.
    func announcements(to player: PlayerID) -> Int {
        hostTransport.sentMessages(HostMessage.self).filter {
            if case .host = $0.message { return $0.to == [player] }
            return false
        }.count
    }
}

@Suite("Host roster and version gate")
@MainActor
struct RosterTests {
    @Test func aClientIsSeatedOnHelloAndSeesTheSnapshot() {
        let lobby = Lobby()
        let client = lobby.addClient("ann")

        // The host's announcement reached the client, which greeted it back.
        #expect(client.hostID == "host")
        #expect(lobby.host.state.players.map(\.id) == ["host", "ann"])
        #expect(client.state?.players.count == 2)
        #expect(lobby.seat("ann")?.host == false)
        #expect(lobby.seat("host")?.host == true)
    }

    @Test func aLateJoinerIsToldWhoReferees() {
        let lobby = Lobby()
        lobby.addClient("ann")
        // Bea arrives after the opening broadcast and still learns the host,
        // because the host re-announces to every new connection (plan §7.2).
        let bea = lobby.addClient("bea")
        #expect(bea.hostID == "host")
        #expect(lobby.host.state.players.map(\.id).sorted() == ["ann", "bea", "host"])
    }

    @Test func theNinthPlayerIsTurnedAway() {
        let lobby = Lobby()
        // Seven clients plus the host fills the eight seats.
        for index in 1...7 { lobby.addClient("p\(index)") }
        #expect(lobby.host.state.players.count == BATTLE_MAX_PLAYERS)

        let ninth = lobby.addClient("late")
        #expect(lobby.host.state.players.count == BATTLE_MAX_PLAYERS)
        #expect(lobby.rejections["late"]?.count == 1)
        #expect(ninth.isRejected)
    }

    @Test func aVersionMismatchIsRefusedLoudly() throws {
        // No Game Center sandbox means a prerelease build can meet a released
        // one (TN2417), so the gate has to actually fire.
        let lobby = Lobby()
        let transport = lobby.mesh.join("oldbuild")
        var rejected: String?
        transport.onReceive = { data, _ in
            if case let .reject(reason) = Wire.decode(HostMessage.self, from: data) {
                rejected = reason
            }
        }
        transport.send(
            try #require(Wire.encode(ClientMessage.hello(proto: PROTOCOL_VERSION - 1))),
            to: ["host"])

        #expect(rejected != nil)
        #expect(lobby.host.state.players.map(\.id) == ["host"])
    }

    @Test func aMidGameJoinerSpectatesUntilTheNextDeal() {
        let lobby = Lobby()
        lobby.addClient("ann")
        lobby.host.start()

        lobby.addClient("bea")
        #expect(lobby.seat("bea")?.waiting == true, "seated, but dealt into the next game")

        lobby.host.start()
        #expect(lobby.seat("bea")?.waiting == false)
    }

    @Test func startPurgesDepartedSeatsAndResetsTheRest() {
        let lobby = Lobby()
        lobby.addClient("ann")
        lobby.addClient("bea")
        lobby.host.start()
        lobby.host.reportSelf(score: 30, buried: false, tiles: 4)

        // Bea leaves for good, mid-game.
        lobby.clients["bea"]?.leave()
        #expect(lobby.seat("bea")?.left == true)

        lobby.host.start()
        #expect(lobby.host.state.players.map(\.id) == ["host", "ann"])
        #expect(lobby.seat("host")?.score == 0)
        #expect(lobby.seat("host")?.outOrder == nil)
        #expect(lobby.host.state.game == 2)
    }

    @Test func startSendsTheSeedBeforeTheSnapshot() {
        // Clients build their tile streams on `start`; an attack or state
        // arriving first would draw from the previous game (spec §6).
        let lobby = Lobby()
        lobby.addClient("ann")
        let before = lobby.hostTransport.sent.count
        lobby.host.start()

        let sent = lobby.hostTransport.sentMessages(HostMessage.self).dropFirst(before)
        let startIndex = sent.firstIndex { if case .start = $0.message { return true } else { return false } }
        let stateIndex = sent.firstIndex { if case .state = $0.message { return true } else { return false } }
        #expect(startIndex != nil)
        #expect(stateIndex != nil)
        #expect(startIndex! < stateIndex!)
        #expect(lobby.seedsReceived["ann"] == ["seedseedseed"])
        #expect(lobby.hostSeeds == ["seedseedseed"])
    }
}

@Suite("Attack splitting and routing")
@MainActor
struct AttackTests {
    @Test func aVolleyIsSplitAcrossStandingRivalsOnly() {
        let lobby = Lobby()
        lobby.addClient("ann")
        lobby.addClient("bea")
        lobby.addClient("cal")
        lobby.host.start()

        // Cal is out; the volley must not reach a dead board.
        lobby.clients["cal"]?.reportProgress(score: 0, buried: true, tiles: 26)
        #expect(lobby.seat("cal")?.buried == true)

        lobby.clients["ann"]?.sendAttack(4)
        // Ann attacked, so her share goes to the host and Bea: 2 each.
        #expect(lobby.hostAttacks == [2])
        #expect(lobby.attacksReceived["bea"] == [2])
        #expect(lobby.attacksReceived["cal"] == nil)
        #expect(lobby.attacksReceived["ann"] == nil, "an attacker never hits themselves")
    }

    @Test func theRemainderRotatesSoNobodyAlwaysAbsorbsIt() {
        let lobby = Lobby()
        lobby.addClient("ann")
        lobby.addClient("bea")
        lobby.host.start()

        // 3 tiles across 2 rivals: someone gets 2 and someone gets 1, and the
        // extra tile moves on the next volley.
        lobby.clients["ann"]?.sendAttack(3)
        lobby.clients["ann"]?.sendAttack(3)
        let hostShares = lobby.hostAttacks
        let beaShares = lobby.attacksReceived["bea"] ?? []
        #expect(hostShares.count == 2)
        #expect(beaShares.count == 2)
        let delivered: Int = hostShares.reduce(0, +) + beaShares.reduce(0, +)
        #expect(delivered == 6)
        #expect(hostShares != beaShares, "the remainder rotates between volleys")
    }

    @Test func aVolleyIsClampedAndNonsenseIsIgnored() {
        let lobby = Lobby()
        lobby.addClient("ann")
        lobby.host.start()

        lobby.clients["ann"]?.sendAttack(9_999)
        #expect(lobby.hostAttacks == [ATTACK_CLAMP])

        lobby.hostAttacks.removeAll()
        lobby.clients["ann"]?.sendAttack(0)
        lobby.clients["ann"]?.sendAttack(-5)
        #expect(lobby.hostAttacks.isEmpty)
    }

    @Test func attacksAreIgnoredOutsideAGame() {
        let lobby = Lobby()
        lobby.addClient("ann")
        // Still in the lobby.
        lobby.clients["ann"]?.sendAttack(6)
        #expect(lobby.hostAttacks.isEmpty)
    }

    @Test func aSpectatorNeitherSendsNorReceives() {
        let lobby = Lobby()
        lobby.addClient("ann")
        lobby.host.start()
        // Bea joins mid-game: waiting, so outside the volley entirely.
        lobby.addClient("bea")

        lobby.clients["ann"]?.sendAttack(2)
        #expect(lobby.attacksReceived["bea"] == nil)

        lobby.clients["bea"]?.sendAttack(4)
        #expect(lobby.hostAttacks.count == 1, "the spectator's own volley is ignored")
    }
}

@Suite("Referee: elimination order and the verdict")
@MainActor
struct RefereeTests {
    @Test func theLastBoardStandingWins() {
        let lobby = Lobby()
        lobby.addClient("ann")
        lobby.addClient("bea")
        lobby.host.start()

        lobby.clients["ann"]?.reportProgress(score: 10, buried: true, tiles: 26)
        #expect(lobby.host.state.phase == .playing, "two boards are still alive")

        lobby.clients["bea"]?.reportProgress(score: 20, buried: true, tiles: 26)
        #expect(lobby.host.state.phase == .finished)
        #expect(lobby.host.state.winnerId == "host")
        // Standings are pure reverse elimination order.
        #expect(lobby.seat("ann")?.outOrder == 1)
        #expect(lobby.seat("bea")?.outOrder == 2)
    }

    @Test func theEliminationStampIsWriteOnce() {
        let lobby = Lobby()
        lobby.addClient("ann")
        lobby.addClient("bea")
        lobby.host.start()

        lobby.clients["ann"]?.reportProgress(score: 5, buried: true, tiles: 26)
        let stamp = lobby.seat("ann")?.outOrder
        // A repeat report — or a regressing one — can't move a standing.
        lobby.clients["ann"]?.reportProgress(score: 5, buried: true, tiles: 26)
        lobby.clients["ann"]?.reportProgress(score: 5, buried: false, tiles: 3)
        #expect(lobby.seat("ann")?.outOrder == stamp)
    }

    @Test func progressIsClampedToSanity() {
        let lobby = Lobby()
        lobby.addClient("ann")
        lobby.host.start()
        lobby.clients["ann"]?.reportProgress(score: -50, buried: false, tiles: -3)
        #expect(lobby.seat("ann")?.score == 0)
        #expect(lobby.seat("ann")?.tiles == 0)
    }

    @Test func theFirstBurialDecidesAHeadToHead() {
        // Burials arrive one message at a time, so with two contestants the
        // first one to go under hands the game to the other — there is no
        // moment where both are down at once. (WordCore's referee covers the
        // simultaneous-draw branch; this protocol can't produce it.)
        let lobby = Lobby()
        lobby.addClient("ann")
        lobby.host.start()
        lobby.clients["ann"]?.reportProgress(score: 8, buried: true, tiles: 26)
        #expect(lobby.host.state.phase == .finished)
        #expect(lobby.host.state.winnerId == "host")

        // A later report from the loser can't reopen a decided game.
        lobby.host.reportSelf(score: 9, buried: true, tiles: 26)
        #expect(lobby.host.state.winnerId == "host")
    }

    @Test func aSoloContestantIsNotAGameToWin() {
        let lobby = Lobby()
        lobby.host.start()
        lobby.host.reportSelf(score: 3, buried: false, tiles: 2)
        // One contestant can't satisfy the "at least two started" rule.
        #expect(lobby.host.state.phase == .playing)
    }
}

@Suite("Seat grace, drops and re-entry")
@MainActor
struct GraceTests {
    @Test func aMidGameDropHoldsTheSeatAndTheGamePlaysOn() {
        let lobby = Lobby()
        lobby.addClient("ann")
        lobby.addClient("bea")
        lobby.host.start()

        lobby.mesh.drop("ann")
        #expect(lobby.seat("ann")?.connected == false)
        #expect(lobby.seat("ann")?.left == false, "the seat is held, not vacated")
        #expect(lobby.seat("ann")?.outOrder == nil)
        #expect(lobby.host.state.phase == .playing, "a battle never pauses for a drop")
        #expect(lobby.host.gracedSeats == ["ann"])
    }

    @Test func graceExpiryCountsThemOutAndFixesTheirStanding() {
        let lobby = Lobby()
        lobby.addClient("ann")
        lobby.addClient("bea")
        lobby.host.start()
        lobby.mesh.drop("ann")

        lobby.advance(RECONNECT_GRACE_SECONDS - 1)
        #expect(lobby.seat("ann")?.left == false, "still inside the grace period")

        lobby.advance(2)
        #expect(lobby.seat("ann")?.left == true)
        #expect(lobby.seat("ann")?.outOrder == 1)
        // Ann's seat is no longer being held open — though Bea's now is, since
        // 31 seconds of silence trips the staleness sweep for her too.
        #expect(lobby.host.gracedSeats.contains("ann") == false)
    }

    @Test func reEnteringInsideGraceReclaimsTheSeat() {
        let lobby = Lobby()
        lobby.addClient("ann")
        lobby.addClient("bea")
        lobby.host.start()
        let scoreBefore = 17
        lobby.clients["ann"]?.reportProgress(score: scoreBefore, buried: false, tiles: 5)

        lobby.mesh.drop("ann")
        lobby.advance(5)

        // Same player id back on the mesh: the seat re-attaches with its score
        // intact, exactly as the web's stable key does (spec §5).
        let returning = lobby.addClient("ann")
        returning.reattach()

        #expect(lobby.seat("ann")?.connected == true)
        #expect(lobby.seat("ann")?.left == false)
        #expect(lobby.seat("ann")?.score == scoreBefore)
        #expect(lobby.host.gracedSeats.isEmpty)
        #expect(lobby.host.state.players.filter { $0.id == "ann" }.count == 1, "one seat, not two")
    }

    @Test func returningAfterGraceComesBackAsASpectator() {
        let lobby = Lobby()
        lobby.addClient("ann")
        lobby.addClient("bea")
        lobby.host.start()
        lobby.mesh.drop("ann")
        lobby.advance(RECONNECT_GRACE_SECONDS + 1)
        #expect(lobby.seat("ann")?.left == true)

        lobby.addClient("ann").reattach()

        // Their game is over, but their seat is: they wait for the next deal.
        #expect(lobby.seat("ann")?.left == false)
        #expect(lobby.seat("ann")?.waiting == true)
        #expect(lobby.seat("ann")?.outOrder == 1, "their standing stays fixed")
    }

    @Test func aLobbyDropJustLeaves() {
        let lobby = Lobby()
        lobby.addClient("ann")
        lobby.mesh.drop("ann")
        // Outside a game there is nothing to hold a seat for.
        #expect(lobby.host.state.players.map(\.id) == ["host"])
    }

    @Test func aDeliberateLeaveMidGameGetsNoGrace() {
        let lobby = Lobby()
        lobby.addClient("ann")
        lobby.addClient("bea")
        lobby.host.start()

        lobby.clients["ann"]?.leave()
        #expect(lobby.seat("ann")?.left == true)
        #expect(lobby.seat("ann")?.outOrder == 1, "they still place in the standings")
        #expect(lobby.host.gracedSeats.isEmpty)
    }

    @Test func silenceOutlastingTheStalenessCutoffIsADeadLink() {
        let lobby = Lobby()
        lobby.addClient("ann")
        lobby.addClient("bea")
        lobby.host.start()

        // Nobody says anything for longer than the cutoff. The transport still
        // believes the link is up; the app-level sweep knows better.
        lobby.advance(STALE_LINK_SECONDS + 1)
        #expect(lobby.seat("ann")?.connected == false)
        #expect(lobby.host.gracedSeats.contains("ann"))
    }

    @Test func aRandomMatchHoldsADroppedSeatForLess() {
        // Strangers have no road back in, so their seat is held for a shorter
        // grace than friends get — an init parameter, not a second constant.
        let lobby = Lobby(graceSeconds: 10)
        lobby.addClient("ann")
        lobby.addClient("bea")
        lobby.host.start()
        lobby.mesh.drop("ann")

        lobby.advance(9)
        #expect(lobby.seat("ann")?.left == false)
        lobby.advance(2)
        #expect(lobby.seat("ann")?.left == true)
    }

    @Test func disconnectingDropsAPlayerFromTheMesh() {
        // Leaving for good is a transport-level act: everyone else sees the
        // player go, the way GKMatch.disconnect shows a departure.
        let lobby = Lobby()
        let client = lobby.addClient("ann")
        client.leave()
        lobby.clientTransports["ann"]?.disconnect()

        #expect(lobby.host.state.players.map(\.id) == ["host"])
        #expect(lobby.hostTransport.remotePlayerIDs.contains("ann") == false)
    }

    @Test func theHeartbeatDrawsPongsThatKeepASeatAlive() {
        let lobby = Lobby()
        lobby.addClient("ann")
        lobby.host.start()

        // Two ping intervals of quiet play: the pings draw pongs, which keep
        // lastSeen fresh, so nobody is swept.
        lobby.advance(PING_INTERVAL_SECONDS)
        lobby.advance(PING_INTERVAL_SECONDS)
        #expect(lobby.seat("ann")?.connected == true)

        let pings = lobby.hostTransport.sentMessages(HostMessage.self)
            .filter { if case .ping = $0.message { return true } else { return false } }
        #expect(pings.count >= 2)
    }
}

@Suite("Host election (the one new piece of protocol)")
@MainActor
struct HostElectionTests {
    @Test func theAnnouncementSettlesIt() {
        let lobby = Lobby()
        let client = lobby.addClient("zoe")
        // "zoe" sorts after "host", so the fallback would have picked the
        // host anyway — check the announcement itself did the work, with no
        // waiting at all.
        #expect(client.hostID == "host")
    }

    @Test func silenceFallsBackToTheLowestPlayerID() {
        // A party formed without an announcement (an older build, no lobby
        // creator): every client computes the same answer without talking.
        let mesh = MemoryMesh()
        let annTransport = mesh.join("ann")
        let beaTransport = mesh.join("bea")
        let now = Date(timeIntervalSince1970: 500)

        var beaHost: PlayerID?
        let bea = ClientSession(transport: beaTransport, clock: { now })
        bea.events.onHostElected = { beaHost = $0 }
        let ann = ClientSession(transport: annTransport, clock: { now })

        // Nothing yet — the announcement might still be coming.
        bea.tick(at: now.addingTimeInterval(HOST_ANNOUNCE_TIMEOUT_SECONDS - 0.5))
        #expect(beaHost == nil)

        bea.tick(at: now.addingTimeInterval(HOST_ANNOUNCE_TIMEOUT_SECONDS))
        #expect(beaHost == "ann", "lowest id referees")

        // Ann is that lowest id, so she elects nobody: she should have been
        // running a host session, which the app layer decides.
        ann.tick(at: now.addingTimeInterval(HOST_ANNOUNCE_TIMEOUT_SECONDS))
        #expect(ann.hostID == nil)
    }

    @Test func anAnnouncementBeatsAPendingFallback() {
        let mesh = MemoryMesh()
        let now = Date(timeIntervalSince1970: 500)
        let hostTransport = mesh.add("zzz-host")
        let clientTransport = mesh.add("ann")

        // The lowest id here is "ann" — the client itself — so a fallback
        // would elect nobody. The announcement names the real referee.
        let host = HostSession(
            transport: hostTransport, displayName: { $0 }, makeSeed: { "s" }, clock: { now })
        let client = ClientSession(transport: clientTransport, clock: { now })
        mesh.connect("zzz-host")
        mesh.connect("ann")
        host.announceHost()
        #expect(client.hostID == "zzz-host")
        #expect(host.state.players.map(\.id) == ["zzz-host", "ann"])
    }

    @Test func onlyTheHostIsObeyed() throws {
        let lobby = Lobby()
        let client = lobby.addClient("ann")
        lobby.addClient("bea")

        // Bea forges host traffic. A client takes orders from its referee only.
        let forged = try #require(Wire.encode(HostMessage.start(seed: "forged")))
        lobby.clientTransports["bea"]?.send(forged, to: ["ann"])
        #expect(lobby.seedsReceived["ann"] == nil)

        let forgedAttack = try #require(Wire.encode(HostMessage.attack(count: 9)))
        lobby.clientTransports["bea"]?.send(forgedAttack, to: ["ann"])
        #expect(lobby.attacksReceived["ann"] == nil)
        #expect(client.isRejected == false)
    }

    @Test func theLobbyDiesWithItsHostRatherThanMigrating() {
        // There is no host migration in this protocol; what changes on GameKit
        // is that clients learn in seconds instead of burning a redial budget
        // (plan §7.4).
        let lobby = Lobby()
        let client = lobby.addClient("ann")
        lobby.host.start()
        #expect(client.hostID == "host")

        let sentBeforeHostDeath = lobby.clientTransports["ann"]?.sent.count ?? 0
        lobby.mesh.drop("host")
        #expect(client.hostID == nil)
        #expect(client.isReconnecting)

        // And a client with no referee says nothing into the void.
        client.sendAttack(3)
        client.reportProgress(score: 1, buried: false, tiles: 1)
        let sentAfterHostDeath: [[PlayerID]] =
            (lobby.clientTransports["ann"]?.sent ?? []).dropFirst(sentBeforeHostDeath).map(\.to)
        let addressedTheDeadHost = sentAfterHostDeath.contains { $0.contains("host") }
        #expect(addressedTheDeadHost == false)
    }

    @Test func aMidGameHostLossStillHoldsTheSeatAndElectsNobody() {
        let lobby = Lobby()
        let ann = lobby.addClient("ann")
        lobby.addClient("bea")
        var askedToHost = false
        ann.events.onShouldHost = { askedToHost = true }
        lobby.host.start()

        lobby.mesh.drop("host")
        #expect(ann.isReconnecting)
        // Long past any election window: a game in progress never elects.
        for _ in 0..<10 { lobby.advance(1) }
        #expect(ann.hostID == nil)
        #expect(askedToHost == false)
    }

    // MARK: A match nobody opened

    @Test func theLowestIDIsToldToHost() {
        // Automatch pairs strangers with no natural host: everyone starts as
        // a client, and after the claim window the lowest id is told to
        // stand up a host session — once, and only that one.
        let mesh = MemoryMesh()
        let clock = SimulatedClock(Date(timeIntervalSince1970: 500))
        var asked: [PlayerID] = []
        let ids: [PlayerID] = ["cal", "ann", "bea"]
        var clients: [PlayerID: ClientSession] = [:]
        for id in ids {
            let client = ClientSession(
                transport: mesh.add(id), clock: { clock.now },
                announceTimeout: HOST_CLAIM_TIMEOUT_SECONDS)
            client.events.onShouldHost = { asked.append(id) }
            clients[id] = client
        }
        for id in ids { mesh.connect(id) }

        clock.now = clock.now.addingTimeInterval(HOST_CLAIM_TIMEOUT_SECONDS - 0.1)
        for client in clients.values { client.tick(at: clock.now) }
        #expect(asked.isEmpty, "the announcement might still be coming")

        clock.now = clock.now.addingTimeInterval(0.1)
        for client in clients.values { client.tick(at: clock.now) }
        #expect(asked == ["ann"])
        #expect(clients["bea"]?.hostID == "ann")
        #expect(clients["cal"]?.hostID == "ann")

        clock.now = clock.now.addingTimeInterval(1)
        for client in clients.values { client.tick(at: clock.now) }
        #expect(asked == ["ann"], "told once per election, not once per tick")
    }

    @Test func aHelloThatBeatTheHostIsRetriedOnReannounce() {
        // Bea elects Ann and says hello before Ann's device has stood up its
        // host session — the hello lands on nothing. The host's repeat to
        // whoever hasn't sat down, and the client's re-greet on hearing it,
        // heal that within a tick.
        let mesh = MemoryMesh()
        let clock = SimulatedClock(Date(timeIntervalSince1970: 500))
        let annTransport = mesh.add("ann")
        let bea = ClientSession(
            transport: mesh.add("bea"), clock: { clock.now },
            announceTimeout: HOST_CLAIM_TIMEOUT_SECONDS)
        mesh.connect("ann")
        mesh.connect("bea")

        clock.now = clock.now.addingTimeInterval(HOST_CLAIM_TIMEOUT_SECONDS)
        bea.tick(at: clock.now)
        #expect(bea.hostID == "ann")
        #expect(bea.state == nil, "the hello went into the void")

        let ann = HostSession(
            transport: annTransport, displayName: { $0 }, makeSeed: { "s" },
            clock: { clock.now })
        ann.tick(at: clock.now)
        #expect(ann.state.players.map(\.id) == ["ann", "bea"])
        #expect(bea.state?.players.count == 2)
    }

    @Test func theHostKeepsAnnouncingToWhoeverHasNotSatDown() {
        let lobby = Lobby()
        // A connected player that never says hello.
        lobby.mesh.join("mute")
        #expect(lobby.announcements(to: "mute") == 1, "told on arrival")

        // Half-second ticks for three seconds: once a second, not once a tick.
        for _ in 0..<6 { lobby.advance(0.5) }
        let repeats = lobby.announcements(to: "mute")
        #expect(repeats >= 3 && repeats <= 5, "was \(repeats)")

        // Seated players are left alone.
        lobby.addClient("ann")
        let toAnn = lobby.announcements(to: "ann")
        lobby.advance(3)
        #expect(lobby.announcements(to: "ann") == toAnn)
    }

    @Test func aRejectedPeerIsNotNagged() throws {
        let lobby = Lobby()
        let transport = lobby.mesh.join("oldbuild")
        transport.send(
            try #require(Wire.encode(ClientMessage.hello(proto: PROTOCOL_VERSION - 1))),
            to: ["host"])
        let told = lobby.announcements(to: "oldbuild")
        lobby.advance(3)
        #expect(lobby.announcements(to: "oldbuild") == told)
    }

    @Test func aClientOnlySwitchesToALowerAnnouncer() throws {
        // Two referees can only meet in a match nobody opened; the lowest
        // id wins, so a live host is traded for a lower one and never a
        // higher one.
        let lobby = Lobby(hostID: "mmm")
        let client = lobby.addClient("ppp")
        #expect(client.hostID == "mmm")
        let announcement = try #require(Wire.encode(HostMessage.host(proto: PROTOCOL_VERSION)))

        lobby.mesh.join("zzz").send(announcement, to: ["ppp"])
        #expect(client.hostID == "mmm")

        lobby.mesh.join("aaa").send(announcement, to: ["ppp"])
        #expect(client.hostID == "aaa")
    }

    @Test func aHostYieldsToALowerAnnouncer() throws {
        let lobby = Lobby(hostID: "mmm")
        var yieldedTo: [PlayerID] = []
        lobby.host.events.onYield = { yieldedTo.append($0) }
        let announcement = try #require(Wire.encode(HostMessage.host(proto: PROTOCOL_VERSION)))

        lobby.mesh.join("zzz").send(announcement, to: ["mmm"])
        #expect(yieldedTo.isEmpty, "a higher id yields to us, not the other way round")

        lobby.mesh.join("aaa").send(announcement, to: ["mmm"])
        #expect(yieldedTo == ["aaa"])
    }

    @Test func aLobbyHostLeavingTriggersAFreshElection() {
        // Nothing is lost by choosing again in the lobby, and for strangers
        // the alternative is a room that reads "reconnecting" forever.
        let lobby = Lobby()
        let ann = lobby.addClient("ann")
        let bea = lobby.addClient("bea")
        var askedToHost = false
        ann.events.onShouldHost = { askedToHost = true }

        lobby.mesh.drop("host")
        #expect(ann.hostID == nil)
        #expect(ann.isReconnecting == false, "a lobby loss is not a reconnection")
        #expect(bea.isReconnecting == false)

        lobby.advance(HOST_ANNOUNCE_TIMEOUT_SECONDS)
        #expect(askedToHost)
        #expect(bea.hostID == "ann")
    }
}

@Suite("Auto-start: duel and party")
@MainActor
struct AutoStartTests {
    @Test func aLobbyWithNoRuleNeverDealsItself() {
        let lobby = Lobby()
        lobby.addClient("ann")
        for _ in 0..<12 { lobby.advance(5) }
        #expect(lobby.host.state.phase == .lobby)
        #expect(lobby.host.state.countdown == nil)
    }

    @Test func aDuelCountsDownTheMomentTheSecondSeatFills() {
        let lobby = Lobby(autoStart: .duel)
        lobby.advance(5)
        #expect(lobby.host.state.countdown == nil, "one player is not a duel")

        let client = lobby.addClient("ann")
        lobby.advance(0.5)
        #expect(lobby.host.state.countdown == START_COUNTDOWN_SECONDS)
        #expect(client.state?.countdown == START_COUNTDOWN_SECONDS, "the countdown rides the snapshot")
    }

    @Test func theCountdownTicksOncePerSecondThenDeals() {
        let lobby = Lobby(autoStart: .duel)
        let client = lobby.addClient("ann")
        lobby.advance(0.5)

        var shown: [Int?] = []
        for _ in 0..<4 {
            lobby.advance(1)
            shown.append(lobby.host.state.countdown)
        }
        #expect(shown == [4, 3, 2, 1])
        #expect(lobby.host.state.phase == .lobby)

        lobby.advance(1)
        #expect(lobby.host.state.phase == .playing)
        #expect(lobby.host.state.countdown == nil)
        #expect(lobby.hostSeeds.count == 1)
        #expect(lobby.seedsReceived["ann"]?.count == 1)
        #expect(client.state?.countdown == nil)
    }

    @Test func aDropBelowTwoCancelsTheCountdown() {
        let lobby = Lobby(autoStart: .duel)
        lobby.addClient("ann")
        lobby.advance(0.5)
        #expect(lobby.host.state.countdown != nil)

        lobby.mesh.drop("ann")
        lobby.advance(0.5)
        #expect(lobby.host.state.countdown == nil)
        #expect(lobby.host.state.phase == .lobby)

        // Long after the countdown would have dealt: still nothing.
        lobby.advance(10)
        #expect(lobby.host.state.phase == .lobby)
        #expect(lobby.hostSeeds.isEmpty)
    }

    @Test func aPartyWaitsForTheDoorToGoQuiet() {
        let lobby = Lobby(autoStart: .party)
        lobby.addClient("ann")
        lobby.addClient("bea")
        lobby.advance(PARTY_IDLE_SECONDS - 1)
        #expect(lobby.host.state.countdown == nil, "the door is still open")

        // A fourth arrival resets the clock.
        lobby.addClient("cal")
        lobby.advance(PARTY_IDLE_SECONDS - 1)
        #expect(lobby.host.state.countdown == nil)

        lobby.advance(2)
        #expect(lobby.host.state.countdown == START_COUNTDOWN_SECONDS)
        lobby.advance(Double(START_COUNTDOWN_SECONDS))
        #expect(lobby.host.state.phase == .playing)
        #expect(lobby.host.state.players.count == 4)
    }

    @Test func aPartyStartsWithTwoIfSomeoneBailed() {
        // Three asked for, but a departure neither resets the door's clock
        // nor strands the pair left behind.
        let lobby = Lobby(autoStart: .party)
        lobby.addClient("ann")
        lobby.addClient("bea")
        lobby.advance(15)
        lobby.mesh.drop("bea")
        #expect(lobby.host.state.players.count == 2)

        lobby.advance(4)
        #expect(lobby.host.state.countdown == nil)
        lobby.advance(1.5)
        #expect(lobby.host.state.countdown == START_COUNTDOWN_SECONDS)
    }

    @Test func aPartyWithOneSeatKeepsWaiting() {
        let lobby = Lobby(autoStart: .party)
        for _ in 0..<12 { lobby.advance(5) }
        #expect(lobby.host.state.countdown == nil)
        #expect(lobby.host.state.phase == .lobby)
    }

    @Test func stopGivesAPartyItsBreatherAgain() {
        let lobby = Lobby(autoStart: .party)
        lobby.addClient("ann")
        lobby.advance(PARTY_IDLE_SECONDS + 0.5)
        lobby.advance(Double(START_COUNTDOWN_SECONDS))
        #expect(lobby.host.state.phase == .playing)

        lobby.host.stop()
        #expect(lobby.host.state.phase == .lobby)
        #expect(lobby.host.state.countdown == nil)
        lobby.advance(PARTY_IDLE_SECONDS - 1)
        #expect(lobby.host.state.countdown == nil, "back in the lobby, the door reopens for a while")
        lobby.advance(2)
        #expect(lobby.host.state.countdown == START_COUNTDOWN_SECONDS)
    }

    @Test func aRandomLobbyTurnsAwayAMidGameArrival() {
        let lobby = Lobby(autoStart: .duel, admitsMidGame: false)
        lobby.addClient("ann")
        lobby.advance(0.5)
        lobby.advance(Double(START_COUNTDOWN_SECONDS))
        #expect(lobby.host.state.phase == .playing)

        let late = lobby.addClient("late")
        #expect(late.isRejected)
        #expect(lobby.rejections["late"]?.count == 1)
        #expect(lobby.host.state.players.map(\.id) == ["host", "ann"])
    }
}

@Suite("Client snapshot handling")
@MainActor
struct ClientStateTests {
    @Test func theLatestSnapshotIsAdoptedWhole() {
        let lobby = Lobby()
        let client = lobby.addClient("ann")
        lobby.host.start()
        lobby.host.reportSelf(score: 40, buried: false, tiles: 6)

        #expect(client.state?.phase == .playing)
        #expect(client.state?.players.first { $0.id == "host" }?.score == 40)
        #expect(client.state?.game == 1)
    }

    @Test func stopReturnsEveryoneToTheLobby() {
        let lobby = Lobby()
        let client = lobby.addClient("ann")
        var stopped = false
        client.events.onStop = { stopped = true }
        lobby.host.start()
        lobby.host.stop()

        #expect(stopped)
        #expect(client.state?.phase == .lobby)
        #expect(lobby.host.state.phase == .lobby)
    }

    @Test func aRejectedClientGoesQuietForGood() {
        let lobby = Lobby()
        for index in 1...7 { lobby.addClient("p\(index)") }
        let late = lobby.addClient("late")
        #expect(late.isRejected)

        // No further traffic, whatever it's asked to do.
        let before = lobby.clientTransports["late"]?.sent.count ?? 0
        late.sendAttack(4)
        late.reportProgress(score: 1, buried: false, tiles: 1)
        late.leave()
        #expect(lobby.clientTransports["late"]?.sent.count == before)
    }

    @Test func aPingIsAnsweredWithAPong() throws {
        let lobby = Lobby()
        lobby.addClient("ann")
        let before = lobby.clientTransports["ann"]?.sentMessages(ClientMessage.self).count ?? 0
        lobby.advance(PING_INTERVAL_SECONDS)

        let sent = try #require(lobby.clientTransports["ann"]?.sentMessages(ClientMessage.self))
        let pongs = sent.dropFirst(before).filter { $0.message == .pong }
        #expect(!pongs.isEmpty)
        #expect(pongs.allSatisfy { $0.to == ["host"] }, "clients only ever address the host")
    }
}
