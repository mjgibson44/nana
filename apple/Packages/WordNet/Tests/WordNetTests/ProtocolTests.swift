import Foundation
import Testing
import WordCore

@testable import WordNet

@Suite("Wire protocol")
struct WireProtocolTests {
    @Test func clientMessagesRoundTripThroughTheirTaggedShape() throws {
        let messages: [ClientMessage] = [
            .hello(proto: PROTOCOL_VERSION),
            .progress(score: 42, buried: true, tiles: 7),
            .attack(count: 5),
            .place(
                serial: 3,
                placement: OccupyPlacement(tiles: ["3,3": "c", "3,4": "a"], borrowed: ["3,5"])),
            .pong,
            .leave,
        ]
        for message in messages {
            let data = try #require(Wire.encode(message))
            #expect(Wire.decode(ClientMessage.self, from: data) == message)
        }
    }

    @Test func hostMessagesRoundTripThroughTheirTaggedShape() throws {
        let state = BattleState(
            phase: .playing,
            players: [BattlePlayer(id: "a", name: "Ann", host: true, score: 12, tiles: 3)],
            game: 2,
            winnerId: nil)
        let messages: [HostMessage] = [
            .state(state),
            .start(seed: "abc123def456"),
            .stop,
            .reject(reason: "full"),
            .attack(count: 3),
            .ping,
            .host(proto: PROTOCOL_VERSION),
            .placed(serial: 3),
            .refused(serial: 4, reason: "Someone got there first."),
            .state(
                BattleState(
                    phase: .playing, players: [], game: 1, winnerId: nil, mode: .occupy,
                    occupy: OccupyState(
                        size: 15, seats: ["a", "b"], board: TileMap([("3,3", "c")]),
                        owners: ["3,3": 0], opened: [true, false], scores: [1, 0],
                        settledAt: [5, 0], end: .stall))),
        ]
        for message in messages {
            let data = try #require(Wire.encode(message))
            #expect(Wire.decode(HostMessage.self, from: data) == message)
        }
    }

    @Test func theWireShapeIsTheWebsTaggedJSON() throws {
        // Keeping `t` means a future WebSocket relay (plan §10) or a web
        // client can speak this without a translation layer.
        let data = try #require(Wire.encode(ClientMessage.progress(score: 1, buried: false, tiles: 2)))
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["t"] as? String == "progress")
        #expect(json["score"] as? Int == 1)
        #expect(json["buried"] as? Bool == false)
        #expect(json["tiles"] as? Int == 2)
    }

    @Test func malformedTrafficIsIgnoredNotFatal() {
        // A hostile or half-written message must never take a game down.
        #expect(Wire.decode(ClientMessage.self, from: Data("not json".utf8)) == nil)
        #expect(Wire.decode(HostMessage.self, from: Data("{}".utf8)) == nil)
        #expect(Wire.decode(HostMessage.self, from: Data(#"{"t":"nope"}"#.utf8)) == nil)
        #expect(Wire.decode(ClientMessage.self, from: Data(#"{"t":"hello"}"#.utf8)) == nil)
    }

    @Test func versionIsSevenForOccupy() {
        // v5 was the web's; the announcement is the one addition (plan §7.2).
        #expect(PROTOCOL_VERSION == 7)
    }
}
