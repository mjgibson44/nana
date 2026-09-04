import Foundation
import WordCore
import XCTest

@testable import Word

final class SoloSessionTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_000)

    func testOpeningSplashAndPauseFreezeTheWallClock() {
        var session = SoloSession(pace: .regular, now: start)

        XCTAssertEqual(session.splash, .start)
        XCTAssertEqual(session.remaining(at: start.addingTimeInterval(500)), 120)
        XCTAssertNil(session.advance(at: start.addingTimeInterval(500)))

        session.dismissSplash(at: start)
        XCTAssertEqual(session.remaining(at: start.addingTimeInterval(30)), 90)

        session.pause(at: start.addingTimeInterval(30))
        XCTAssertTrue(session.paused)
        XCTAssertEqual(session.remaining(at: start.addingTimeInterval(500)), 90)
        XCTAssertNil(session.advance(at: start.addingTimeInterval(500)))

        session.resume(at: start.addingTimeInterval(500))
        XCTAssertFalse(session.paused)
        XCTAssertEqual(session.remaining(at: start.addingTimeInterval(589)), 1)
        XCTAssertEqual(session.advance(at: start.addingTimeInterval(590)), 5)
        XCTAssertEqual(session.phase, .drip)
        XCTAssertEqual(session.remaining(at: start.addingTimeInterval(590)), 45)
        XCTAssertNil(
            session.advance(at: start.addingTimeInterval(590)),
            "one wall-clock expiry must never deal twice")
    }

    func testTheClockOnlyDealsAndNeverEndsTheGame() {
        // The pile is the model's business: the clock has no opinion about
        // losing, however many tiles are out.
        var session = SoloSession(pace: .fast, now: start)
        session.dismissSplash(at: start)
        XCTAssertEqual(session.advance(at: start.addingTimeInterval(60)), 3)
        XCTAssertEqual(session.advance(at: start.addingTimeInterval(75)), 3)
        XCTAssertFalse(session.complete)
        XCTAssertNil(session.endReason)
    }

    func testFastBatchGrowthRaisesASplashAndHoldsTheNewRound() {
        var session = SoloSession(pace: .fast, now: start)
        session.dismissSplash(at: start)
        var expiry = start.addingTimeInterval(60)
        XCTAssertEqual(session.advance(at: expiry), 3)

        for elapsed in 1...8 {
            expiry = expiry.addingTimeInterval(15)
            XCTAssertEqual(session.advance(at: expiry), elapsed == 8 ? 4 : 3)
        }

        XCTAssertEqual(session.dripsElapsed, 8)
        XCTAssertEqual(session.splash, .speedUp(seconds: 15, tiles: 4))
        XCTAssertEqual(session.remaining(at: expiry.addingTimeInterval(100)), 15)
    }
}

@MainActor
final class SoloGameModelTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 2_000)

    func testTheClockDealsAndAFullPileEndsTheGame() {
        let model = GameModel()
        model.newGame(seed: "phase-2b-clock", pace: .fast, now: start)
        model.dismissSplash(at: start)
        let opening = model.rack.count

        var now = start.addingTimeInterval(60)
        model.advanceClock(at: now)
        XCTAssertEqual(model.phase, .drip)
        XCTAssertEqual(model.rack.count, opening + 3)
        XCTAssertFalse(model.isComplete)

        // Three tiles a round: the pile reaches the limit on the fourth.
        for _ in 0..<3 {
            now = now.addingTimeInterval(15)
            model.advanceClock(at: now)
        }
        XCTAssertGreaterThanOrEqual(model.rack.count, PILE_LIMIT)
        XCTAssertTrue(model.isComplete)
        XCTAssertTrue(model.showSummary)
        XCTAssertEqual(model.endReason, .buried)
        XCTAssertNil(model.countdown)
        XCTAssertFalse(model.canAcceptInput)
    }

    func testPauseAndResumePreserveStagedLetters() {
        let model = GameModel()
        model.newGame(seed: "phase-2b-pause", pace: .regular, now: start)
        model.dismissSplash(at: start)
        model.togglePick(0)
        let picks = model.picks

        model.pause(at: start.addingTimeInterval(15))
        XCTAssertTrue(model.isPaused)
        XCTAssertFalse(model.canAcceptInput)
        XCTAssertEqual(model.picks, picks)
        XCTAssertEqual(model.remainingSeconds(at: start.addingTimeInterval(500)), 105)

        model.resume(at: start.addingTimeInterval(500))
        XCTAssertFalse(model.isPaused)
        XCTAssertTrue(model.canAcceptInput)
        XCTAssertEqual(model.picks, picks)
        XCTAssertEqual(model.remainingSeconds(at: start.addingTimeInterval(604)), 1)
    }

    func testABattleCannotBePaused() {
        let model = GameModel()
        model.newBattle(seed: "battle", selfID: "me", now: start)
        XCTAssertFalse(model.canPause)
        model.pause(at: start)
        XCTAssertFalse(model.isPaused)
    }

    func testTheHeaderClockCountsToTheNextBatch() {
        let model = GameModel()
        model.newGame(seed: "clock", pace: .regular, now: start)
        model.dismissSplash(at: start)
        XCTAssertEqual(model.secondsToNextTiles(at: start.addingTimeInterval(10)), 110)

        let battle = GameModel()
        battle.newBattle(seed: "battle", selfID: "me", now: start)
        XCTAssertEqual(
            battle.secondsToNextTiles(at: start.addingTimeInterval(5)), BATTLE_DRIP_SECONDS - 5)
    }
}
