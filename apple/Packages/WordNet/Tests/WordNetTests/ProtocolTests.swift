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
        var countingDown = state
        countingDown.phase = .lobby
        countingDown.countdown = 3
        let messages: [HostMessage] = [
            .state(state),
            .state(countingDown),
            .start(seed: "abc123def456"),
            .stop,
            .reject(reason: "full"),
            .attack(count: 3),
            .ping,
            .host(proto: PROTOCOL_VERSION),
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

    @Test func aSnapshotWithoutACountdownStillDecodes() throws {
        // The countdown is an optional addition to the web's snapshot shape:
        // a v6-shaped `state` — no `countdown` key at all — must decode to
        // "no countdown", not fail.
        let json = #"""
            {"t":"state","state":{"phase":"lobby","game":0,"winnerId":null,
             "players":[{"id":"a","name":"Ann","host":true,"score":0,"buried":false,
                         "connected":true,"left":false,"waiting":false,"tiles":0}]}}
            """#
        let message = try #require(Wire.decode(HostMessage.self, from: Data(json.utf8)))
        guard case let .state(state) = message else {
            Issue.record("decoded as \(message), not a snapshot")
            return
        }
        #expect(state.countdown == nil)
        #expect(state.players.map(\.id) == ["a"])
    }

    @Test func versionIsSevenForTheCountdown() {
        // v5 was the web's; v6 added the host announcement (plan §7.2); v7
        // put the countdown in the snapshot.
        #expect(PROTOCOL_VERSION == 7)
    }
}
