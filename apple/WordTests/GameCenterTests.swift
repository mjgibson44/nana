import Foundation
import GameKit
import WordCore
import XCTest

@testable import Word

/// What can be checked without an account.
///
/// The auth flow itself needs a real Apple ID on real hardware — there has
/// been no Game Center sandbox since 2016 (TN2417) — so what's pinned here is
/// the part §7.1 actually cares about: that being signed out never stops the
/// game, and that the door copy tells the truth about why.
@MainActor
final class GameCenterTests: XCTestCase {

    func testStartsIdleAndSignedOut() {
        let center = GameCenter()
        XCTAssertEqual(center.state, .idle)
        XCTAssertFalse(center.isSignedIn)
        XCTAssertFalse(center.canPlayOnline)
    }

    func testSignedOutExplainsTheBattleDoorWithoutBlockingAnythingElse() {
        let center = GameCenter()
        let reason = try? XCTUnwrap(center.battleBlockedReason)
        XCTAssertNotNil(reason)
        XCTAssertTrue(
            center.battleBlockedReason?.contains("Game Center") ?? false,
            "the door has to say what it needs")
    }

    func testRestrictedIsItsOwnStateBecauseRetryingWontHelp() {
        // Screen Time forbidding multiplayer is not the same as being signed
        // out: no amount of signing in changes it, so the copy differs.
        XCTAssertNotEqual(
            GameCenter.State.restricted, GameCenter.State.signedOut(reason: nil))
    }

    func testAuthenticatingIsNotSignedIn() {
        XCTAssertNotEqual(
            GameCenter.State.authenticating,
            GameCenter.State.signedIn(playerID: "x", name: "y"))
    }

    // MARK: The point of all of it — signed out, everything still plays

    func testEverythingButBattlePlaysSignedOut() {
        let center = GameCenter()
        XCTAssertFalse(center.isSignedIn)

        // Solo, the Daily Deal and the tutorial ask GameCenter nothing at all.
        let model = GameModel()
        model.newGame(pace: .regular)
        XCTAssertEqual(model.rack.count, ENDLESS_START_TILES)

        model.newDaily(deal: dailyDeal(at: .now))
        XCTAssertEqual(model.rack.count, DailyRules.tileCount)

        model.newTutorial()
        XCTAssertFalse(model.rack.isEmpty)
    }

    func testScoresEarnedSignedOutAreHeldAndFlushOnSignIn() async {
        // The §7.1 contract end to end, with a stand-in for GameKit.
        final class Submitter: ProgressionSubmitter, @unchecked Sendable {
            private(set) var submitted: [PendingScore] = []
            func submit(_ score: PendingScore) async -> Bool {
                submitted.append(score)
                return true
            }
            func report(_ achievement: AchievementProgress) async -> Bool { true }
        }

        let progression = Progression(store: MemoryStore())
        progression.record(
            GameOutcome(
                report: GameReport(mode: .endless, pace: .fast, score: 400),
                words: 5, tilesLeft: 0, bonusEarned: false, daily: nil))
        XCTAssertFalse(progression.pendingScores.isEmpty, "held while signed out")

        let submitter = Submitter()
        await progression.signedIn(as: submitter)
        XCTAssertTrue(progression.pendingScores.isEmpty, "and sent on sign-in")
        XCTAssertEqual(submitter.submitted.first?.board, .soloFast)
    }

    // MARK: Config the GameKit bundle has to agree with

    func testLeaderboardAndAchievementIDsAreStable() {
        // These strings are the contract with App Store Connect. Changing one
        // silently orphans a board or a badge.
        XCTAssertEqual(
            Set(LeaderboardID.allCases.map(\.rawValue)),
            ["solo.regular", "solo.fast", "daily.deal", "battle.wins"])
        XCTAssertEqual(AchievementID.allCases.count, 15)
        XCTAssertEqual(Set(AchievementID.allCases.map(\.rawValue)).count, 15)
    }

    func testTheEntitlementsDeclareGameCenterAndICloud() throws {
        // Cheap guard against a capability being dropped: the build would
        // still succeed and every submission would fail at runtime, on a
        // device, silently. Asserted against project.yml rather than the
        // generated plist — XcodeGen owns that file and rewrites it.
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("project.yml")
        let text = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(text.contains("com.apple.developer.game-center"))
        XCTAssertTrue(text.contains("com.apple.developer.ubiquity-kvstore-identifier"))
        XCTAssertTrue(text.contains("com.apple.security.network.client"))
    }
}
