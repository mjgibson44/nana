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
/// Two details it exists to absorb:
///
///  - GameKit speaks `GKPlayer`, the protocol speaks `gamePlayerID` strings.
///    The map is rebuilt from `match.players` on every change rather than
///    cached, because a reconnecting player arrives as a *new* `GKPlayer`
///    instance with the same id.
///  - `GKMatch` is a full mesh with no marked owner. The star topology is
///    enforced by convention above this line — clients send only to the host —
///    so this adapter deliberately offers no opinion about who that is.
/// Threading: every method here is called from the main actor (the sessions
/// above it are `@MainActor`), and every delegate callback hops to main before
/// touching anything. `@unchecked Sendable` records that invariant, which the
/// compiler can't check across a non-isolated protocol.
final class GameKitTransport: NSObject, BattleTransport, @unchecked Sendable {
    let localPlayerID: PlayerID
    private let match: GKMatch

    var onReceive: ((Data, PlayerID) -> Void)?
    var onPlayerConnected: ((PlayerID) -> Void)?
    var onPlayerDisconnected: ((PlayerID) -> Void)?

    init(match: GKMatch, localPlayerID: PlayerID = GKLocalPlayer.local.gamePlayerID) {
        self.match = match
        self.localPlayerID = localPlayerID
        super.init()
        match.delegate = self
    }

    var remotePlayerIDs: [PlayerID] {
        match.players.map(\.gamePlayerID)
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
        onMain { [weak self] in self?.onReceive?(data, id) }
    }

    func match(_ match: GKMatch, player: GKPlayer, didChange state: GKPlayerConnectionState) {
        let id = player.gamePlayerID
        switch state {
        case .connected:
            onMain { [weak self] in self?.onPlayerConnected?(id) }
        case .disconnected:
            // Backgrounding an app produces exactly this, which is why the
            // host holds a seat for a grace rather than eliminating on it
            // (plan §7.4).
            onMain { [weak self] in self?.onPlayerDisconnected?(id) }
        default:
            break
        }
    }

    func match(_ match: GKMatch, didFailWithError error: Error?) {
        // A dead match is every player disconnecting at once, as far as the
        // sessions above are concerned.
        let ids = match.players.map(\.gamePlayerID)
        onMain { [weak self] in
            for id in ids { self?.onPlayerDisconnected?(id) }
        }
    }
}
