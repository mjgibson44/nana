import Foundation

/// What a session needs from the network, and nothing more. `GKMatch` supplies
/// this in the app layer (`send(_:to:dataMode:.reliable)` plus the
/// `match(_:player:didChange:)` delegate); tests supply `MemoryTransport`.
///
/// Every send is reliable and ordered per sender — the protocol's standing
/// assumption (spec §6), and what `GKMatch.SendDataMode.reliable` guarantees.
public protocol BattleTransport: AnyObject {
    var localPlayerID: PlayerID { get }
    /// Everyone currently connected, excluding the local player.
    var remotePlayerIDs: [PlayerID] { get }

    func send(_ data: Data, to players: [PlayerID])
    func broadcast(_ data: Data)

    var onReceive: ((Data, PlayerID) -> Void)? { get set }
    var onPlayerConnected: ((PlayerID) -> Void)? { get set }
    var onPlayerDisconnected: ((PlayerID) -> Void)? { get set }
}

/// An in-process mesh. Delivery is synchronous and ordered, which is exactly
/// the contract `.reliable` gives — so a protocol bug shows up here rather
/// than on eight borrowed devices.
public final class MemoryTransport: BattleTransport {
    public let localPlayerID: PlayerID
    public private(set) var connected: Set<PlayerID> = []

    public var onReceive: ((Data, PlayerID) -> Void)?
    public var onPlayerConnected: ((PlayerID) -> Void)?
    public var onPlayerDisconnected: ((PlayerID) -> Void)?

    /// Every transport in this mesh, keyed by player id.
    private var mesh: MemoryMesh?

    /// Messages this transport sent, in order — the assertion surface for
    /// "who was told what".
    public private(set) var sent: [(data: Data, to: [PlayerID])] = []

    /// False until the mesh wires this transport up, so a session can attach
    /// its handlers before anyone can reach it.
    var isConnectedToMesh = false

    public init(localPlayerID: PlayerID) {
        self.localPlayerID = localPlayerID
    }

    public var remotePlayerIDs: [PlayerID] {
        connected.sorted()
    }

    public func send(_ data: Data, to players: [PlayerID]) {
        sent.append((data, players))
        for player in players where connected.contains(player) {
            mesh?.deliver(data, from: localPlayerID, to: player)
        }
    }

    public func broadcast(_ data: Data) {
        send(data, to: remotePlayerIDs)
    }

    func attach(to mesh: MemoryMesh) {
        self.mesh = mesh
    }

    func receive(_ data: Data, from sender: PlayerID) {
        onReceive?(data, sender)
    }

    func noteConnected(_ player: PlayerID) {
        guard player != localPlayerID, connected.insert(player).inserted else { return }
        onPlayerConnected?(player)
    }

    func noteDisconnected(_ player: PlayerID) {
        guard connected.remove(player) != nil else { return }
        onPlayerDisconnected?(player)
    }

    /// Decode this transport's outgoing traffic for assertions.
    public func sentMessages<M: Decodable>(_ type: M.Type) -> [(message: M, to: [PlayerID])] {
        sent.compactMap { entry in
            Wire.decode(type, from: entry.data).map { ($0, entry.to) }
        }
    }
}

/// The wiring between `MemoryTransport`s: who can see whom, and the ability to
/// cut a link the way a backgrounded iPhone does.
public final class MemoryMesh {
    private var transports: [PlayerID: MemoryTransport] = [:]

    public init() {}

    /// Register a player's transport without connecting it yet. Sessions are
    /// built on a transport before anyone can reach them — the real order of
    /// events, since a `GKMatch` exists before its delegate sees players — so
    /// registration and connection are deliberately two steps. Connecting
    /// first would deliver the host's announcement to a session that hasn't
    /// attached its handler.
    @discardableResult
    public func add(_ id: PlayerID) -> MemoryTransport {
        let transport = MemoryTransport(localPlayerID: id)
        transport.attach(to: self)
        transports[id] = transport
        return transport
    }

    /// Wire a registered player to everyone else already connected.
    public func connect(_ id: PlayerID) {
        guard let transport = transports[id] else { return }
        for (other, otherTransport) in transports where other != id {
            guard otherTransport.isConnectedToMesh else { continue }
            transport.noteConnected(other)
            otherTransport.noteConnected(id)
        }
        transport.isConnectedToMesh = true
    }

    /// Register and connect in one step, for players whose session doesn't
    /// need to exist first.
    @discardableResult
    public func join(_ id: PlayerID) -> MemoryTransport {
        let transport = add(id)
        connect(id)
        return transport
    }

    /// Drop a player off the mesh — the GKMatch "player disconnected" event
    /// every backgrounded app produces.
    public func drop(_ id: PlayerID) {
        guard transports.removeValue(forKey: id) != nil else { return }
        for transport in transports.values {
            transport.noteDisconnected(id)
        }
    }

    /// Re-enter as the same player id, which is how a graced seat is
    /// reclaimed (spec §5).
    @discardableResult
    public func rejoin(_ id: PlayerID) -> MemoryTransport {
        join(id)
    }

    func deliver(_ data: Data, from sender: PlayerID, to recipient: PlayerID) {
        transports[recipient]?.receive(data, from: sender)
    }

    public func transport(for id: PlayerID) -> MemoryTransport? {
        transports[id]
    }
}
