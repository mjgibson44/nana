import WordCore
import XCTest

@testable import Word

/// Prize cells, played through the real model: that gold only ever appears in
/// a game that asked for it, that it runs on wall time rather than the drip's
/// rounds, that a held clock doesn't charge it, and that claiming one pays
/// what the square said it would.
///
/// The rules themselves are argued out in `WordCoreTests/PrizesTests`; this is
/// about the wiring — the places the model has to remember prizes exist.
@MainActor
final class PrizePlayTests: XCTestCase {
    /// A game under a modifier with its opening word down and the clock
    /// running, so prizes can start appearing.
    private func playingModel(
        modifier: SoloModifier, seed: String = "gold"
    ) async throws -> (model: GameModel, start: Date) {
        let model = GameModel()
        let start = Date(timeIntervalSince1970: 1_000)
        model.newGame(seed: seed, pace: .regular, modifier: modifier, now: start)
        await model.loadDictionary()
        try TestPlays.placeOpener(on: model)
        model.dismissSplash(at: start)
        return (model, start)
    }

    /// Run the heartbeat forward at its real rate, so the model sees the
    /// deltas it would see on a device rather than one implausible leap.
    private func tick(_ model: GameModel, from start: Date, seconds: Double) {
        var now = start
        let end = start.addingTimeInterval(seconds)
        while now < end {
            now = min(end, now.addingTimeInterval(0.25))
            model.advanceClock(at: now)
        }
    }

    // MARK: Only when asked for

    func testAPlainSoloGameNeverLightsASquare() async throws {
        let (model, start) = try await playingModel(modifier: .none, seed: "clear")
        tick(model, from: start, seconds: 90)
        XCTAssertTrue(model.prizes.isEmpty, "a game nobody asked to light stays plain")
        XCTAssertEqual(model.modifier, .none)
    }

    func testABattleClearsAnyPrizesTheLastSoloGameLit() async throws {
        let (model, start) = try await playingModel(modifier: .prizes)
        tick(model, from: start, seconds: 30)
        XCTAssertFalse(model.prizes.isEmpty)

        model.newBattle(seed: "battle", selfID: "me", now: .now)
        XCTAssertTrue(model.prizes.isEmpty, "prizes are Solo's; a battle starts clean")
        XCTAssertEqual(model.modifier, .none)
    }

    func testTheDailyIsNeverModified() async throws {
        let (model, _) = try await playingModel(modifier: .prizes)
        try model.newDaily(dailyDeal(day: 20_500))
        XCTAssertEqual(model.modifier, .none)
        XCTAssertTrue(model.prizes.isEmpty)
    }

    // MARK: The clock

    func testASquareAppearsOnWallTimeNotOnTheDrip() async throws {
        // The opening phase is two minutes long at this pace, so nothing has
        // dripped yet — a prize that needed a round boundary would still be
        // waiting.
        let (model, start) = try await playingModel(modifier: .prizes)
        tick(model, from: start, seconds: PRIZE_FIRST_SPAWN_SECONDS + 1)
        XCTAssertEqual(model.dripsElapsed, 0, "no round has ended")
        XCTAssertEqual(model.prizes.prizes.count, 1)
    }

    func testASquareSitsWithinReachOfTheBoardAndOnEmptyGround() async throws {
        let (model, start) = try await playingModel(modifier: .prizes)
        tick(model, from: start, seconds: 60)
        XCTAssertFalse(model.prizes.isEmpty)
        for prize in model.prizes.prizes {
            XCTAssertNil(model.board[prize.key], "a prize only ever sits on an empty square")
            let cell = parseKey(prize.key)
            let near = model.board.keys.contains { key in
                let tile = parseKey(key)
                return max(abs(tile.row - cell.row), abs(tile.col - cell.col)) <= PRIZE_REACH
            }
            XCTAssertTrue(near, "\(prize.key) is out of reach of anything to build from")
        }
    }

    func testNeverMoreThanTheCeilingHowLongTheGameRuns() async throws {
        let (model, start) = try await playingModel(modifier: .prizes)
        tick(model, from: start, seconds: 240)
        XCTAssertLessThanOrEqual(model.prizes.prizes.count, PRIZE_MAX_LIVE)
    }

    func testASquareRunsOutAndCostsNothing() async throws {
        let (model, start) = try await playingModel(modifier: .prizes)
        tick(model, from: start, seconds: PRIZE_FIRST_SPAWN_SECONDS + 1)
        let lit = try XCTUnwrap(model.prizes.prizes.first?.key)
        let tiles = model.board.count
        let hand = model.rack.count
        let score = model.bankedBonus

        tick(
            model, from: start.addingTimeInterval(PRIZE_FIRST_SPAWN_SECONDS + 1),
            seconds: PRIZE_SECONDS + 1)

        XCTAssertFalse(model.prizes.isLit(lit), "its twenty seconds ran out")
        XCTAssertEqual(model.board.count, tiles, "an ignored prize takes nothing off the board")
        XCTAssertEqual(model.rack.count, hand, "…and puts nothing in the pile")
        XCTAssertEqual(model.bankedBonus, score)
    }

    func testAHeldClockIsNotChargedToASquaresTwentySeconds() async throws {
        // The one bug this shape of clock exists to prevent: a pause, or a
        // card the player is reading, must not spend a prize's life.
        let (model, start) = try await playingModel(modifier: .prizes)
        tick(model, from: start, seconds: PRIZE_FIRST_SPAWN_SECONDS + 1)
        let before = try XCTUnwrap(model.prizes.prizes.first)

        let paused = start.addingTimeInterval(PRIZE_FIRST_SPAWN_SECONDS + 1)
        model.pause(at: paused)
        tick(model, from: paused, seconds: 300)
        model.resume(at: paused.addingTimeInterval(300))

        let after = try XCTUnwrap(model.prizes.prize(at: before.key))
        XCTAssertEqual(after.secondsLeft, before.secondsLeft, accuracy: 0.5,
                       "five minutes behind a pause cost it nothing")
    }

    func testAnHourInAPocketExpiresEverythingRatherThanFloodingTheBoard() async throws {
        let (model, start) = try await playingModel(modifier: .prizes)
        tick(model, from: start, seconds: 60)
        XCTAssertFalse(model.prizes.isEmpty)

        // One tick, an hour later — what a suspended app comes back to.
        model.advanceClock(at: start.addingTimeInterval(3_660))
        XCTAssertLessThanOrEqual(model.prizes.prizes.count, 1, "no backlog is paid out")
    }

    // MARK: Claiming

    /// A square of a known kind, lit on an empty cell beside the board, so a
    /// test can say what it is claiming rather than take what the seed dealt.
    /// Both kinds are lit at random now, so a test that wanted a specific one
    /// would otherwise be a test of the RNG.
    private func light(
        _ kind: PrizeKind, on model: GameModel, secondsLeft: Double = PRIZE_SECONDS
    ) throws -> Prize {
        let anchor = try XCTUnwrap(model.board.keys.first)
        let cell = parseKey(anchor)
        let key = keyOf(cell.row - 1, cell.col)
        let prize = Prize(key: key, kind: kind, secondsLeft: secondsLeft)
        model.setPrizes(PrizeField(prizes: [prize]))
        return prize
    }

    func testGoldPaysWhatTheSquareSaidAndTheSquareIsGone() async throws {
        let (model, _) = try await playingModel(modifier: .prizes)
        let prize = try light(.points, on: model)
        let due = prizeValue(.points, prize)
        let before = model.bankedBonus

        // Claim it the way a landed word would, without needing the rack to
        // spell something that happens to reach: the model's claim runs off
        // the cells a word occupied.
        model.claimPrizes(covering: [prize.key])

        XCTAssertEqual(model.bankedBonus, before + due)
        XCTAssertEqual(model.prizesClaimed, 1)
        XCTAssertFalse(model.prizes.isLit(prize.key))
        XCTAssertNotNil(model.toast)
    }

    func testGoldPaysLessTheLongerItIsLeft() async throws {
        let (model, _) = try await playingModel(modifier: .prizes)
        let stale = try light(.points, on: model, secondsLeft: PRIZE_SECONDS / 2)
        XCTAssertLessThan(prizeValue(.points, stale), GOLD_TOP_POINTS)

        let before = model.bankedBonus
        model.claimPrizes(covering: [stale.key])
        XCTAssertEqual(model.bankedBonus - before, prizeValue(.points, stale))
        XCTAssertGreaterThanOrEqual(model.bankedBonus - before, GOLD_FLOOR_POINTS)
    }

    func testSalvageTakesTilesOffThePileRatherThanScoring() async throws {
        let (model, _) = try await playingModel(modifier: .prizes, seed: "salvage")
        let prize = try light(.relief, on: model)
        let due = prizeValue(.relief, prize)
        let hand = model.rack.count
        let score = model.bankedBonus
        XCTAssertGreaterThan(hand, due, "this test needs a pile deeper than the claim")

        model.claimPrizes(covering: [prize.key])

        XCTAssertEqual(model.rack.count, hand - due)
        XCTAssertEqual(model.bankedBonus, score, "salvage buys survival, not points")
        XCTAssertEqual(model.prizesClaimed, 1)
    }

    func testOneWordCanClaimBothKindsAtOnce() async throws {
        // The reason the two stopped being separate modifiers: they share a
        // board now, so a word that crosses one of each has to be paid in
        // both currencies rather than one of them.
        let (model, _) = try await playingModel(modifier: .prizes)
        let anchor = parseKey(try XCTUnwrap(model.board.keys.first))
        let gold = Prize(key: keyOf(anchor.row - 1, anchor.col), kind: .points)
        let blue = Prize(key: keyOf(anchor.row - 2, anchor.col), kind: .relief)
        model.setPrizes(PrizeField(prizes: [gold, blue]))
        let score = model.bankedBonus
        let hand = model.rack.count

        model.claimPrizes(covering: [gold.key, blue.key])

        XCTAssertEqual(model.bankedBonus, score + prizeValue(.points, gold))
        XCTAssertEqual(model.rack.count, hand - prizeValue(.relief, blue))
        XCTAssertEqual(model.prizesClaimed, 2)
        XCTAssertTrue(model.prizes.isEmpty)
    }

    func testSalvageNeverTakesMoreTilesThanThereAre() async throws {
        let (model, _) = try await playingModel(modifier: .prizes, seed: "salvage")
        let prize = try light(.relief, on: model)
        model.setPile(["a", "b"])

        model.claimPrizes(covering: [prize.key])
        XCTAssertTrue(model.rack.isEmpty, "it clears what's there and says so")
    }

    func testAWordThatLandsBesideASquareClaimsNothing() async throws {
        let (model, _) = try await playingModel(modifier: .prizes)
        let prize = try light(.points, on: model)
        let cell = parseKey(prize.key)
        let before = model.bankedBonus

        model.claimPrizes(covering: [keyOf(cell.row, cell.col + 1)])

        XCTAssertEqual(model.bankedBonus, before, "on the square, not beside it")
        XCTAssertTrue(model.prizes.isLit(prize.key))
    }

    func testAPlainGameClaimsNothingHoweverTheBoardIsLit() async throws {
        // The modifier is what pays, not the field: a `.none` game with a
        // prize somehow on it must not quietly score for one.
        let (model, _) = try await playingModel(modifier: .none, seed: "clear")
        model.setPrizes(PrizeField(prizes: [Prize(key: keyOf(0, 0))]))
        let before = model.bankedBonus
        model.claimPrizes(covering: [keyOf(0, 0)])
        XCTAssertEqual(model.bankedBonus, before)
        XCTAssertEqual(model.prizesClaimed, 0)
    }

    // MARK: The pile is the pile

    func testTheGaugeMeansTheSameThingUnderEveryModifier() {
        // Wildfire needed a bigger pile because it fed one. Neither kind of
        // square does: gold never touches the pile and salvage only ever
        // takes off it.
        for modifier in SoloModifier.allCases {
            let model = GameModel()
            model.newGame(seed: "gauge", pace: .regular, modifier: modifier, now: .now)
            XCTAssertEqual(model.pileLimit, PILE_LIMIT)
            XCTAssertEqual(model.pileWarn, PILE_WARN)
            XCTAssertEqual(model.pileUrgent, PILE_URGENT)
        }
    }

    // MARK: Surviving process death

    func testASavedGameComesBackWithItsSquaresAndTheirClocks() async throws {
        let (model, start) = try await playingModel(modifier: .prizes)
        tick(model, from: start, seconds: 30)
        let prizes = model.prizes
        XCTAssertFalse(prizes.isEmpty)

        let saved = try XCTUnwrap(model.savedGame())
        XCTAssertEqual(saved.soloModifier, .prizes)

        let store = MemoryStore()
        saved.save(to: store)
        let back = try XCTUnwrap(SavedSoloGame.load(from: store))

        let restored = GameModel()
        restored.restore(back)
        XCTAssertEqual(restored.modifier, .prizes)
        XCTAssertEqual(restored.prizes, prizes, "the same squares, with the seconds they had")
        XCTAssertEqual(restored.prizes.spawns, prizes.spawns, "and the same place in the stream")
    }

    func testARestoredSquareDoesNotAgeWhileTheResumeCardIsUp() async throws {
        let (model, start) = try await playingModel(modifier: .prizes)
        tick(model, from: start, seconds: 30)
        let saved = try XCTUnwrap(model.savedGame(at: start.addingTimeInterval(30)))

        let later = start.addingTimeInterval(86_400)
        let restored = GameModel()
        restored.restore(saved, now: later)
        let held = restored.prizes
        // A day away, and the card still up: the clock is held, so nothing
        // may have been charged to a prize for being gone.
        restored.advanceClock(at: later)
        XCTAssertEqual(restored.prizes, held)

        // Dismissing it starts them from where they stopped, not from zero.
        restored.dismissSplash(at: later)
        restored.advanceClock(at: later)
        XCTAssertEqual(restored.prizes, held, "the first tick after the card sets the anchor")
    }

    func testAPlainSavedGameComesBackPlain() async throws {
        let (model, _) = try await playingModel(modifier: .none, seed: "plain")
        let saved = try XCTUnwrap(model.savedGame())
        XCTAssertEqual(saved.soloModifier, .none)

        let restored = GameModel()
        restored.restore(saved)
        XCTAssertTrue(restored.prizes.isEmpty)
    }
}
