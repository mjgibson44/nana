import Foundation
import GameKit
import WordCore

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Forming a battle: getting from "I want to play with my friends" to a live
/// `GKMatch` (plan §7.3).
///
/// Two roads, ranked by what the player's OS can do:
///
///  1. **Party codes (26+)** — `GKGameActivity` generates a short shareable
///     code and URL that the system understands, and `findMatch` turns the
///     party into a `GKMatch`. This is the OS-blessed version of the web
///     game's typed join codes. Note the code *format* is Apple's, not ours:
///     two same-length parts joined by a dash, so `newBattleCode`'s five
///     letters don't apply here.
///  2. **Invites (everywhere)** — `GKMatchmakerViewController` in invite-only
///     mode: friends, Messages threads, nearby players. Ships on every OS the
///     app supports, and stays the fallback below 26.
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

    private var continuation: CheckedContinuation<UncheckedBox<GKMatch>, Error>?
    private var presented: GKMatchmakerViewController?

    // MARK: Invites — the road that works everywhere

    /// Raise Game Center's own matchmaker, invite-only. Returns once the
    /// player has a match, or throws if they backed out.
    func findMatchByInvite() async throws -> GKMatch {
        let request = GKMatchRequest()
        request.minPlayers = BATTLE_MIN_PLAYERS
        request.maxPlayers = BATTLE_MAX_PLAYERS
        request.inviteMessage = "Come play a battle of Time Tiles."

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
