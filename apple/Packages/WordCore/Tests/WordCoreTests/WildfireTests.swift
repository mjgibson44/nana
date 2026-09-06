import Foundation
import Testing

@testable import WordCore

/// Wildfire has no TS counterpart, so these are the spec. The rules are the
/// whole risk in the mode — how fast it escalates, what an unanswered fire
/// costs, and what counts as answering one — so they get argued out here
/// before any of it reaches a screen.

/// An RNG that hands back a scripted sequence, cycling. `0` always picks the
/// first candidate and `0.99` the last, which is how these tests pin down
/// *which* cell a fire chose without caring how the choice is computed.
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

@Suite("Wildfire: how fast it comes")
struct WildfireEscalation {
    @Test("starts at one fire a round and grows to the ceiling")
    func growsToTheCeiling() {
        #expect(wildfireIgnitions(0) == WILDFIRE_FIRST_IGNITIONS)
        #expect(wildfireIgnitions(WILDFIRE_IGNITION_ROUNDS - 1) == 1)
        #expect(wildfireIgnitions(WILDFIRE_IGNITION_ROUNDS) == 2)
        #expect(wildfireIgnitions(WILDFIRE_IGNITION_ROUNDS * 2) == 3)
        #expect(wildfireIgnitions(10_000) == WILDFIRE_MAX_IGNITIONS)
    }

    @Test("a negative round index is still the opening rate")
    func negativeRoundsAreTheOpeningRate() {
        #expect(wildfireIgnitions(-5) == WILDFIRE_FIRST_IGNITIONS)
    }

    @Test("gives the pile more room than a clear board, because fire feeds it too")
    func givesThePileMoreRoom() {
        // The base is the app's to set; the relief is the rule's.
        #expect(hazardPileLimit(24, .none) == 24)
        #expect(hazardPileLimit(24, .wildfire) == 24 + WILDFIRE_PILE_RELIEF)
        #expect(WILDFIRE_PILE_RELIEF > 0)
    }
}

@Suite("Wildfire: where it catches")
struct WildfireIgnition {
    @Test("nothing catches on an empty board")
    func nothingCatchesOnAnEmptyBoard() {
        #expect(wildfireCandidates(board: TileMap(), fire: Wildfire()).isEmpty)

        let round = wildfireAdvance(Wildfire(), board: TileMap(), ignitions: 3, rng: scriptedRng([0]))
        #expect(round.lit.isEmpty)
        #expect(round.fire.isEmpty)
    }

    @Test("only empty cells touching a tile can catch")
    func onlyEmptyCellsTouchingATile() {
        let board = catBoard()
        let candidates = wildfireCandidates(board: board, fire: Wildfire())

        // Never on a tile.
        #expect(!candidates.contains(keyOf(5, 6)))
        // The cells around the word, and no others.
        #expect(candidates.contains(keyOf(4, 6)))
        #expect(candidates.contains(keyOf(6, 6)))
        #expect(candidates.contains(keyOf(5, 4)))
        #expect(candidates.contains(keyOf(5, 8)))
        // Two cells away is not touching.
        #expect(!candidates.contains(keyOf(3, 6)))
        // Diagonals don't touch either — fire moves the way words do.
        #expect(!candidates.contains(keyOf(4, 4)))
        // Each cell offered once, however many tiles it touches.
        #expect(Set(candidates).count == candidates.count)
    }

    @Test("never on dead ground, and never twice on the same cell")
    func neverOnDeadGroundOrAliveFire() {
        let board = catBoard()
        let fire = Wildfire(fires: [keyOf(4, 6)], scars: [keyOf(6, 6)])
        let candidates = wildfireCandidates(board: board, fire: fire)
        #expect(!candidates.contains(keyOf(6, 6)))
        #expect(!candidates.contains(keyOf(4, 6)))
        #expect(candidates.contains(keyOf(5, 4)))
    }

    @Test("lights the number of fires asked for, and stops when it runs out of room")
    func lightsWhatItIsAskedFor() {
        let board = catBoard()
        let round = wildfireAdvance(Wildfire(), board: board, ignitions: 3, rng: scriptedRng([0]))
        #expect(round.fire.fires.count == 3)
        #expect(round.lit.count == 3)
        #expect(Set(round.fire.fires).count == 3)  // never the same cell twice
        #expect(round.burnt.isEmpty)               // nothing was alight to burn

        // One tile in the middle of nowhere has four cells around it, so a
        // greedier round than that runs out of anywhere to catch.
        var lonely = TileMap()
        lonely[keyOf(0, 0)] = "z"
        let crowded = wildfireAdvance(Wildfire(), board: lonely, ignitions: 9, rng: scriptedRng([0]))
        #expect(crowded.fire.fires.count == 4)
    }
}

@Suite("Wildfire: the round of grace")
struct WildfireGrace {
    @Test("a fire lit this round does nothing until the next one")
    func freshFiresDoNothingYet() {
        let board = catBoard()
        let first = wildfireAdvance(Wildfire(), board: board, ignitions: 1, rng: scriptedRng([0]))
        #expect(first.burnt.isEmpty)
        #expect(first.scarred.isEmpty)
        #expect(first.fire.fires.count == 1)

        // …and then it resolves, on the very next round. Exactly one round of
        // grace, no more and no less.
        let second = wildfireAdvance(first.fire, board: board, ignitions: 0, rng: scriptedRng([0]))
        #expect(second.scarred == first.fire.fires)
        #expect(second.burnt.count == 1)
    }
}

@Suite("Wildfire: what an unanswered fire costs")
struct WildfireResolution {
    @Test("scars its own cell, takes a tile beside it, and moves on")
    func scarsBurnsAndSpreads() {
        let board = catBoard()
        // Alight directly above the 'a'.
        let fire = Wildfire(fires: [keyOf(4, 6)])
        let round = wildfireAdvance(fire, board: board, ignitions: 0, rng: scriptedRng([0]))

        // Dead ground where it sat.
        #expect(round.scarred == [keyOf(4, 6)])
        #expect(round.fire.isScarred(keyOf(4, 6)))
        // The only tile it touches is the 'a' — so that is the one it takes.
        #expect(round.burnt == [keyOf(5, 6)])
        #expect(round.returned == ["a"])
        // And it has moved somewhere new, which is not where it was.
        #expect(round.fire.fires.count == 1)
        #expect(round.fire.fires != [keyOf(4, 6)])
    }

    @Test("walks toward the board rather than off into open space")
    func walksTowardTheBoard() {
        let board = catBoard()
        // (3,6) touches nothing; its neighbours (4,6) and (2,6) differ — only
        // (4,6) is next to a tile, so that is where a fire there must go.
        let round = wildfireAdvance(
            Wildfire(fires: [keyOf(3, 6)]), board: board, ignitions: 0, rng: scriptedRng([0]))
        #expect(round.burnt.isEmpty)  // it touched no tiles this round
        #expect(round.fire.fires == [keyOf(4, 6)])
    }

    @Test("dies out when it is ringed by dead ground")
    func diesOutWhenRinged() {
        var board = TileMap()
        board[keyOf(0, 0)] = "z"
        let ringed = Wildfire(
            fires: [keyOf(1, 0)],
            scars: [keyOf(2, 0), keyOf(1, 1), keyOf(1, -1)]
        )
        let round = wildfireAdvance(ringed, board: board, ignitions: 0, rng: scriptedRng([0]))
        // (0,0) is a tile, the other three are dead — nowhere left to go.
        #expect(round.fire.fires.isEmpty)
        #expect(round.burnt == [keyOf(0, 0)])
    }

    @Test("two fires never end up sharing a cell, or sitting on dead ground")
    func firesNeverCollide() {
        let board = catBoard()
        var fire = Wildfire()
        let rng = seededRng("wildfire-collision-sweep")
        for round in 0..<40 {
            let step = wildfireAdvance(
                fire, board: board, ignitions: wildfireIgnitions(round), rng: rng)
            fire = step.fire
            #expect(Set(fire.fires).count == fire.fires.count)
            for cell in fire.fires {
                #expect(!fire.isScarred(cell))
                #expect(!board.contains(cell))
            }
        }
    }

    @Test("takes each tile at most once in a round, and reports the letters it took")
    func takesEachTileOnce() {
        let board = catBoard()
        // Fires above and below the same letter.
        let fire = Wildfire(fires: [keyOf(4, 6), keyOf(6, 6)])
        let round = wildfireAdvance(fire, board: board, ignitions: 0, rng: scriptedRng([0]))
        #expect(Set(round.burnt).count == round.burnt.count)
        #expect(round.returned.count == round.burnt.count)
        for (cell, letter) in zip(round.burnt, round.returned) {
            #expect(board[cell] == letter)
        }
    }
}

@Suite("Wildfire: putting one out")
struct WildfireDousing {
    @Test("a tile on the fire, or beside it, puts it out")
    func onOrBesideCounts() {
        let fire = Wildfire(fires: [keyOf(4, 6), keyOf(5, 4), keyOf(9, 9)])

        // On it.
        #expect(wildfireDouse(fire, played: [keyOf(4, 6)]).doused == [keyOf(4, 6)])
        // Beside it.
        #expect(wildfireDouse(fire, played: [keyOf(4, 5)]).doused == [keyOf(4, 6)])
        // Diagonally is not beside it.
        #expect(wildfireDouse(fire, played: [keyOf(3, 5)]).doused.isEmpty)
        // Two cells away is not either.
        #expect(wildfireDouse(fire, played: [keyOf(2, 6)]).doused.isEmpty)
    }

    @Test("a word puts out every fire it reaches, and leaves the rest alone")
    func aWordDousesWhatItReaches() {
        let fire = Wildfire(fires: [keyOf(4, 6), keyOf(5, 4), keyOf(9, 9)], scars: [keyOf(1, 1)])
        let word = [keyOf(5, 5), keyOf(5, 6), keyOf(5, 7)]
        let (after, doused) = wildfireDouse(fire, played: word)

        #expect(Set(doused) == [keyOf(4, 6), keyOf(5, 4)])
        #expect(after.fires == [keyOf(9, 9)])
        // Dousing never heals dead ground.
        #expect(after.scars == [keyOf(1, 1)])
    }

    @Test("pays for the trouble")
    func paysForTheTrouble() {
        #expect(wildfireDouseBonus(0) == 0)
        #expect(wildfireDouseBonus(2) == 2 * WILDFIRE_DOUSE_BONUS)
        #expect(wildfireDouseBonus(-1) == 0)
        // Worth about a four-letter word — enough that answering the board is
        // never a pure cost.
        #expect(WILDFIRE_DOUSE_BONUS >= wordScore("word"))
    }

    @Test("a doused fire is gone for good, not merely delayed")
    func dousedIsGone() {
        let board = catBoard()
        let lit = wildfireAdvance(Wildfire(), board: board, ignitions: 1, rng: scriptedRng([0]))
        let (after, doused) = wildfireDouse(lit.fire, played: lit.fire.fires)
        #expect(doused.count == 1)

        let next = wildfireAdvance(after, board: board, ignitions: 0, rng: scriptedRng([0]))
        #expect(next.burnt.isEmpty)
        #expect(next.scarred.isEmpty)
    }
}

@Suite("Wildfire: dead ground")
struct WildfireScars {
    @Test("nothing may be placed on a scar")
    func nothingMayBePlacedOnAScar() {
        let fire = Wildfire(fires: [keyOf(0, 0)], scars: [keyOf(2, 2)])
        #expect(wildfireAllows(fire, keyOf(1, 1)))
        #expect(!wildfireAllows(fire, keyOf(2, 2)))
        // A burning cell is still live ground — playing on it is how you put
        // it out.
        #expect(wildfireAllows(fire, keyOf(0, 0)))
    }

    @Test("a word has to clear every cell it would take")
    func aWordMustClearEveryCell() {
        let fire = Wildfire(scars: [keyOf(2, 2)])
        #expect(wildfireAllows(fire, cells: [keyOf(2, 0), keyOf(2, 1)]))
        #expect(!wildfireAllows(fire, cells: [keyOf(2, 1), keyOf(2, 2), keyOf(2, 3)]))
    }

    @Test("survives a round trip through the save file")
    func survivesASaveFile() throws {
        let fire = Wildfire(fires: [keyOf(4, 6), keyOf(1, 2)], scars: [keyOf(0, 0), keyOf(9, 9)])
        let data = try JSONEncoder().encode(fire)
        let back = try JSONDecoder().decode(Wildfire.self, from: data)
        #expect(back == fire)
        // The order fires caught in is part of the contract, not incidental.
        #expect(back.fires == fire.fires)
    }
}
