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
        XCTAssertEqual(
            session.advance(at: start.addingTimeInterval(500), looseTiles: 99), .none)

        session.dismissSplash(at: start)
        XCTAssertEqual(session.remaining(at: start.addingTimeInterval(30)), 90)

        session.pause(at: start.addingTimeInterval(30))
        XCTAssertTrue(session.paused)
        XCTAssertEqual(session.remaining(at: start.addingTimeInterval(500)), 90)
        XCTAssertEqual(
            session.advance(at: start.addingTimeInterval(500), looseTiles: 99), .none)

        session.resume(at: start.addingTimeInterval(500))
        XCTAssertFalse(session.paused)
        XCTAssertEqual(session.remaining(at: start.addingTimeInterval(589)), 1)
        XCTAssertEqual(
            session.advance(at: start.addingTimeInterval(590), looseTiles: 99),
            .deal(tiles: 5))
        XCTAssertEqual(session.phase, .drip)
        XCTAssertEqual(session.remaining(at: start.addingTimeInterval(590)), 45)
        XCTAssertEqual(
            session.advance(at: start.addingTimeInterval(590), looseTiles: 99), .none,
            "one wall-clock expiry must never deal twice")
    }

    func testGoingOverLimitOnlyEndsAtADripDeadline() {
        var session = SoloSession(pace: .fast, now: start)
        session.dismissSplash(at: start)

        // The opening expiry starts the drip phase even if the opening pile
        // itself is over the eventual loose-tile limit.
        XCTAssertEqual(
            session.advance(at: start.addingTimeInterval(60), looseTiles: 99),
            .deal(tiles: 3))
        XCTAssertFalse(session.complete)

        XCTAssertEqual(
            session.advance(at: start.addingTimeInterval(75), looseTiles: 21), .buried)
        XCTAssertTrue(session.complete)
        XCTAssertEqual(session.endReason, .buried)
        XCTAssertNil(session.countdown)
    }

    func testFastBatchGrowthRaisesASplashAndHoldsTheNewRound() {
        var session = SoloSession(pace: .fast, now: start)
        session.dismissSplash(at: start)
        var expiry = start.addingTimeInterval(60)
        XCTAssertEqual(session.advance(at: expiry, looseTiles: 0), .deal(tiles: 3))

        for elapsed in 1...8 {
            expiry = expiry.addingTimeInterval(15)
            let effect = session.advance(at: expiry, looseTiles: 0)
            XCTAssertEqual(effect, .deal(tiles: elapsed == 8 ? 4 : 3))
        }

        XCTAssertEqual(session.dripsElapsed, 8)
        XCTAssertEqual(session.splash, .speedUp(seconds: 15, tiles: 4))
        XCTAssertEqual(session.remaining(at: expiry.addingTimeInterval(100)), 15)
    }
}

@MainActor
final class SoloGameModelTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 2_000)

    func testClockDealSurvivesUndoAndNextDeadlineCanBuryThePile() {
        let model = GameModel()
        model.newGame(seed: "phase-2b-clock", pace: .fast, now: start)
        model.dismissSplash(at: start)

        let originalCount = model.rack.count
        model.togglePick(0)
        XCTAssertTrue(model.handle(.confirm))
        XCTAssertEqual(model.rack.count, originalCount - 1)

        model.advanceClock(at: start.addingTimeInterval(60))
        XCTAssertEqual(model.phase, .drip)
        XCTAssertEqual(model.rack.count, originalCount + 2)

        model.undo()
        XCTAssertTrue(model.board.isEmpty)
        XCTAssertEqual(
            model.rack.count, originalCount + 3,
            "undo restores the move but keeps every clock-dealt tile")

        model.advanceClock(at: start.addingTimeInterval(75))
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

    func testBoardClearBanksBonusAndRefillsWithoutChangingScore() async throws {
        let model = GameModel()
        model.newGame(seed: "hello", pace: .regular, now: start)
        await model.loadDictionary()
        let puzzle = try generatePuzzle(
            wordPool: commonWords, tileCount: ENDLESS_START_TILES, rng: seededRng("hello"))
        let solution = try XCTUnwrap(puzzle.solution)

        for (key, letter) in solution.entries {
            let index = findAvailable(rack: model.rack, letter: letter, taken: [])
            XCTAssertNotEqual(index, -1)
            model.cellClick(key)
            model.togglePick(index)
            if let target = model.target { model.commit(target.key, target.dir) }
        }

        XCTAssertTrue(model.rack.isEmpty)
        XCTAssertTrue(model.boardClearReady)
        let scoreWithLiveBonus = model.score

        model.claimBoardClear()
        XCTAssertEqual(model.bankedBonus, ENDLESS_CONNECT_BONUS)
        XCTAssertEqual(model.rack.count, ENDLESS_CLEAR_TILES)
        XCTAssertEqual(model.score, scoreWithLiveBonus)

        model.finishGame(reason: .buried)
        XCTAssertEqual(model.finalScore, scoreWithLiveBonus)
        XCTAssertFalse(model.finalWords.isEmpty)
        XCTAssertTrue(model.showSummary)
    }
}
