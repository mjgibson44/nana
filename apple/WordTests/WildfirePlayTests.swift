import WordCore
import XCTest

@testable import Word

/// Wildfire, played through the real model: that fire only ever appears in a
/// game that asked for it, that it lands on the round clock, that what it
/// burns comes back to the pile, and that dead ground stays dead.
///
/// The rules themselves are argued out in `WordCoreTests/WildfireTests`; this
/// is about the wiring — the places the model has to remember fire exists.
@MainActor
final class WildfirePlayTests: XCTestCase {
    /// A game under fire with its opening word down, and the clock run out
    /// once so the first fires have caught.
    private func burningModel(seed: String = "fire") async throws -> GameModel {
        let model = GameModel()
        model.newGame(seed: seed, pace: .regular, hazard: .wildfire, now: .now)
        await model.loadDictionary()
        try TestPlays.placeOpener(on: model)
        model.dismissSplash(at: .now)
        model.advanceClock(at: .now.addingTimeInterval(Double(endlessInitialSeconds(.regular)) + 1))
        return model
    }

    // MARK: Only when asked for

    func testAPlainSoloGameNeverCatchesFire() async throws {
        let model = GameModel()
        model.newGame(seed: "clear", pace: .regular, now: .now)
        await model.loadDictionary()
        try TestPlays.placeOpener(on: model)
        model.dismissSplash(at: .now)
        var now = Date.now.addingTimeInterval(Double(endlessInitialSeconds(.regular)) + 1)
        for _ in 0..<5 {
            model.advanceClock(at: now)
            now = now.addingTimeInterval(Double(ENDLESS_SLOW_SECONDS) + 1)
        }
        XCTAssertTrue(model.fire.isEmpty, "a game nobody asked to burn stays whole")
        XCTAssertEqual(model.pileLimit, PILE_LIMIT)
    }

    func testABattleClearsAnyFireTheLastSoloGameLit() async throws {
        let model = try await burningModel()
        XCTAssertFalse(model.fire.fires.isEmpty)
        model.newBattle(seed: "battle", selfID: "me", now: .now)
        XCTAssertTrue(model.fire.isEmpty, "fire is Solo's; a battle starts clean")
        XCTAssertEqual(model.hazard, .none)
    }

    // MARK: Catching

    func testFireCatchesOnTheRoundClock() async throws {
        let model = try await burningModel()
        // The opening round's expiry both deals the batch and lights the
        // board — one pulse, two consequences.
        XCTAssertEqual(model.fire.fires.count, wildfireIgnitions(0))
        for cell in model.fire.fires {
            XCTAssertNil(model.board[cell], "fire only ever sits on an empty square")
        }
    }

    func testFireNeverCatchesBeforeThereIsABoard() {
        let model = GameModel()
        model.newGame(seed: "empty", pace: .regular, hazard: .wildfire, now: .now)
        model.dismissSplash(at: .now)
        model.advanceClock(at: .now.addingTimeInterval(Double(endlessInitialSeconds(.regular)) + 1))
        // Nothing is down, so there is nowhere a fire could be answered.
        XCTAssertTrue(model.fire.fires.isEmpty)
    }

    func testGivesThePileMoreRoomThanAClearGame() {
        let model = GameModel()
        model.newGame(seed: "room", pace: .regular, hazard: .wildfire, now: .now)
        XCTAssertEqual(model.pileLimit, PILE_LIMIT + WILDFIRE_PILE_RELIEF)
        XCTAssertGreaterThan(model.pileUrgent, PILE_URGENT)
        XCTAssertEqual(model.pileLimit - model.pileUrgent, PILE_LIMIT - PILE_URGENT,
                       "the gauge's red still means the same distance from the end")
    }

    // MARK: Burning

    func testAnUnansweredFireTakesATileBackToThePile() async throws {
        let model = try await burningModel()
        let tilesOnBoard = model.board.count
        let inHand = model.rack.count
        XCTAssertFalse(model.fire.fires.isEmpty)

        // A second round, with the fires left alone: they have had their grace.
        model.advanceClock(
            at: .now.addingTimeInterval(
                Double(endlessInitialSeconds(.regular)) + Double(ENDLESS_SLOW_SECONDS) + 2))

        XCTAssertFalse(model.fire.scars.isEmpty, "burnt ground is left behind")
        XCTAssertLessThan(model.board.count, tilesOnBoard, "the board lost a tile")
        // The pile gained the burnt tile as well as the round's own batch.
        XCTAssertGreaterThan(model.rack.count, inHand + 1)
    }

    func testBurntGroundRefusesATile() async throws {
        let model = try await burningModel()
        // Scar a square by hand: what makes one is WordCore's business, and
        // what this is about is the model refusing to build on it. The square
        // is one beside the opener, so nothing but the scar can refuse it.
        let opener = try XCTUnwrap(model.board.keys.first)
        let beside = parseKey(opener)
        let target = Cell(row: beside.row + 1, col: beside.col)
        XCTAssertNil(model.board[keyOf(target.row, target.col)])

        model.setFire(Wildfire(scars: [keyOf(target.row, target.col)]))
        model.beginDrag(.rack(index: 0, letter: model.rack[0]), at: .zero)
        model.applyDrop(.cell(target))

        XCTAssertTrue(model.staged.isEmpty, "nothing may be put on dead ground")
        XCTAssertNotNil(model.toast)
    }

    func testLiveGroundStillTakesATile() async throws {
        // The same drop, with nothing burnt — so the refusal above is the
        // scar's doing and not the drop's.
        let model = try await burningModel()
        let opener = try XCTUnwrap(model.board.keys.first)
        let beside = parseKey(opener)
        let target = Cell(row: beside.row + 1, col: beside.col)

        model.setFire(Wildfire())
        model.beginDrag(.rack(index: 0, letter: model.rack[0]), at: .zero)
        model.applyDrop(.cell(target))

        XCTAssertEqual(model.staged.count, 1)
    }

    // MARK: Putting one out

    func testAWordBesideAFirePutsItOutAndScores() async throws {
        let model = try await burningModel()
        guard let burning = model.fire.fires.first else {
            throw XCTSkip("nothing caught this round")
        }
        let before = model.bankedBonus
        // Douse it the way a landed word would, without needing the rack to
        // spell something that happens to reach: the model's douse runs off
        // the cells a word occupied.
        model.douseFires(reachedBy: [burning])
        XCTAssertFalse(model.fire.isBurning(burning))
        XCTAssertEqual(model.bankedBonus, before + WILDFIRE_DOUSE_BONUS)
        XCTAssertEqual(model.firesDoused, 1)
    }

    func testADousedFireNeverBurns() async throws {
        let model = try await burningModel()
        let tilesOnBoard = model.board.count
        model.douseFires(reachedBy: model.fire.fires)
        XCTAssertTrue(model.fire.fires.isEmpty)

        model.advanceClock(
            at: .now.addingTimeInterval(
                Double(endlessInitialSeconds(.regular)) + Double(ENDLESS_SLOW_SECONDS) + 2))
        // The round lit new fires, but nothing from last round burned.
        XCTAssertTrue(model.fire.scars.isEmpty)
        XCTAssertEqual(model.board.count, tilesOnBoard)
    }

    // MARK: Surviving process death

    func testASavedGameComesBackStillBurning() async throws {
        let model = try await burningModel()
        let fire = model.fire
        XCTAssertFalse(fire.fires.isEmpty)

        let saved = try XCTUnwrap(model.savedGame())
        XCTAssertEqual(saved.soloHazard, .wildfire)

        let store = MemoryStore()
        saved.save(to: store)
        let back = try XCTUnwrap(SavedSoloGame.load(from: store))

        let restored = GameModel()
        restored.restore(back)
        XCTAssertEqual(restored.hazard, .wildfire)
        XCTAssertEqual(restored.fire, fire, "the same squares alight, the same ground lost")
        XCTAssertEqual(restored.pileLimit, PILE_LIMIT + WILDFIRE_PILE_RELIEF)
    }

    func testAPlainSavedGameComesBackPlain() async throws {
        let model = GameModel()
        model.newGame(seed: "plain", pace: .regular, now: .now)
        await model.loadDictionary()
        try TestPlays.placeOpener(on: model)
        let saved = try XCTUnwrap(model.savedGame())
        XCTAssertEqual(saved.soloHazard, .none)

        let restored = GameModel()
        restored.restore(saved)
        XCTAssertTrue(restored.fire.isEmpty)
        XCTAssertEqual(restored.pileLimit, PILE_LIMIT)
    }
}
