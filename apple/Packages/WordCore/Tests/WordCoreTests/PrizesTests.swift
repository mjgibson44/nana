import Foundation
import Testing

@testable import WordCore

/// Prize cells have no TS counterpart, so these are the spec. The rules are
/// the whole risk in the modifiers — how often a square appears, where it may
/// appear, what claiming one is worth and when — so they get argued out here
/// before any of it reaches a screen.

/// An RNG that hands back a scripted sequence, cycling. `0` always picks the
/// first candidate and `0.99` the last, which is how these tests pin down
/// *which* cell was chosen without caring how the choice is computed.
private func scriptedRng(_ values: [Double]) -> () -> Double {
    var index = 0
    return {
        defer { index += 1 }
        return values[index % values.count]
    }
}

/// A three-letter word across, from (5,5). Its cells are (5,5), (5,6), (5,7).
private func catBoard() -> TileMap {
    var board = TileMap()
    board[keyOf(5, 5)] = "c"
    board[keyOf(5, 6)] = "a"
    board[keyOf(5, 7)] = "t"
    return board
}

/// A field with its spawn clock wound right down, so one call lights a cell.
private func dueField(_ field: PrizeField = PrizeField()) -> PrizeField {
    var due = field
    due.untilNextSpawn = 0.01
    return due
}

@Suite("Prizes: what a claim is worth")
struct PrizeValueTests {
    @Test("full price the instant it appears")
    func fullPriceAtSpawn() {
        #expect(prizeValue(.points, secondsLeft: PRIZE_SECONDS) == GOLD_TOP_POINTS)
        #expect(prizeValue(.relief, secondsLeft: PRIZE_SECONDS) == SALVAGE_TOP_TILES)
        // A fresh prize carries a full life, so the two agree.
        #expect(prizeValue(.points, Prize(key: keyOf(0, 0))) == GOLD_TOP_POINTS)
    }

    @Test("the floor as it vanishes, never nothing")
    func theFloorAsItVanishes() {
        #expect(prizeValue(.points, secondsLeft: 0) == GOLD_FLOOR_POINTS)
        #expect(prizeValue(.relief, secondsLeft: 0) == SALVAGE_FLOOR_TILES)
        // A late scramble is rewarded rather than mocked.
        #expect(GOLD_FLOOR_POINTS > 0)
        #expect(SALVAGE_FLOOR_TILES > 0)
    }

    @Test("half the time left is half the prize")
    func halfTheTimeIsHalfThePrize() {
        // Linear on purpose: the player has to be able to price a square at a
        // glance, and that has to be a sentence rather than a graph.
        let half = prizeValue(.points, secondsLeft: PRIZE_SECONDS / 2)
        #expect(half == GOLD_FLOOR_POINTS + (GOLD_TOP_POINTS - GOLD_FLOOR_POINTS) / 2)
        #expect(half == 55)
        #expect(prizeValue(.relief, secondsLeft: PRIZE_SECONDS / 2) == 6)
    }

    @Test("only ever falls, as the seconds do")
    func onlyEverFalls() {
        for kind in [PrizeKind.points, .relief] {
            var last = prizeValue(kind, secondsLeft: PRIZE_SECONDS)
            for step in stride(from: PRIZE_SECONDS, through: 0, by: -0.25) {
                let now = prizeValue(kind, secondsLeft: step)
                #expect(now <= last)
                last = now
            }
        }
    }

    @Test("a nonsense clock is priced at the floor rather than trapping")
    func aNonsenseClockIsPricedAtTheFloor() {
        #expect(prizeValue(.points, secondsLeft: -100) == GOLD_FLOOR_POINTS)
        #expect(prizeValue(.points, secondsLeft: .nan) == GOLD_FLOOR_POINTS)
        #expect(prizeValue(.points, secondsLeft: .infinity) == GOLD_FLOOR_POINTS)
        // Above a full life is still only a full life.
        #expect(prizeValue(.points, secondsLeft: PRIZE_SECONDS * 10) == GOLD_TOP_POINTS)
    }

    @Test("gold can outbid the word already in your hand")
    func goldCanOutbidTheWordInHand() {
        // The entire reason the top price is what it is: a square worth less
        // than the word you were going to play changes no decisions.
        #expect(GOLD_TOP_POINTS > wordScore("letters"))
    }

    @Test("a round's claims add up")
    func aRoundsClaimsAddUp() {
        let claimed = [
            Prize(key: keyOf(1, 1), secondsLeft: PRIZE_SECONDS),
            Prize(key: keyOf(2, 2), secondsLeft: 0),
        ]
        #expect(prizeClaimValue(.points, claimed) == GOLD_TOP_POINTS + GOLD_FLOOR_POINTS)
        #expect(prizeClaimValue(.relief, []) == 0)
    }
}

@Suite("Prizes: where one appears")
struct PrizeSpawnTests {
    @Test("nothing appears on an empty board")
    func nothingAppearsOnAnEmptyBoard() {
        #expect(prizeCandidates(board: TileMap(), field: PrizeField()).isEmpty)

        let round = prizeAdvance(
            dueField(), board: TileMap(), delta: 1, rng: scriptedRng([0]))
        #expect(round.lit.isEmpty)
        #expect(round.field.isEmpty)
        // …but the clock is still reset, so an empty board builds up no debt
        // of spawns to pay out the moment a word lands.
        #expect(round.field.untilNextSpawn == PRIZE_SPAWN_SECONDS)
    }

    @Test("only empty cells within reach of a tile")
    func onlyEmptyCellsWithinReach() {
        let board = catBoard()
        let candidates = prizeCandidates(board: board, field: PrizeField())

        // Never on a tile.
        #expect(!candidates.contains(keyOf(5, 6)))
        // Beside one.
        #expect(candidates.contains(keyOf(4, 6)))
        // Diagonally — unlike fire, which only ever moved the way words do.
        #expect(candidates.contains(keyOf(4, 4)))
        // Out to the reach, and no further.
        #expect(candidates.contains(keyOf(5, 6 - PRIZE_REACH)))
        #expect(!candidates.contains(keyOf(5, 5 - PRIZE_REACH - 1)))
        #expect(!candidates.contains(keyOf(5 - PRIZE_REACH - 1, 6)))
        // Each cell offered once, however many tiles it is near.
        #expect(Set(candidates).count == candidates.count)
    }

    @Test("every candidate really is within reach of some tile")
    func everyCandidateIsWithinReach() {
        let board = catBoard()
        for key in prizeCandidates(board: board, field: PrizeField()) {
            let cell = parseKey(key)
            let near = board.keys.contains { tile in
                let at = parseKey(tile)
                return max(abs(at.row - cell.row), abs(at.col - cell.col)) <= PRIZE_REACH
            }
            #expect(near, "\(key) is out of reach of the board")
        }
    }

    @Test("never on a cell already lit")
    func neverOnACellAlreadyLit() {
        let board = catBoard()
        let field = PrizeField(prizes: [Prize(key: keyOf(4, 6))])
        #expect(!prizeCandidates(board: board, field: field).contains(keyOf(4, 6)))
    }

    @Test("lights one at a time, and stops at the ceiling")
    func lightsOneAtATime() {
        let board = catBoard()
        var field = dueField()
        // However long the gap, one call lights one square: a suspended app
        // must come back to a board, not a burst.
        let leap = prizeAdvance(field, board: board, delta: 3_600, rng: scriptedRng([0]))
        #expect(leap.lit.count == 1)

        // Wound down and run again until the board is full.
        for _ in 0..<10 {
            field = dueField(prizeAdvance(field, board: board, delta: 0.01, rng: scriptedRng([0])).field)
        }
        #expect(field.prizes.count == PRIZE_MAX_LIVE)
        #expect(Set(field.prizes.map(\.key)).count == field.prizes.count)
    }

    @Test("counts its spawns, so a restored game goes on where it left off")
    func countsItsSpawns() {
        let board = catBoard()
        let first = prizeAdvance(dueField(), board: board, delta: 0.01, rng: scriptedRng([0]))
        #expect(first.field.spawns == 1)
        // A tick that lights nothing doesn't move the stream on.
        let quiet = prizeAdvance(first.field, board: board, delta: 0.01, rng: scriptedRng([0]))
        #expect(quiet.field.spawns == 1)
    }

    @Test("the first one comes sooner than the rest")
    func theFirstComesSooner() {
        // So a game shows what the modifier does inside the opening phase
        // rather than a minute into a run.
        #expect(PrizeField().untilNextSpawn == PRIZE_FIRST_SPAWN_SECONDS)
        #expect(PRIZE_FIRST_SPAWN_SECONDS < PRIZE_SPAWN_SECONDS)
    }

    @Test("a spawn is deterministic in its rng")
    func aSpawnIsDeterministicInItsRng() {
        let board = catBoard()
        let a = prizeAdvance(dueField(), board: board, delta: 0.01, rng: seededRng("seed/prize/0"))
        let b = prizeAdvance(dueField(), board: board, delta: 0.01, rng: seededRng("seed/prize/0"))
        #expect(a.field == b.field)
    }
}

@Suite("Prizes: the clock")
struct PrizeClockTests {
    @Test("ages everything lit by the delta")
    func agesEverythingByTheDelta() {
        let field = PrizeField(prizes: [Prize(key: keyOf(4, 6), secondsLeft: 20)])
        let round = prizeAdvance(field, board: catBoard(), delta: 5, rng: scriptedRng([0]))
        #expect(round.field.prizes.first?.secondsLeft == 15)
        #expect(round.expired.isEmpty)
    }

    @Test("a square that runs out is gone, and costs nothing")
    func aSquareThatRunsOutIsGone() {
        let field = PrizeField(
            prizes: [Prize(key: keyOf(4, 6), secondsLeft: 2)], untilNextSpawn: 999)
        let round = prizeAdvance(field, board: catBoard(), delta: 3, rng: scriptedRng([0]))
        #expect(round.expired == [keyOf(4, 6)])
        #expect(round.field.prizes.isEmpty)
        // Nothing is owed for one left alone: it is an opportunity missed,
        // never a punishment. There is no other channel for one to arrive by.
        #expect(round.lit.isEmpty)
    }

    @Test("a whole life is exactly a whole life")
    func aWholeLifeIsAWholeLife() {
        let field = PrizeField(prizes: [Prize(key: keyOf(4, 6))], untilNextSpawn: 999)
        // A hair under, and it is still there to be claimed for the floor.
        let alive = prizeAdvance(
            field, board: catBoard(), delta: PRIZE_SECONDS - 0.01, rng: scriptedRng([0]))
        #expect(alive.field.prizes.count == 1)
        // Exactly its life, and it is gone.
        let gone = prizeAdvance(
            field, board: catBoard(), delta: PRIZE_SECONDS, rng: scriptedRng([0]))
        #expect(gone.field.prizes.isEmpty)
    }

    @Test("a tick with no time in it changes nothing")
    func aTickWithNoTimeChangesNothing() {
        // The heartbeat can hand this the same instant twice, and a held
        // clock hands it nothing at all.
        let field = PrizeField(prizes: [Prize(key: keyOf(4, 6), secondsLeft: 3)])
        for delta in [0.0, -5.0, Double.nan] {
            let round = prizeAdvance(field, board: catBoard(), delta: delta, rng: scriptedRng([0]))
            #expect(round.field == field)
            #expect(round.lit.isEmpty)
            #expect(round.expired.isEmpty)
        }
    }

    @Test("a long absence expires everything and owes nothing")
    func aLongAbsenceExpiresEverything() {
        // A phone in a pocket for an hour: the squares are gone, one is due
        // shortly, and no backlog was paid out.
        let field = PrizeField(prizes: [Prize(key: keyOf(4, 6)), Prize(key: keyOf(6, 6))])
        let round = prizeAdvance(field, board: catBoard(), delta: 3_600, rng: scriptedRng([0]))
        #expect(round.expired.count == 2)
        #expect(round.field.prizes.count == 1, "one lit, not an hour's worth")
        #expect(round.field.untilNextSpawn == PRIZE_SPAWN_SECONDS)
    }

    @Test("many small ticks age the same as one big one")
    func manySmallTicksAgeLikeOneBigOne() {
        // The heartbeat runs at 4Hz and the tests step in seconds; the two
        // must not drift, or a prize is worth something different depending
        // on who is watching it.
        let field = PrizeField(prizes: [Prize(key: keyOf(4, 6))], untilNextSpawn: 999)
        var stepped = field
        for _ in 0..<40 {
            stepped = prizeAdvance(
                stepped, board: catBoard(), delta: 0.25, rng: scriptedRng([0])
            ).field
        }
        let leapt = prizeAdvance(
            field, board: catBoard(), delta: 10, rng: scriptedRng([0])
        ).field
        let a = try! #require(stepped.prizes.first?.secondsLeft)
        let b = try! #require(leapt.prizes.first?.secondsLeft)
        #expect(abs(a - b) < 0.000_1)
    }
}

@Suite("Prizes: claiming one")
struct PrizeClaimTests {
    @Test("a tile on the square claims it — and beside it does not")
    func onTheSquareOnly() {
        let field = PrizeField(prizes: [Prize(key: keyOf(4, 6)), Prize(key: keyOf(9, 9))])

        #expect(prizeClaim(field, covering: [keyOf(4, 6)]).claimed.map(\.key) == [keyOf(4, 6)])
        // Beside it is nothing. The opposite of dousing a fire, and for the
        // opposite reason: a prize you stumble onto has asked nothing of you.
        #expect(prizeClaim(field, covering: [keyOf(4, 5)]).claimed.isEmpty)
        #expect(prizeClaim(field, covering: [keyOf(3, 6)]).claimed.isEmpty)
        #expect(prizeClaim(field, covering: []).claimed.isEmpty)
    }

    @Test("a word claims every square it lands on, and leaves the rest")
    func aWordClaimsWhatItLandsOn() {
        let field = PrizeField(
            prizes: [
                Prize(key: keyOf(5, 5)), Prize(key: keyOf(5, 7)), Prize(key: keyOf(9, 9)),
            ])
        let word = [keyOf(5, 5), keyOf(5, 6), keyOf(5, 7)]
        let (after, claimed) = prizeClaim(field, covering: word)

        #expect(Set(claimed.map(\.key)) == [keyOf(5, 5), keyOf(5, 7)])
        #expect(after.prizes.map(\.key) == [keyOf(9, 9)])
    }

    @Test("a claimed square is gone for good, not merely delayed")
    func aClaimedSquareIsGone() {
        let field = PrizeField(prizes: [Prize(key: keyOf(4, 6))], untilNextSpawn: 999)
        let (after, claimed) = prizeClaim(field, covering: [keyOf(4, 6)])
        #expect(claimed.count == 1)

        let next = prizeAdvance(after, board: catBoard(), delta: 1, rng: scriptedRng([0]))
        #expect(next.field.prizes.isEmpty)
        #expect(next.expired.isEmpty)
    }

    @Test("what it pays is read at the moment it is claimed")
    func pricedWhenClaimed() {
        // The whole mechanic: the same square pays the full price to the word
        // that goes straight for it and the floor to the one that gets round
        // to it.
        let key = keyOf(4, 6)
        let fresh = PrizeField(prizes: [Prize(key: key, secondsLeft: PRIZE_SECONDS)])
        let stale = PrizeField(prizes: [Prize(key: key, secondsLeft: 0.5)])
        let early = prizeClaimValue(.points, prizeClaim(fresh, covering: [key]).claimed)
        let late = prizeClaimValue(.points, prizeClaim(stale, covering: [key]).claimed)
        #expect(early == GOLD_TOP_POINTS)
        #expect(late < early)
        #expect(late >= GOLD_FLOOR_POINTS)
    }
}

@Suite("Prizes: what a modifier offers")
struct PrizeModifierTests {
    @Test("a clear board offers nothing")
    func aClearBoardOffersNothing() {
        #expect(SoloModifier.none.prize == nil)
    }

    @Test("each modifier buys exactly one thing")
    func eachModifierBuysOneThing() {
        #expect(SoloModifier.gold.prize == .points)
        #expect(SoloModifier.salvage.prize == .relief)
        // Every modifier but `none` lights squares — otherwise the setup row
        // would offer something the board never does.
        for modifier in SoloModifier.allCases where modifier != .none {
            #expect(modifier.prize != nil, "\(modifier) lights nothing")
        }
    }

    @Test("every modifier the sheet offers is a real one, and vice versa")
    func theSheetOffersEveryModifier() {
        #expect(Set(MODIFIER_OPTIONS.map(\.modifier)) == Set(SoloModifier.allCases))
        // Set in tiles, so a name past eight characters won't fit a phone.
        for option in MODIFIER_OPTIONS {
            #expect(option.name.count <= 8, "\(option.name) is too wide for the row")
        }
    }

    @Test("every modifier that changes the board has a card explaining it")
    func everyModifierHasACard() {
        for modifier in SoloModifier.allCases where modifier != .none {
            #expect(MODIFIER_INFO[modifier] != nil, "\(modifier) has no explainer")
            #expect(MODIFIER_NAMES[modifier]?.isEmpty == false)
        }
        // …and a clear board adds nothing to the pace's own name.
        #expect(MODIFIER_NAMES[SoloModifier.none] == "")
        #expect(MODIFIER_INFO[SoloModifier.none] == nil)
    }
}

@Suite("Prizes: surviving process death")
struct PrizePersistenceTests {
    @Test("a field survives a round trip through the save file")
    func survivesASaveFile() throws {
        let field = PrizeField(
            prizes: [Prize(key: keyOf(4, 6), secondsLeft: 12.5), Prize(key: keyOf(1, 2))],
            untilNextSpawn: 3.25,
            spawns: 7)
        let back = try JSONDecoder().decode(
            PrizeField.self, from: JSONEncoder().encode(field))
        #expect(back == field)
        // The order they appeared in is part of the contract, not incidental.
        #expect(back.prizes.map(\.key) == field.prizes.map(\.key))
        // And the seconds each had left, not a deadline — a game picked back
        // up tomorrow must not find them all expired on arrival.
        #expect(back.prizes[0].secondsLeft == 12.5)
        #expect(back.spawns == 7)
    }
}
