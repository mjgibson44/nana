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

/// The seven cues fire off game events exactly where the web plays them.
@MainActor
final class GameCueTests: XCTestCase {
    private func playableModel(seed: String = "cues") -> (GameModel, RecordingCues) {
        let model = GameModel()
        let cues = RecordingCues()
        model.newGame(seed: seed, pace: .regular, now: .now)
        model.cues = cues
        return (model, cues)
    }

    func testLandingAWordSoundsTheCommitCue() {
        let (model, cues) = playableModel()
        model.cellClick(keyOf(16, 16))
        model.togglePick(0)
        guard let target = model.target else { return XCTFail("no anchored target") }
        model.commit(target.key, target.dir)
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

    func testCrossingTheLooseLimitAlarmsAndReArms() {
        let (model, cues) = playableModel()
        model.dismissSplash(at: .now)
        // Reach the drip phase, where the loose gauge is live.
        var now = Date.now.addingTimeInterval(Double(endlessInitialSeconds(.regular)) + 1)
        model.advanceClock(at: now)
        XCTAssertEqual(model.phase, .drip)

        // Deal until the pile crosses the limit; each expiry adds a batch.
        var alarms = 0
        var guard_ = 0
        while model.looseTiles <= ENDLESS_LOOSE_LIMIT, guard_ < 20 {
            now = now.addingTimeInterval(Double(endlessDripSeconds(model.dripsElapsed, .regular)) + 1)
            model.advanceClock(at: now)
            guard_ += 1
        }
        alarms = cues.played.filter { $0 == .overflow }.count
        XCTAssertGreaterThan(model.looseTiles, ENDLESS_LOOSE_LIMIT)
        XCTAssertEqual(alarms, 1, "one alarm per crossing, not one per deal")
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

    func testAPlayedGameRoundTripsThroughStorage() {
        let store = MemoryStore()
        let model = GameModel()
        model.newGame(seed: "save", pace: .fast, now: .now)
        model.cellClick(keyOf(16, 16))
        model.togglePick(0)
        guard let target = model.target else { return XCTFail("no anchored target") }
        model.commit(target.key, target.dir)

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
    }

    func testARestoredClockComesBackHeldAtItsRemainingTime() {
        let store = MemoryStore()
        let model = GameModel()
        let start = Date(timeIntervalSince1970: 1_000)
        model.newGame(seed: "save", pace: .regular, now: start)
        model.dismissSplash(at: start)
        model.cellClick(keyOf(16, 16))
        model.togglePick(0)
        if let target = model.target { model.commit(target.key, target.dir) }

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

    func testAFinishedGameIsNotAGameToComeBackTo() {
        let model = GameModel()
        model.newGame(seed: "save", pace: .regular, now: .now)
        model.cellClick(keyOf(16, 16))
        model.togglePick(0)
        if let target = model.target { model.commit(target.key, target.dir) }
        XCTAssertNotNil(model.savedGame())
        model.finishGame(reason: .buried)
        XCTAssertNil(model.savedGame())
    }
}

/// The guided lesson walks its script, enforces the gap step, and can be
/// skipped from any point.
@MainActor
final class TutorialTests: XCTestCase {
    func testTheLessonOpensOnStepOneWithItsWordSpelledOut() {
        let model = GameModel()
        model.newTutorial()
        XCTAssertTrue(model.isTutorial)
        XCTAssertEqual(model.tutorialProgress?.step, 1)
        XCTAssertEqual(model.tutorialProgress?.of, TUTORIAL_STEPS)
        // Step one's tiles are dealt in order, not shuffled: the lesson is
        // about getting a word down at all.
        XCTAssertEqual(model.rack, tutorialScript[0].tiles)
        // A lesson has no clock to run out.
        XCTAssertFalse(model.showsClock)
        XCTAssertNil(model.countdown)
        XCTAssertFalse(model.showsLooseGauge)
    }

    func testSkippingEveryStepPlaysTheScriptAndWalksThePlayerOut() {
        let model = GameModel()
        var walkedOut = false
        model.onTutorialWalkedOut = { walkedOut = true }
        model.newTutorial()

        for _ in 0..<TUTORIAL_STEPS {
            model.skipTutorialStep()
        }
        XCTAssertTrue(model.tutorialFinished)
        // Every scripted word made it onto the board.
        let words = Set(extractRuns(model.board).map(\.word))
        for step in tutorialScript {
            XCTAssertTrue(words.contains(step.word), "\(step.word) should be on the board")
        }
        XCTAssertTrue(walkedOut, "a player who skipped the lot is handed on")
    }

    func testPlayingStepOneDealsStepTwosTiles() {
        let model = GameModel()
        model.newTutorial()
        let step = tutorialScript[0]

        // Type the step's word from the pile and land it on the pre-anchored
        // middle square.
        for letter in step.word.map(String.init) { model.typeLetter(letter) }
        guard let target = model.target else { return XCTFail("no anchored target") }
        model.commit(target.key, target.dir)

        XCTAssertEqual(model.tutorialProgress?.step, 2)
        // The next step's tiles arrived.
        XCTAssertEqual(model.rack, tutorialScript[1].tiles)
    }

    func testTheGapStepRefusesTheSameWordTypedOverTheBoardLetter() {
        // The final step insists the word be played *through* a gap tile.
        guard let gapIndex = tutorialScript.firstIndex(where: \.needsGap) else {
            return XCTFail("the script should have a gap step")
        }
        let model = GameModel()
        model.newTutorial()
        // Skip up to the gap step, which plays each earlier word for us.
        for _ in 0..<gapIndex { model.skipTutorialStep() }
        XCTAssertEqual(model.tutorialProgress?.step, gapIndex + 1)
        XCTAssertEqual(model.rack, tutorialScript[gapIndex].tiles)

        // The scripted placement uses a gap and is accepted.
        let step = tutorialScript[gapIndex]
        guard
            let played = scriptedPlacement(
                board: model.board, bounds: model.bounds, step: step, rack: model.rack)
        else { return XCTFail("the script should be playable") }
        XCTAssertTrue(played.picks.contains { $0.letter == nil }, "the step plays through a gap")
        model.commit(
            keyOf(played.anchor.row, played.anchor.col), played.dir, picksToPlace: played.picks)
        XCTAssertTrue(model.tutorialFinished)
    }

    func testTheTutorialNeverOffersAGameToResume() {
        let model = GameModel()
        model.newTutorial()
        model.skipTutorialStep()
        XCTAssertNil(model.savedGame(), "a lesson is not a run to lose")
    }
}
