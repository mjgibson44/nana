import Foundation
import GameKit
import WordCore
import WordNet

/// `BattleTransport` over a real `GKMatch` — the last piece of the battle
/// stack, and the only one that can't be tested without hardware.
///
/// Everything above this file (the protocol in `WordNet`, the sessions, the
/// board wiring in `BattleSession`) runs over `MemoryTransport` in CI, which
/// is deliberate: there has been **no Game Center sandbox since 2016**
/// (TN2417), real-time `GKMatch` is widely reported broken in the simulator,
/// and Apple's own sample instructs two devices with two Apple IDs. So the
/// plan (§7.5) puts every rule somewhere testable and leaves this adapter as
/// the thin part that needs the devices.
///
/// **Unverified.** This has never run against a real match — it needs an Apple
/// Developer account and two devices. Treat it as the shape the spike starts
/// from, not as working code.
///
/// Three details it exists to absorb:
///
///  - GameKit speaks `GKPlayer`, the protocol speaks `gamePlayerID` strings.
///    Names are looked up in `match.players` on every call rather than
///    cached, because a reconnecting player arrives as a *new* `GKPlayer`
///    instance with the same id. Who is *connected*, though, is this
///    adapter's own set, kept from the delegate: whether `match.players`
///    still lists a player who dropped is undocumented, and the sessions'
///    host election needs every device to agree on the roster.
///  - `GKMatch` is a full mesh with no marked owner. The star topology is
///    enforced by convention above this line — clients send only to the host —
///    so this adapter deliberately offers no opinion about who that is.
///  - A match exists before the session that will read it: anything that
///    arrives in between (an established host's announcement to a newcomer,
///    say) is held and replayed once a receiver is attached.
///
/// Threading: every method here is called from the main actor (the sessions
/// above it are `@MainActor`), and every delegate callback hops to main before
/// touching anything. `@unchecked Sendable` records that invariant, which the
/// compiler can't check across a non-isolated protocol.
final class GameKitTransport: NSObject, BattleTransport, @unchecked Sendable {
    let localPlayerID: PlayerID
    let match: GKMatch

    /// Everyone this device currently has a link to — seeded from the match
    /// as handed over, then kept from the delegate.
    private var connected: Set<PlayerID>
    /// Traffic that arrived before anyone was listening, oldest first.
    private var buffered: [(data: Data, sender: PlayerID)] = []
    private static let bufferLimit = 64
    /// Set if GameKit gives up on the match while it is still forming.
    private var failure: Error?

    var onReceive: ((Data, PlayerID) -> Void)? {
        didSet { if onReceive != nil { scheduleFlush() } }
    }
    var onPlayerConnected: ((PlayerID) -> Void)?
    var onPlayerDisconnected: ((PlayerID) -> Void)?

    init(match: GKMatch, localPlayerID: PlayerID = GKLocalPlayer.local.gamePlayerID) {
        self.match = match
        self.localPlayerID = localPlayerID
        connected = Set(match.players.map(\.gamePlayerID))
        super.init()
        match.delegate = self
    }

    var remotePlayerIDs: [PlayerID] {
        connected.sorted()
    }

    /// The display names the roster shows. Friends see each other's real names;
    /// everyone else sees nicknames (plan §7.1).
    func displayName(for id: PlayerID) -> String {
        guard id != localPlayerID else { return GKLocalPlayer.local.displayName }
        return match.players.first { $0.gamePlayerID == id }?.displayName ?? "Player"
    }

    func send(_ data: Data, to players: [PlayerID]) {
        let targets = match.players.filter { players.contains($0.gamePlayerID) }
        guard !targets.isEmpty else { return }
        // Every message is reliable: the protocol assumes delivery *and*
        // per-sender ordering, which is exactly what `.reliable` guarantees,
        // and the volume is tiny (the largest message is a snapshot of eight
        // small player records).
        try? match.send(data, to: targets, dataMode: .reliable)
    }

    func broadcast(_ data: Data) {
        guard !match.players.isEmpty else { return }
        try? match.sendData(toAllPlayers: data, with: .reliable)
    }

    func disconnect() {
        match.delegate = nil
        match.disconnect()
        connected = []
    }

    // MARK: Forming

    /// Wait for the players GameKit matched us with to actually connect.
    ///
    /// `expectedPlayerCount` is treated as advisory rather than gospel — how
    /// it behaves for a player who never connects, or while GameKit keeps
    /// filling a match, is undocumented. So: done when it reaches zero with
    /// someone here, or when `minimum` peers are here and the roster has been
    /// quiet for `settle`; at the `cap`, done with whoever came, and a failure
    /// only if nobody did. Progress is reported as a line for the screen.
    @MainActor
    func awaitPeers(
        atLeast minimum: Int, settle: TimeInterval, cap: TimeInterval,
        onProgress: @escaping @MainActor (String) -> Void
    ) async throws {
        let started = Date()
        var lastChange = started
        var lastCount = -1
        while true {
            try Task.checkCancellation()
            if let failure { throw failure }

            let count = connected.count
            if count != lastCount {
                lastCount = count
                lastChange = Date()
                let promised = count + Int(match.expectedPlayerCount)
                onProgress("Connecting \(count + 1) of \(promised + 1)…")
            }

            if match.expectedPlayerCount == 0, count >= 1 { return }
            if count >= minimum, Date().timeIntervalSince(lastChange) >= settle { return }
            if Date().timeIntervalSince(started) >= cap {
                if count >= 1 { return }
                throw Matchmaking.Failure.failed("Nobody could connect. Try again.")
            }
            try await Task.sleep(for: .milliseconds(250))
        }
    }

    // MARK: Buffering

    private func scheduleFlush() {
        guard !buffered.isEmpty else { return }
        // On the next turn, not now: the receiver that just attached is a
        // session still being wired to the app layer above it.
        DispatchQueue.main.async { [weak self] in self?.flush() }
    }

    private func flush() {
        guard let onReceive else { return }
        let pending = buffered
        buffered = []
        for entry in pending { onReceive(entry.data, entry.sender) }
    }
}

extension GameKitTransport: GKMatchDelegate {
    /// GameKit doesn't document which queue these arrive on, so nothing here
    /// touches session state directly — each one hops to main first.
    private func onMain(_ work: @escaping @Sendable () -> Void) {
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }

    func match(_ match: GKMatch, didReceive data: Data, fromRemotePlayer player: GKPlayer) {
        let id = player.gamePlayerID
        onMain { [weak self] in
            guard let self else { return }
            if let onReceive {
                onReceive(data, id)
            } else if buffered.count < Self.bufferLimit {
                buffered.append((data, id))
            }
        }
    }

    func match(_ match: GKMatch, player: GKPlayer, didChange state: GKPlayerConnectionState) {
        let id = player.gamePlayerID
        switch state {
        case .connected:
            onMain { [weak self] in
                guard let self, connected.insert(id).inserted else { return }
                onPlayerConnected?(id)
            }
        case .disconnected:
            // Backgrounding an app produces exactly this, which is why the
            // host holds a seat for a grace rather than eliminating on it
            // (plan §7.4).
            onMain { [weak self] in
                guard let self, connected.remove(id) != nil else { return }
                onPlayerDisconnected?(id)
            }
        default:
            break
        }
    }

    func match(_ match: GKMatch, didFailWithError error: Error?) {
        // A dead match is every player disconnecting at once, as far as the
        // sessions above are concerned.
        onMain { [weak self] in
            guard let self else { return }
            failure = error ?? Matchmaking.Failure.failed("The match was lost.")
            let ids = connected
            connected = []
            for id in ids.sorted() { onPlayerDisconnected?(id) }
        }
    }
}
