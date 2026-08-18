/// A sparse board: only occupied cells are present; values are lowercase
/// letters. Ported from `TileMap = Record<CellKey, string>` in
/// `src/game/types.ts` — with one crucial addition: **iteration order is
/// insertion order**, exactly like a JS object with non-numeric string keys.
///
/// This is not a nicety. The seeded generator indexes the shared RNG into
/// `Object.keys(grid)` and `Object.values(solution)`, so two clients agree on
/// a deal only if their boards enumerate in the identical order. Swift's
/// `Dictionary` order is unspecified per process; this type pairs the hash
/// map with an insertion-ordered key list to reproduce the JS semantics:
///
/// - inserting a new key appends it to the order;
/// - overwriting an existing key keeps its position;
/// - removing a key removes it from the order;
/// - re-inserting a removed key appends it at the end again.
public struct TileMap: Equatable {
    @usableFromInline
    internal var storage: [CellKey: String] = [:]
    /// Insertion order of the keys currently present.
    public private(set) var keys: [CellKey] = []

    public init() {}

    public init(_ entries: [(CellKey, String)]) {
        for (key, value) in entries { self[key] = value }
    }

    public var count: Int { keys.count }
    public var isEmpty: Bool { keys.isEmpty }

    /// Values in insertion order — `Object.values(map)`.
    public var values: [String] { keys.map { storage[$0]! } }

    /// Entries in insertion order — `Object.entries(map)`.
    public var entries: [(key: CellKey, value: String)] {
        keys.map { ($0, storage[$0]!) }
    }

    public func contains(_ key: CellKey) -> Bool {
        storage[key] != nil
    }

    public subscript(key: CellKey) -> String? {
        get { storage[key] }
        set {
            if let newValue {
                if storage[key] == nil { keys.append(key) }
                storage[key] = newValue
            } else if storage[key] != nil {
                storage[key] = nil
                keys.removeAll { $0 == key }
            }
        }
    }

    public subscript(row: Int, col: Int) -> String? {
        get { self[keyOf(row, col)] }
        set { self[keyOf(row, col)] = newValue }
    }

    /// Order-insensitive equality, like deep-equality of two JS objects.
    public static func == (lhs: TileMap, rhs: TileMap) -> Bool {
        lhs.storage == rhs.storage
    }
}

extension TileMap: Sequence {
    /// Iterates entries in insertion order.
    public func makeIterator() -> AnyIterator<(key: CellKey, value: String)> {
        var index = 0
        return AnyIterator {
            guard index < keys.count else { return nil }
            defer { index += 1 }
            let key = keys[index]
            return (key, storage[key]!)
        }
    }
}

extension TileMap: Codable {
    /// Encodes as an ordered `[["row,col", "letter"], …]` pair list, NOT a
    /// JSON object: insertion order is part of this type's contract (the
    /// seeded generator indexes the RNG into it), and Foundation's keyed
    /// containers cannot observe or reproduce document order. The pair list
    /// round-trips the order exactly, so a saved mid-game board resumes with
    /// the identical deal. (Boards never cross the battle wire — only seeds
    /// do — so this format is app-internal.)
    public init(from decoder: Decoder) throws {
        let pairs = try [[String]](from: decoder)
        var map = TileMap()
        for pair in pairs {
            guard pair.count == 2 else {
                throw DecodingError.dataCorrupted(DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "TileMap entry must be a [key, letter] pair"
                ))
            }
            guard Self.isValidKey(pair[0]) else {
                throw DecodingError.dataCorrupted(DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "malformed cell key \(pair[0].debugDescription)"
                ))
            }
            map[pair[0]] = pair[1]
        }
        self = map
    }

    public func encode(to encoder: Encoder) throws {
        try keys.map { [$0, storage[$0]!] }.encode(to: encoder)
    }

    /// A key `parseKey` can digest: `<int>,<int>` with no padding.
    static func isValidKey(_ key: String) -> Bool {
        guard let comma = key.firstIndex(of: ",") else { return false }
        return Int(key[key.startIndex..<comma]) != nil
            && Int(key[key.index(after: comma)...]) != nil
    }
}

extension TileMap: ExpressibleByDictionaryLiteral {
    public init(dictionaryLiteral elements: (CellKey, String)...) {
        self.init(elements)
    }
}
