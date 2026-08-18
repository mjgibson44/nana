import Foundation
import Testing
@testable import WordCore

/// Regression tests for the review findings: places where the Swift port
/// could trap or silently reorder where the canonical JS stays alive.
/// (Findings from the phase-1 code review; each test failed or crashed
/// before its fix.)

@Suite("Hardening: TileMap codable") struct TileMapCodableHardening {
    @Test("round-trips insertion order exactly")
    func roundTripsOrder() throws {
        // An order no sort would produce.
        var map = TileMap()
        map["3,9"] = "z"
        map["-2,4"] = "a"
        map["0,0"] = "m"
        map["10,-7"] = "q"
        let data = try JSONEncoder().encode(map)
        let back = try JSONDecoder().decode(TileMap.self, from: data)
        #expect(back == map)
        #expect(back.keys == map.keys, "insertion order must survive the round-trip")
        #expect(back.values == map.values)
    }

    @Test("re-inserted keys keep their re-insertion position through a round-trip")
    func reinsertionOrderSurvives() throws {
        var map = TileMap()
        map["0,0"] = "a"
        map["0,1"] = "b"
        map["0,0"] = nil
        map["0,0"] = "c" // re-appended at the end, JS-style
        let back = try JSONDecoder().decode(TileMap.self, from: JSONEncoder().encode(map))
        #expect(back.keys == ["0,1", "0,0"])
    }

    @Test("rejects malformed cell keys instead of trapping later in parseKey")
    func rejectsMalformedKeys() {
        for bad in ["[[\"oops\",\"a\"]]", "[[\"1, 2\",\"a\"]]", "[[\"1;2\",\"a\"]]", "[[\"1,2,3\",\"a\"]]", "[[\"\",\"a\"]]"] {
            #expect(throws: DecodingError.self) {
                _ = try JSONDecoder().decode(TileMap.self, from: bad.data(using: .utf8)!)
            }
        }
    }

    @Test("rejects entries that are not pairs")
    func rejectsNonPairs() {
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(TileMap.self, from: "[[\"1,2\"]]".data(using: .utf8)!)
        }
    }
}

@Suite("Hardening: tile stream") struct TileStreamHardening {
    @Test("a non-positive request returns nothing and doesn't derail the sequence")
    func nonPositiveRequests() {
        // TS semantics: next(-1)/next(0) still size the opening board on the
        // first call — at max(count, STREAM_CHUNK) = 5 — hand back nothing,
        // and later requests drain the same sequence a stream opened with
        // next(5) would deal.
        let reference = TileStream(seed: "hardening")
        let expected = reference.next(5) + reference.next(10)

        let stream = TileStream(seed: "hardening")
        #expect(stream.next(-1) == [])
        #expect(stream.next(0) == [])
        #expect(stream.next(15) == expected)
    }
}

@Suite("Hardening: modes numeric edges") struct ModesNumericHardening {
    @Test("splitAttackTiles survives absurd finite counts")
    func splitSurvivesHugeCounts() {
        let shares = splitAttackTiles(count: 1e19, targets: 3)
        #expect(shares.count == 3)
        #expect(shares.allSatisfy { $0 > 0 })
        // NaN/infinite stay [] per the TS guards.
        #expect(splitAttackTiles(count: .nan, targets: 3) == [])
        #expect(splitAttackTiles(count: .infinity, targets: 3) == [])
    }

    @Test("battleRoundAt degrades on non-finite or huge clocks")
    func roundAtDegrades() {
        #expect(battleRoundAt(seconds: .nan) == 1)
        #expect(battleRoundAt(seconds: .infinity) == BATTLE_ROUNDS)
        #expect(battleRoundAt(seconds: 1e300) == BATTLE_ROUNDS)
        #expect(battleRoundAt(seconds: -1e300) == 1)
        // The real table is untouched.
        #expect(battleRoundAt(seconds: 0) == 1)
        #expect(battleRoundAt(seconds: 180) == 2)
        #expect(battleRoundAt(seconds: 360) == 3)
    }

    @Test("formatSeconds renders a stopped clock for non-finite values")
    func formatSecondsDegrades() {
        #expect(formatSeconds(.nan) == "0:00")
        #expect(formatSeconds(.infinity) == "0:00")
        #expect(formatSeconds(-.infinity) == "0:00")
        #expect(formatSeconds(90) == "1:30")
    }
}
