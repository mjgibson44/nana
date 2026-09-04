import Testing
@testable import WordCore

/// Ported from `src/game/__tests__/battle.test.ts`.

/// The TS suite builds bare `Contestant` objects; this struct is the Swift
/// equivalent, conforming to `OutOrdered` so it serves both the referee and
/// the standings.
private struct TestContestant: OutOrdered, Equatable {
    var score = 0
    var buried = false
    var left = false
    var waiting = false
    var outOrder: Int? = nil
}

private func player(
    score: Int = 0, buried: Bool = false, left: Bool = false, waiting: Bool = false
) -> TestContestant {
    TestContestant(score: score, buried: buried, left: left, waiting: waiting)
}

private func isLowercase(_ s: String) -> Bool {
    !s.isEmpty && s.allSatisfy { $0 >= "a" && $0 <= "z" }
}

@Suite("Battle: seededRng") struct BattleSeededRng {
    @Test("repeats exactly for the same seed")
    func repeatsExactlyForTheSameSeed() {
        let a = seededRng("pepper")
        let b = seededRng("pepper")
        for _ in 0..<1000 {
            #expect(a() == b())
        }
    }

    @Test("differs between seeds and stays in [0, 1)")
    func differsBetweenSeedsAndStaysInZeroToOne() {
        let a = seededRng("pepper")
        let b = seededRng("peppes")
        var same = 0
        for _ in 0..<1000 {
            let x = a()
            let y = b()
            #expect(x >= 0)
            #expect(x < 1)
            if x == y { same += 1 }
        }
        #expect(same < 5)
    }
}

@Suite("Battle: createTileStream") struct BattleCreateTileStream {
    @Test("deals identical batches to every stream with the same seed")
    func dealsIdenticalBatchesToEveryStreamWithTheSameSeed() {
        // The real battle pattern: an opening 20, then fives for a long game —
        // however a player earns them, batch N is batch N.
        let counts = [20, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5]
        for round in 0..<5 {
            let seed = "game-\(round)"
            let a = TileStream(seed: seed)
            let b = TileStream(seed: seed)
            for count in counts {
                let batchA = a.next(count)
                let batchB = b.next(count)
                #expect(batchA.count == count)
                #expect(isLowercase(batchA.joined()))
                #expect(batchA == batchB)
            }
        }
    }

    @Test("deals the same letter sequence however the requests are sized")
    func dealsTheSameLetterSequenceHoweverTheRequestsAreSized() {
        // Late-game drips grow to eights and tens while pile-clears stay at
        // five, so two players' request sizes interleave differently. The
        // letters must not: same seed, same sequence, just cut differently.
        let seed = "chunky"
        let a = TileStream(seed: seed)
        let b = TileStream(seed: seed)
        #expect(a.next(20) == b.next(20))
        let lettersA = [5, 8, 5, 10, 8].flatMap { a.next($0) }
        let lettersB = [8, 5, 5, 8, 10].flatMap { b.next($0) }
        #expect(lettersA == lettersB)
    }

    @Test("deals different games for different seeds")
    func dealsDifferentGamesForDifferentSeeds() {
        let a = TileStream(seed: "seed-one").next(20)
        let b = TileStream(seed: "seed-two").next(20)
        #expect(a.joined() != b.joined())
    }

    @Test("serves requests smaller than a word — attacks ask for one tile")
    func servesRequestsSmallerThanAWordAttacksAskForOneTile() {
        let stream = TileStream(seed: "attacks")
        #expect(stream.next(1).count == 1)
        #expect(stream.next(2).count == 2)
        #expect(stream.next(4).count == 4)
        for letter in stream.next(1) {
            #expect(letter.count == 1 && isLowercase(letter))
        }
    }
}

@Suite("Battle: battle codes") struct BattleCodes {
    @Test("generates valid codes")
    func generatesValidCodes() {
        for _ in 0..<100 {
            #expect(isValidBattleCode(newBattleCode()) == true)
        }
    }

    @Test("generates letters only — never a digit")
    func generatesLettersOnlyNeverADigit() {
        for _ in 0..<200 {
            let code = newBattleCode()
            #expect(code.count == CODE_LENGTH && code.allSatisfy { $0 >= "A" && $0 <= "Z" })
        }
    }

    @Test("forgives spacing and case, and drops characters no code contains")
    func forgivesSpacingAndCaseAndDropsCharactersNoCodeContains() {
        #expect(normalizeBattleCode("  ab-cde ") == "ABCDE")
        #expect(normalizeBattleCode("ab cd e") == "ABCDE")
        #expect(normalizeBattleCode("a0cd1") == "ACD")
    }

    @Test("rejects the wrong shape")
    func rejectsTheWrongShape() {
        #expect(isValidBattleCode("") == false)
        #expect(isValidBattleCode("AB") == false)
        #expect(isValidBattleCode("ABCD") == false)
        #expect(isValidBattleCode("A1C") == false) // digits are out entirely
        #expect(isValidBattleCode("AIC") == false) // I is not in the alphabet
        #expect(isValidBattleCode("ABC") == true) // three letters is the shape
    }
}

@Suite("Battle: battleOver / battleWinner") struct BattleOverBattleWinner {
    @Test("is not decided before two players are dealt in")
    func isNotDecidedBeforeTwoPlayersAreDealtIn() {
        #expect(battleOver([player()]) == false)
        #expect(battleOver([player(), player(waiting: true)]) == false)
    }

    @Test("plays on while two players are alive")
    func playsOnWhileTwoPlayersAreAlive() {
        #expect(battleOver([player(), player()]) == false)
    }

    @Test("ends the moment the field is down to one, and names the survivor")
    func endsTheMomentTheFieldIsDownToOneAndNamesTheSurvivor() {
        let survivor = player(score: 12)
        let players = [survivor, player(buried: true)]
        #expect(battleOver(players) == true)
        #expect(battleWinner(players) == survivor)
    }

    @Test("ends when the last rival leaves for good")
    func endsWhenTheLastRivalLeavesForGood() {
        let survivor = player()
        let players = [survivor, player(left: true)]
        #expect(battleOver(players) == true)
        #expect(battleWinner(players) == survivor)
    }

    @Test("calls a draw when everyone is gone")
    func callsADrawWhenEveryoneIsGone() {
        let players = [player(buried: true), player(buried: true)]
        #expect(battleOver(players) == true)
        #expect(battleWinner(players) == nil)
    }

    @Test("referees a full field of eight: last one standing")
    func refereesAFullFieldOfEightLastOneStanding() {
        // Seven of eight down — the game runs until exactly one is left.
        func field(_ alive: Int) -> [TestContestant] {
            (0..<8).map { player(buried: $0 >= alive) }
        }
        #expect(battleOver(field(3)) == false)
        #expect(battleOver(field(2)) == false)
        let done = field(1)
        #expect(battleOver(done) == true)
        #expect(battleWinner(done) == done[0])
    }
}

@Suite("Battle: rankByElimination") struct BattleRankByElimination {
    fileprivate func faller(_ outOrder: Int?, buried: Bool? = nil, left: Bool = false) -> TestContestant {
        var p = player(buried: buried ?? (outOrder != nil), left: left)
        p.outOrder = outOrder
        return p
    }

    @Test("leads with the survivor and walks back through the falls")
    func leadsWithTheSurvivorAndWalksBackThroughTheFalls() {
        let winner = faller(nil)
        let first = faller(1)
        let second = faller(2)
        let third = faller(3)
        let ranked = rankByElimination([first, third, winner, second])
        #expect(ranked.map(\.player) == [winner, third, second, first])
        #expect(ranked.map(\.rank) == [1, 2, 3, 4])
    }

    @Test("shares the top rank in a draw where nobody survived")
    func sharesTheTopRankInADrawWhereNobodySurvived() {
        // The theoretical draw: the last two went down together, so the two
        // never-marked entries would both be survivors — but here everyone
        // fell, and the two who share an outOrder share a rank.
        let ranked = rankByElimination([faller(nil), faller(nil), faller(1)])
        #expect(ranked.map(\.rank) == [1, 1, 3])
    }

    @Test("ranks a leaver by when they left, like any other fall")
    func ranksALeaverByWhenTheyLeftLikeAnyOtherFall() {
        let winner = faller(nil)
        let quitter = faller(1, buried: false, left: true)
        let fighter = faller(2)
        let ranked = rankByElimination([quitter, winner, fighter])
        #expect(ranked.map(\.player) == [winner, fighter, quitter])
    }
}

@Suite("Battle: battleWinners") struct BattleWinnersTests {
    func seat(
        _ id: String, score: Int = 0, buried: Bool = false,
        waiting: Bool = false, outOrder: Int? = nil
    ) -> BattlePlayer {
        BattlePlayer(
            id: id, name: id, host: false, score: score, buried: buried,
            connected: true, left: false, waiting: waiting, tiles: 0, outOrder: outOrder
        )
    }

    func state(_ players: [BattlePlayer], _ winnerId: String? = nil) -> BattleState {
        BattleState(phase: .finished, players: players, game: 1, winnerId: winnerId)
    }

    @Test("gives the battle to the last one standing, whatever the scores say")
    func givesTheBattleToTheLastOneStandingWhateverTheScoresSay() {
        let winners = battleWinners(state(
            [
                seat("a", score: 99, buried: true, outOrder: 2),
                seat("b", score: 1),
                seat("c", score: 50, buried: true, outOrder: 1),
            ],
            "b"
        ))
        #expect(winners.map(\.id) == ["b"])
    }

    @Test("gives a drawn battle to nobody")
    func givesADrawnBattleToNobody() {
        let winners = battleWinners(state(
            [seat("a", buried: true, outOrder: 1), seat("b", buried: true, outOrder: 2)],
            nil
        ))
        #expect(winners == [])
    }

    @Test("never crowns a player who sat the game out")
    func neverCrownsAPlayerWhoSatTheGameOut() {
        // A winnerId pointing at a waiting player names nobody — contestants only.
        let winners = battleWinners(state(
            [seat("a", buried: true, outOrder: 1), seat("w", waiting: true)],
            "w"
        ))
        #expect(winners == [])
    }
}

@Suite("Battle: ordinal") struct BattleOrdinal {
    @Test("spells ranks the way people say them")
    func spellsRanksTheWayPeopleSayThem() {
        #expect(ordinal(1) == "1st")
        #expect(ordinal(2) == "2nd")
        #expect(ordinal(3) == "3rd")
        #expect(ordinal(4) == "4th")
        #expect(ordinal(11) == "11th")
        #expect(ordinal(12) == "12th")
        #expect(ordinal(13) == "13th")
        #expect(ordinal(21) == "21st")
        #expect(ordinal(22) == "22nd")
    }
}
