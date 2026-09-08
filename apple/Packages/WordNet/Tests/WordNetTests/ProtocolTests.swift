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
            .placed(serial: 3),
            .refused(serial: 4, reason: "Someone got there first."),
            .state(
                BattleState(
                    phase: .playing, players: [], game: 1, winnerId: nil, mode: .occupy,
                    occupy: OccupyState(
                        seats: ["a", "b"], board: TileMap([("3,3", "c")]),
                        owners: ["3,3": 0], opened: [true, false], scores: [1, 0],
                        settledAt: [5, 0], zones: [OccupyZone(centre: Cell(row: 8, col: 9))],
                        end: .stall))),
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
        // an older `state` — no `countdown` key at all — must decode to
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
        #expect(state.mode == .battle)
        #expect(state.players.map(\.id) == ["a"])
    }

    @Test func versionIsElevenForBattlesRoomWideSettings() {
        // v5 was the web's; v6 added the host announcement (plan §7.2); v7
        // Occupy; v8 put the countdown in the snapshot; v9 unbounded the
        // Occupy board, made it ten minutes, and put the zones in the
        // snapshot; v10 made every word its own player's and turned a zone
        // into a minute-long contest that pays out at the whistle — a v9
        // zone would decode as a 2× patch that no longer exists, which is
        // what the gate is for; v11 gave Battle a board view and a modifier,
        // and a v10 client would silently play a different game from the
        // room it is sitting in.
        #expect(PROTOCOL_VERSION == 11)
    }

    @Test func aSnapshotFromBeforeTheSettingsDecodesAsARoomWithoutThem() throws {
        // The compatibility direction that matters within a version: both
        // fields are absent from anything older, and absent has to mean the
        // game those rooms were actually playing.
        let json = "{\"phase\":\"lobby\",\"players\":[],\"game\":0,\"mode\":\"battle\"}"
        let state = try JSONDecoder().decode(BattleState.self, from: Data(json.utf8))
        #expect(state.boardView == .separate)
        #expect(state.modifier == .none)
        #expect(!state.isSharedBoard)
    }

    @Test func anOccupySnapshotWithoutABoardViewIsStillShared() throws {
        // Occupy has only ever had one layout, so a snapshot that predates
        // the setting must not decode as the layout Occupy cannot play.
        let json = "{\"phase\":\"lobby\",\"players\":[],\"game\":0,\"mode\":\"occupy\"}"
        let state = try JSONDecoder().decode(BattleState.self, from: Data(json.utf8))
        #expect(state.boardView == .shared)
        #expect(state.isSharedBoard)
    }

    @Test func theRoomsSettingsSurviveTheWire() throws {
        let state = BattleState(
            phase: .playing, players: [], game: 3, winnerId: nil,
            boardView: .shared, modifier: .gold)
        let back = try JSONDecoder().decode(
            BattleState.self, from: JSONEncoder().encode(state))
        #expect(back.boardView == .shared)
        #expect(back.modifier == .gold)
        #expect(back == state)
    }
}
