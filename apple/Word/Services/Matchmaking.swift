import Foundation
import GameKit
import WordCore
import WordNet

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Forming a battle: getting from "I want to play" to a live `GKMatch`
/// (plan §7.3).
///
/// Three roads. Two are for friends, ranked by what the player's OS can do:
///
///  1. **Party codes (26+)** — `GKGameActivity` generates a short shareable
///     code and URL that the system understands, and `findMatch` turns the
///     party into a `GKMatch`. This is the OS-blessed version of the web
///     game's typed join codes. Note the code *format* is Apple's, not ours:
///     two same-length parts joined by a dash. `newBattleCode`'s three letters
///     are the web broker's codes and have no say here — Game Center issues
///     the code this screen shows, and there is no API to shorten it.
///  2. **Invites (everywhere)** — `GKMatchmakerViewController` in invite-only
///     mode: friends, Messages threads, nearby players. Ships on every OS the
///     app supports, and stays the fallback below 26.
///
/// The third is for strangers:
///
///  3. **Random matches** — Game Center's rules-free automatch, headless, so
///     the search is drawn in the game's own tiles rather than Apple's sheet.
///     Duel and Party are separate pools (`MatchPool`), and so is every
///     protocol version: with no sandbox, a newer build must never be paired
///     with an older one. Nobody opens a random room, so nobody is its host
///     until the sessions elect one (`BattleSession.becomeHost`), and nobody
///     presses START: the host session deals on a rule (`AutoStartRule`).
///
/// Everything the web game needed a broker, STUN and TURN for is Apple's
/// problem from here.
///
/// **Unverified.** Matchmaking cannot run without a signed-in Apple ID on real
/// hardware — there is no Game Center sandbox (TN2417) and real-time matches
/// are reported broken in the simulator. This compiles and is shaped to the
/// documented API; it has not formed a match.
/// `GKMatch` is not `Sendable`, and GameKit hands one back from a delegate on
/// an unspecified queue. Boxing it states the invariant the compiler can't
/// see: it is only ever carried to the main actor, which is where every user
/// of it lives.
private struct UncheckedBox<T>: @unchecked Sendable {
    let value: T
}

/// The two random matches on offer, in either game. A duel is exactly two; a
/// party asks Game Center for at least three and holds its door open for
/// more — up to eight in a Battle, four in Occupy.
enum RandomMatchKind: String, CaseIterable, Equatable {
    case duel
    case party

    /// What the automatch request asks for. A party's floor is three
    /// (`PARTY_MIN_PLAYERS`), though once formed it will still start with two
    /// if a third came and went.
    func minPlayers(for mode: GameMode) -> Int {
        switch self {
        case .duel: return 2
        case .party: return PARTY_MIN_PLAYERS
        }
    }

    func maxPlayers(for mode: GameMode) -> Int {
        switch self {
        case .duel: return 2
        case .party: return mode == .occupy ? OCCUPY_MAX_PLAYERS : BATTLE_MAX_PLAYERS
        }
    }

    /// The rule the host session deals by.
    var rule: AutoStartRule {
        switch self {
        case .duel: return .duel
        case .party: return .party
        }
    }

    /// The word the screens spell it as.
    var word: String { rawValue.uppercased() }
}

/// How many a party asks Game Center to find before it forms at all.
let PARTY_MIN_PLAYERS = 3

/// Which automatch pool a search goes into. Game Center only ever pairs
/// requests with the same `playerGroup`, so the group is the whole of the
/// segregation: a Battle never meets an Occupy game, a duel never meets a
/// party, and version 8 never meets version 7.
enum MatchPool {
    static func key(
        _ kind: RandomMatchKind, mode: GameMode = .battle, version: Int = PROTOCOL_VERSION
    ) -> String {
        "timetiles/\(mode.rawValue)/\(kind.rawValue)/v\(version)"
    }

    /// FNV-1a, 32 bits. Not `hashValue`, which is seeded per process and
    /// would put every device in a pool of its own. Never zero, which
    /// GameKit reads as "no group at all".
    static func stableHash(_ text: String) -> Int {
        var hash: UInt32 = 0x811C_9DC5
        for byte in text.utf8 {
            hash ^= UInt32(byte)
            hash = hash &* 0x0100_0193
        }
        return Int(hash == 0 ? 1 : hash)
    }

    static func group(
        for kind: RandomMatchKind, mode: GameMode = .battle, version: Int = PROTOCOL_VERSION
    ) -> Int {
        stableHash(key(kind, mode: mode, version: version))
    }

    static func request(for kind: RandomMatchKind, mode: GameMode = .battle) -> GKMatchRequest {
        let request = GKMatchRequest()
        request.minPlayers = kind.minPlayers(for: mode)
        request.maxPlayers = kind.maxPlayers(for: mode)
        request.defaultNumberOfPlayers = kind.maxPlayers(for: mode)
        request.playerGroup = group(for: kind, mode: mode)
        return request
    }
}

@MainActor
final class Matchmaking: NSObject {
    enum Failure: Error, Equatable {
        case cancelled
        case unavailable(String)
        case failed(String)
    }

    /// Whether this OS can do party codes at all.
    static var supportsPartyCodes: Bool {
        if #available(iOS 26, macOS 26, *) { return true }
        return false
    }

    /// The activity the GameKit bundle defines for a battle. Must match the
    /// identifier configured there, the same way `LeaderboardID` must.
    static let battleActivityID = "battle"

    /// How long a random match may spend connecting the players GameKit
    /// found, and how long the roster must be quiet to count as formed.
    static let formingCapSeconds: TimeInterval = 10
    static let formingSettleSeconds: TimeInterval = 2

    private var continuation: CheckedContinuation<UncheckedBox<GKMatch>, Error>?
    private var presented: GKMatchmakerViewController?
    /// Counts searches, so a match that lands for one the player already
    /// backed out of is recognised and let go.
    private var searchGeneration = 0

    // MARK: Random matches — strangers

    /// Find strangers to play. Returns a transport whose peers are connected
    /// and ready for the sessions; cancelling the task cancels the search.
    /// `onProgress` gets one line at a time for the search screen.
    func findRandomMatch(
        _ kind: RandomMatchKind,
        mode: GameMode = .battle,
        onProgress: @escaping @MainActor (String) -> Void
    ) async throws -> GameKitTransport {
        searchGeneration += 1
        let generation = searchGeneration
        onProgress("Finding players…")

        let request = MatchPool.request(for: kind, mode: mode)
        let box: UncheckedBox<GKMatch> = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                GKMatchmaker.shared().findMatch(for: request) { match, error in
                    if let match {
                        continuation.resume(returning: UncheckedBox(value: match))
                    } else {
                        continuation.resume(throwing: Self.failure(from: error))
                    }
                }
            }
        } onCancel: {
            GKMatchmaker.shared().cancel()
        }
        let match = box.value

        // A search the player backed out of, or that another replaced.
        guard generation == searchGeneration, !Task.isCancelled else {
            match.disconnect()
            throw Failure.cancelled
        }

        let transport = GameKitTransport(match: match)
        do {
            try await transport.awaitPeers(
                atLeast: kind.minPlayers(for: mode) - 1,
                settle: Self.formingSettleSeconds,
                cap: Self.formingCapSeconds,
                onProgress: onProgress)
        } catch {
            transport.disconnect()
            throw error
        }
        return transport
    }

    /// Stop looking. Safe to call with nothing pending.
    func cancelSearch() {
        searchGeneration += 1
        GKMatchmaker.shared().cancel()
    }

    /// A party's host asks GameKit to keep seating searchers from the same
    /// pool while the door is open. Whether GameKit does this on its own
    /// after `findMatch` returns is undocumented, so it is asked outright;
    /// if nobody arrives the party starts regardless once its door goes quiet.
    func keepFilling(_ transport: GameKitTransport, kind: RandomMatchKind, mode: GameMode = .battle) {
        let request = MatchPool.request(for: kind, mode: mode)
        GKMatchmaker.shared().addPlayers(to: transport.match, matchRequest: request) { _ in }
    }

    /// The door closes: no more players for this match. Every device says so
    /// as its countdown begins.
    func stopFilling(_ transport: GameKitTransport) {
        GKMatchmaker.shared().finishMatchmaking(for: transport.match)
    }

    private static func failure(from error: Error?) -> Failure {
        if let error = error as? GKError, error.code == .cancelled {
            return .cancelled
        }
        return .failed(error?.localizedDescription ?? "Game Center couldn't find a match.")
    }

    // MARK: Invites — the road that works everywhere

    /// Raise Game Center's own matchmaker, invite-only. Returns once the
    /// player has a match, or throws if they backed out. The room is sized
    /// for the game being played — eight for a Battle, four for Occupy.
    func findMatchByInvite(mode: GameMode = .battle) async throws -> GKMatch {
        let request = GKMatchRequest()
        request.minPlayers = mode == .occupy ? OCCUPY_MIN_PLAYERS : BATTLE_MIN_PLAYERS
        request.maxPlayers = mode == .occupy ? OCCUPY_MAX_PLAYERS : BATTLE_MAX_PLAYERS
        request.inviteMessage =
            mode == .occupy ? "Come play Occupy in Time Tiles." : "Come play a battle of Time Tiles."

        guard let controller = GKMatchmakerViewController(matchRequest: request) else {
            throw Failure.unavailable("Game Center couldn't open matchmaking.")
        }
        controller.matchmakingMode = .inviteOnly
        controller.matchmakerDelegate = self

        let box: UncheckedBox<GKMatch> = try await withCheckedThrowingContinuation {
            continuation in
            self.continuation = continuation
            self.presented = controller
            guard ModalPresenter.present(controller) else {
                self.finish(.failure(Failure.unavailable("Nowhere to show matchmaking.")))
                return
            }
        }
        return box.value
    }

    // MARK: Party codes — 26 and up

    /// Open a party and return the code to share. The match itself doesn't
    /// exist until `match(for:)` — players join the *party* first.
    @available(iOS 26, macOS 26, *)
    func hostParty() async throws -> (activity: GKGameActivity, code: String) {
        let definition = try await battleActivityDefinition()
        guard definition.supportsPartyCode else {
            throw Failure.unavailable("This build's battle activity has no party code.")
        }
        let activity = try GKGameActivity.start(definition: definition)
        guard let code = activity.partyCode else {
            throw Failure.unavailable("Game Center didn't issue a party code.")
        }
        return (activity, code)
    }

    /// Join someone else's party with a typed code.
    @available(iOS 26, macOS 26, *)
    func joinParty(code: String) async throws -> GKGameActivity {
        let cleaned = Self.normalizePartyCode(code)
        guard GKGameActivity.isValidPartyCode(cleaned) else {
            throw Failure.failed("That isn't a valid party code.")
        }
        let definition = try await battleActivityDefinition()
        return try GKGameActivity.start(definition: definition, partyCode: cleaned)
    }

    /// Turn a party — hosted or joined — into a live match.
    @available(iOS 26, macOS 26, *)
    func match(for activity: GKGameActivity) async throws -> GKMatch {
        let box: UncheckedBox<GKMatch> = try await withCheckedThrowingContinuation {
            continuation in
            activity.findMatch { match, error in
                if let match {
                    continuation.resume(returning: UncheckedBox(value: match))
                } else {
                    continuation.resume(
                        throwing: Failure.failed(
                            error?.localizedDescription ?? "The party didn't become a match."))
                }
            }
        }
        return box.value
    }

    @available(iOS 26, macOS 26, *)
    private func battleActivityDefinition() async throws -> GKGameActivityDefinition {
        try await withCheckedThrowingContinuation { continuation in
            GKGameActivityDefinition.loadGameActivityDefinitions(IDs: [Self.battleActivityID]) {
                definitions, error in
                if let definition = definitions?.first {
                    continuation.resume(returning: definition)
                } else {
                    continuation.resume(
                        throwing: Failure.unavailable(
                            error?.localizedDescription
                                ?? "No battle activity is configured in App Store Connect."))
                }
            }
        }
    }

    /// Uppercase, spaces stripped. Apple's format is two same-length parts
    /// joined by a dash, so — unlike the web's codes — the dash is meaningful
    /// and is left alone.
    static func normalizePartyCode(_ raw: String) -> String {
        raw.uppercased().filter { !$0.isWhitespace }
    }

    // MARK: Finishing

    private func finish(_ result: Result<UncheckedBox<GKMatch>, Error>) {
        if let presented {
            ModalPresenter.dismiss(presented)
            self.presented = nil
        }
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(with: result)
    }
}

/// The delegate protocol isn't main-actor isolated, so each callback hops on
/// explicitly rather than conforming across the boundary.
extension Matchmaking: GKMatchmakerViewControllerDelegate {
    nonisolated func matchmakerViewController(
        _ viewController: GKMatchmakerViewController, didFind match: GKMatch
    ) {
        let box = UncheckedBox(value: match)
        Task { @MainActor in self.finish(.success(box)) }
    }

    nonisolated func matchmakerViewControllerWasCancelled(
        _ viewController: GKMatchmakerViewController
    ) {
        Task { @MainActor in self.finish(.failure(Failure.cancelled)) }
    }

    nonisolated func matchmakerViewController(
        _ viewController: GKMatchmakerViewController, didFailWithError error: Error
    ) {
        let message = error.localizedDescription
        Task { @MainActor in self.finish(.failure(Failure.failed(message))) }
    }
}
