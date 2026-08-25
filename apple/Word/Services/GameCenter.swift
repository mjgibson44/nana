import Foundation
import GameKit
import Observation
import WordCore

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Game Center sign-in, and the honest handling of not being signed in.
///
/// Plan §7.1 is emphatic: **signed-out is a designed state, not an error.**
/// The web game needs no account, and the port must not regress that when auth
/// fails, is declined, or is restricted by Screen Time. So this service never
/// blocks anything: Solo, the tutorial and the Daily Deal play regardless,
/// scores are held by `Progression` and submitted if auth later succeeds, and
/// only Battle — which genuinely cannot work without an identity — asks for it.
///
/// Two GameKit details this exists to absorb:
///
///  - **The handler can fire more than once.** It is called again when the
///    player signs in or out from Settings, so it must be idempotent rather
///    than a one-shot.
///  - **It hands back a view controller to present**, and only sometimes.
///    Presenting it is how the player actually signs in; ignoring it leaves
///    them permanently signed out with no way forward.
///
/// **Unverified.** None of this has run against Game Center — there has been no
/// sandbox since 2016 (TN2417), so it needs a real Apple ID on real hardware.
@Observable @MainActor
final class GameCenter {
    enum State: Equatable {
        case idle
        case authenticating
        case signedIn(playerID: String, name: String)
        /// Declined, failed, or never attempted. Everything except Battle
        /// carries on exactly as before.
        case signedOut(reason: String?)
        /// Screen Time or a managed device forbids multiplayer. Distinct from
        /// signed-out because no amount of retrying will change it.
        case restricted
    }

    private(set) var state: State = .idle

    /// Where a submitted score should go once we're signed in.
    private weak var progression: Progression?

    var isSignedIn: Bool {
        if case .signedIn = state { return true }
        return false
    }

    /// Whether Battle can be offered at all.
    var canPlayOnline: Bool {
        isSignedIn && !GKLocalPlayer.local.isMultiplayerGamingRestricted
    }

    /// What to tell someone standing at the Battle door.
    var battleBlockedReason: String? {
        switch state {
        case .signedIn:
            return GKLocalPlayer.local.isMultiplayerGamingRestricted
                ? "Multiplayer is turned off for this device in Screen Time."
                : nil
        case .restricted:
            return "Multiplayer is turned off for this device in Screen Time."
        case .authenticating:
            return "Signing in to Game Center…"
        case .idle, .signedOut:
            return "Battle needs Game Center — sign in to play with friends."
        }
    }

    /// Begin authenticating. Safe to call more than once; GameKit replaces the
    /// handler and re-runs it.
    func authenticate(feeding progression: Progression) {
        self.progression = progression
        guard state != .authenticating else { return }
        state = .authenticating

        GKLocalPlayer.local.authenticateHandler = { [weak self] viewController, error in
            // Hop explicitly: GameKit doesn't promise which queue this is on,
            // and everything it touches is main-actor state.
            Task { @MainActor in
                self?.handle(viewController: viewController, error: error)
            }
        }
    }

    private func handle(viewController: AuthViewController?, error: Error?) {
        if let viewController {
            // The player isn't signed in and GameKit is offering the sheet
            // that lets them. Not presenting it is what strands people.
            present(viewController)
            state = .signedOut(reason: nil)
            return
        }

        let player = GKLocalPlayer.local
        if player.isAuthenticated {
            // Note this stays `signedIn` even when multiplayer is restricted:
            // leaderboards and achievements work fine, and it's only Battle
            // that has to be turned away (`battleBlockedReason`).
            state = .signedIn(playerID: player.gamePlayerID, name: player.displayName)
            if let progression {
                Task { await progression.signedIn(as: GameKitSubmitter()) }
            }
            return
        }

        // Declined, offline, or failed. All the same to the player: carry on.
        state = .signedOut(reason: error?.localizedDescription)
        progression?.signedOut()
    }

    // MARK: Presenting the sign-in sheet

    typealias AuthViewController = ModalPresenter.ViewController

    /// `ModalPresenter` refuses when something is already up, which is what
    /// keeps the handler firing twice from stacking two sign-in sheets.
    private func present(_ viewController: AuthViewController) {
        ModalPresenter.present(viewController)
    }
}

/// `ProgressionSubmitter` over the real Game Center.
///
/// Both calls are idempotent by design — a leaderboard keeps the best score and
/// an achievement ignores a report lower than what it holds — which is what
/// lets `Progression` queue first and send afterwards without worrying about
/// sending something twice.
struct GameKitSubmitter: ProgressionSubmitter {
    func submit(_ score: PendingScore) async -> Bool {
        guard GKLocalPlayer.local.isAuthenticated else { return false }
        do {
            try await GKLeaderboard.submitScore(
                score.score,
                // `context` is a 64-bit annotation on a submission, not
                // something Game Center aggregates. The day a recurring score
                // belongs to is the useful thing to stamp on it.
                context: score.day.map { $0 < 0 ? 0 : Int($0) } ?? 0,
                player: GKLocalPlayer.local,
                leaderboardIDs: [score.board.rawValue])
            return true
        } catch {
            // Left queued; the next flush tries again.
            return false
        }
    }

    func report(_ achievement: AchievementProgress) async -> Bool {
        guard GKLocalPlayer.local.isAuthenticated else { return false }
        let report = GKAchievement(identifier: achievement.id.rawValue)
        report.percentComplete = achievement.percentComplete
        report.showsCompletionBanner = true
        do {
            try await GKAchievement.report([report])
            return true
        } catch {
            return false
        }
    }
}

/// iCloud key-value storage behind `WordCore`'s `SyncStore` (plan §9.1).
///
/// Deliberately last-writer-wins-proof by *construction* rather than by
/// conflict resolution: each device writes only its own key, so two devices
/// can never contend for one. See `Progress.swift` for why that matters.
struct UbiquitousSyncStore: SyncStore {
    private let store = NSUbiquitousKeyValueStore.default

    func data(forKey key: String) -> String? {
        store.string(forKey: key)
    }

    func set(_ value: String, forKey key: String) {
        store.set(value, forKey: key)
    }

    func keys(withPrefix prefix: String) -> [String] {
        store.dictionaryRepresentation.keys.filter { $0.hasPrefix(prefix) }.sorted()
    }

    @discardableResult
    func synchronize() -> Bool {
        // False means "not now", never an error worth showing: the game is
        // fully playable unsynced, and the local blob is authoritative anyway.
        store.synchronize()
    }
}
