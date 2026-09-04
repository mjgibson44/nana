import Foundation
import WordCore

/// The wire protocol, ported from `src/net/battleSession.ts` (spec:
/// `docs/apple-port-notes/protocol.md` §1).
///
/// **Version 8.** Three steps up from the web's 5:
///
///  - v6 added `host`. On the web the join code *is* the host's address, so a
///    client always knows whom to `hello`. A GKMatch formed from a party code
///    is a mesh with no marked owner, so the lobby's creator announces itself
///    and late joiners are told again; clients that hear nothing fall back to
///    the lowest player id (plan §7.2).
///  - v7 added Occupy: a `place` from a client, the host's `placed` or
///    `refused` answer, and the shared board riding in every `state` snapshot
///    (`BattleState.occupy`), plus the lobby's `mode`.
///  - v8 added `countdown` to the `state` snapshot: a random match deals
///    itself once everyone is here, and the seconds left ride the snapshot
///    every screen already shows rather than a message of their own.
///
/// The version gate is load-bearing rather than ceremonial: there has been no
/// Game Center sandbox since 2016 (TN2417), so a prerelease build can and will
/// meet a released one.
public let PROTOCOL_VERSION = 8

/// Who a message is from or to. Maps to `GKPlayer.gamePlayerID` — the stable
/// per-game identity that replaces the web's sessionStorage `playerKey`.
public typealias PlayerID = String

/// Client → host. Clients only ever address the host, which is how the star
/// topology survives a full mesh: by convention, not by capability.
public enum ClientMessage: Equatable {
    /// Sent once whenever a link to the host opens — first join and every
    /// re-entry. The name comes from `GKPlayer.displayName` on the host's side
    /// rather than the wire (plan §7.2), so only the version travels.
    case hello(proto: Int)
    case progress(score: Int, buried: Bool, tiles: Int)
    case attack(count: Int)
    /// Occupy: a word let go of. `serial` is the client's own count, so the
    /// host's answer can be matched to the word it was about.
    case place(serial: Int, placement: OccupyPlacement)
    case pong
    case leave
}

/// Host → client.
public enum HostMessage: Equatable {
    case state(BattleState)
    case start(seed: String)
    case stop
    case reject(reason: String)
    /// Point-to-point: each target hears only its own share of a volley.
    case attack(count: Int)
    case ping
    /// New in v6: "I am the referee." Broadcast on match formation and
    /// re-sent to every later-connecting player.
    case host(proto: Int)
    /// Occupy: the word numbered `serial` is down. Sent to its sender only,
    /// *after* the snapshot that carries it.
    case placed(serial: Int)
    /// Occupy: the word numbered `serial` isn't going down, and why.
    case refused(serial: Int, reason: String)
}

// MARK: - Coding

/// Both unions are tagged by `t`, exactly like the web's JSON. Keeping the
/// shape means a future relay (plan §10) or a web client can speak this
/// without a translation layer.
extension ClientMessage: Codable {
    private enum Tag: String, Codable {
        case hello, progress, attack, place, pong, leave
    }

    private enum Key: String, CodingKey {
        case t, score, buried, tiles, count, proto, serial, placement
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Key.self)
        switch try container.decode(Tag.self, forKey: .t) {
        case .hello:
            self = .hello(proto: try container.decode(Int.self, forKey: .proto))
        case .progress:
            self = .progress(
                score: try container.decode(Int.self, forKey: .score),
                buried: try container.decode(Bool.self, forKey: .buried),
                tiles: try container.decode(Int.self, forKey: .tiles))
        case .attack:
            self = .attack(count: try container.decode(Int.self, forKey: .count))
        case .place:
            self = .place(
                serial: try container.decode(Int.self, forKey: .serial),
                placement: try container.decode(OccupyPlacement.self, forKey: .placement))
        case .pong:
            self = .pong
        case .leave:
            self = .leave
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Key.self)
        switch self {
        case let .hello(proto):
            try container.encode(Tag.hello, forKey: .t)
            try container.encode(proto, forKey: .proto)
        case let .progress(score, buried, tiles):
            try container.encode(Tag.progress, forKey: .t)
            try container.encode(score, forKey: .score)
            try container.encode(buried, forKey: .buried)
            try container.encode(tiles, forKey: .tiles)
        case let .attack(count):
            try container.encode(Tag.attack, forKey: .t)
            try container.encode(count, forKey: .count)
        case let .place(serial, placement):
            try container.encode(Tag.place, forKey: .t)
            try container.encode(serial, forKey: .serial)
            try container.encode(placement, forKey: .placement)
        case .pong:
            try container.encode(Tag.pong, forKey: .t)
        case .leave:
            try container.encode(Tag.leave, forKey: .t)
        }
    }
}

extension HostMessage: Codable {
    private enum Tag: String, Codable {
        case state, start, stop, reject, attack, ping, host, placed, refused
    }

    private enum Key: String, CodingKey {
        case t, state, seed, reason, count, proto, serial
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Key.self)
        switch try container.decode(Tag.self, forKey: .t) {
        case .state:
            self = .state(try container.decode(BattleState.self, forKey: .state))
        case .start:
            self = .start(seed: try container.decode(String.self, forKey: .seed))
        case .stop:
            self = .stop
        case .reject:
            self = .reject(reason: try container.decode(String.self, forKey: .reason))
        case .attack:
            self = .attack(count: try container.decode(Int.self, forKey: .count))
        case .ping:
            self = .ping
        case .host:
            self = .host(proto: try container.decode(Int.self, forKey: .proto))
        case .placed:
            self = .placed(serial: try container.decode(Int.self, forKey: .serial))
        case .refused:
            self = .refused(
                serial: try container.decode(Int.self, forKey: .serial),
                reason: try container.decode(String.self, forKey: .reason))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Key.self)
        switch self {
        case let .state(state):
            try container.encode(Tag.state, forKey: .t)
            try container.encode(state, forKey: .state)
        case let .start(seed):
            try container.encode(Tag.start, forKey: .t)
            try container.encode(seed, forKey: .seed)
        case .stop:
            try container.encode(Tag.stop, forKey: .t)
        case let .reject(reason):
            try container.encode(Tag.reject, forKey: .t)
            try container.encode(reason, forKey: .reason)
        case let .attack(count):
            try container.encode(Tag.attack, forKey: .t)
            try container.encode(count, forKey: .count)
        case .ping:
            try container.encode(Tag.ping, forKey: .t)
        case let .host(proto):
            try container.encode(Tag.host, forKey: .t)
            try container.encode(proto, forKey: .proto)
        case let .placed(serial):
            try container.encode(Tag.placed, forKey: .t)
            try container.encode(serial, forKey: .serial)
        case let .refused(serial, reason):
            try container.encode(Tag.refused, forKey: .t)
            try container.encode(serial, forKey: .serial)
            try container.encode(reason, forKey: .reason)
        }
    }
}

/// Encoding helpers shared by both sessions. A message that can't be encoded
/// or decoded is dropped rather than thrown at the caller: the web ignores
/// unknown and malformed traffic on both sides, and a hostile peer must not be
/// able to crash a game.
enum Wire {
    static func encode<M: Encodable>(_ message: M) -> Data? {
        try? JSONEncoder().encode(message)
    }

    static func decode<M: Decodable>(_ type: M.Type, from data: Data) -> M? {
        try? JSONDecoder().decode(type, from: data)
    }
}
