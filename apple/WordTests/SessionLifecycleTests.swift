import WordCore
import XCTest

@testable import Word

/// A cue sink that records instead of playing, so the model's audio contract
/// is testable without an audio device.
@MainActor
final class RecordingCues: GameCueSink {
    private(set) var played: [GameSound] = []
    func play(_ sound: GameSound) { played.append(sound) }
    func reset() { played = [] }
}

/// The cues fire off game events exactly where the web plays them.
@MainActor
final class GameCueTests: XCTestCase {
    private func playableModel(seed: String = "cues") -> (GameModel, RecordingCues) {
        let model = GameModel()
        let cues = RecordingCues()
        model.newGame(seed: seed, pace: .regular, now: .now)
        model.cues = cues
        return (model, cues)
    }

    func testLandingAWordSoundsTheCommitCue() async throws {
        let (model, cues) = playableModel()
        await model.loadDictionary()
        try TestPlays.placeOpener(on: model)
        XCTAssertEqual(cues.played, [.commit])
    }

    func testAClockDealSoundsTheDealCue() {
        let (model, cues) = playableModel()
        model.dismissSplash(at: .now)
        // Run the opening round out: its expiry deals the first drip batch.
        model.advanceClock(at: .now.addingTimeInterval(Double(endlessInitialSeconds(.regular)) + 1))
        XCTAssertTrue(cues.played.contains(.deal))
    }

    func testTheLastThreeSecondsTickOncePerSecond() {
        let (model, cues) = playableModel()
        let start = Date.now
        model.dismissSplash(at: start)
        let deadline = start.addingTimeInterval(Double(endlessInitialSeconds(.regular)))

        // The heartbeat runs at 4Hz; each of the last three seconds must sound
        // exactly one tick (App.tsx:1559–1569).
        var t = deadline.addingTimeInterval(-3.2)
        while t < deadline {
            model.advanceClock(at: t)
            t = t.addingTimeInterval(0.25)
        }
        XCTAssertEqual(cues.played.filter { $0 == .tick }.count, 3)
    }

    func testEnteringTheRedSoundsTheAlarmOnce() {
        let (model, cues) = playableModel()
        model.dismissSplash(at: .now)
        var now = Date.now.addingTimeInterval(Double(endlessInitialSeconds(.regular)) + 1)

        // Deal until the pile is in the red — but not full.
        var guard_ = 0
        while model.pileTone != .urgent, !model.isComplete, guard_ < 20 {
            model.advanceClock(at: now)
            now = now.addingTimeInterval(Double(endlessDripSeconds(model.dripsElapsed, .regular)) + 1)
            guard_ += 1
        }
        XCTAssertEqual(model.pileTone, .urgent)
        XCTAssertFalse(model.isComplete)
        XCTAssertEqual(cues.played.filter { $0 == .overflow }.count, 1, "one alarm per crossing")
    }

    func testTheEndOfTheGameSoundsTheLoseCue() {
        let (model, cues) = playableModel()
        model.finishGame(reason: .buried)
        XCTAssertTrue(cues.played.contains(.lose))
        // And exactly once, however many times the end is asserted.
        model.finishGame(reason: .buried)
        XCTAssertEqual(cues.played.filter { $0 == .lose }.count, 1)
    }
}

/// A solo game must survive process death (plan §6.1) — new on Apple
/// platforms, and the clock must come back honest.
@MainActor
final class SavedGameTests: XCTestCase {
    func testAnUntouchedOpeningBoardIsNotWorthSaving() {
        let model = GameModel()
        model.newGame(seed: "save", pace: .regular, now: .now)
        XCTAssertNil(model.savedGame(), "nothing has happened yet")
    }

    func testAPlayedGameRoundTripsThroughStorage() async throws {
        let store = MemoryStore()
        let model = GameModel()
        model.newGame(seed: "save", pace: .fast, now: .now)
        await model.loadDictionary()
        try TestPlays.placeOpener(on: model)

        guard let snapshot = model.savedGame() else { return XCTFail("expected a save") }
        snapshot.save(to: store)

        guard let loaded = SavedSoloGame.load(from: store) else {
            return XCTFail("expected to load the save")
        }
        XCTAssertEqual(loaded, snapshot)

        let restored = GameModel()
        restored.restore(loaded)
        XCTAssertEqual(restored.board, model.board)
        XCTAssertEqual(restored.rack, model.rack)
        XCTAssertEqual(restored.pace, .fast)
        XCTAssertEqual(restored.seed, "save")
        XCTAssertFalse(restored.isFirstWord, "the opener is down, so the next word borrows")
    }

    func testARestoredClockComesBackHeldAtItsRemainingTime() async throws {
        let store = MemoryStore()
        let model = GameModel()
        let start = Date(timeIntervalSince1970: 1_000)
        model.newGame(seed: "save", pace: .regular, now: start)
        model.dismissSplash(at: start)
        await model.loadDictionary()
        try TestPlays.placeOpener(on: model)

        // Put it away 30 seconds in.
        let away = start.addingTimeInterval(30)
        let before = model.remainingSeconds(at: away)
        guard let snapshot = model.savedGame(at: away) else { return XCTFail("expected a save") }
        snapshot.save(to: store)

        // Come back a day later: the round must not have expired, and no time
        // may have been charged for being away.
        let later = away.addingTimeInterval(86_400)
        let restored = GameModel()
        restored.restore(SavedSoloGame.load(from: store)!, now: later)
        XCTAssertEqual(restored.remainingSeconds(at: later), before)
        XCTAssertEqual(restored.splash, .resumed, "the resume card holds the clock")

        // And it doesn't deal the moment it's back — the card is still up.
        restored.advanceClock(at: later)
        XCTAssertEqual(restored.remainingSeconds(at: later), before)

        // Dismissing the card starts the clock from where it stopped.
        restored.dismissSplash(at: later)
        XCTAssertEqual(restored.remainingSeconds(at: later), before)
        XCTAssertEqual(restored.remainingSeconds(at: later.addingTimeInterval(5)), before! - 5)
    }

    func testGarbageAndStaleVersionsAreDroppedNotMigrated() {
        let store = MemoryStore(["nana.solo.save.v1": "{not json"])
        XCTAssertNil(SavedSoloGame.load(from: store))
        XCTAssertNil(store.get("nana.solo.save.v1"), "garbage is cleared out")

        var future = SavedSoloGame(
            seed: "x", pace: "regular", board: TileMap([("16,16", "a")]), rack: [],
            phase: "initial", dripsElapsed: 0, bankedBonus: 0, remainingSeconds: 10,
            dealSerial: 0, savedAt: 0)
        future.version = SavedSoloGame.version + 1
        future.save(to: store)
        XCTAssertNil(SavedSoloGame.load(from: store))
    }

    func testAFinishedGameIsNotAGameToComeBackTo() async throws {
        let model = GameModel()
        model.newGame(seed: "save", pace: .regular, now: .now)
        await model.loadDictionary()
        try TestPlays.placeOpener(on: model)
        XCTAssertNotNil(model.savedGame())
        model.finishGame(reason: .buried)
        XCTAssertNil(model.savedGame())
    }

    func testABattleIsNeverSaved() {
        let model = GameModel()
        model.newBattle(seed: "battle", selfID: "me")
        XCTAssertNil(model.savedGame(), "a battle is host-driven; there is nothing to come back to")
    }
}
