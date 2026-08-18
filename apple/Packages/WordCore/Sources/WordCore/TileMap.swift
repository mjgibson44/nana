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
    /// Encodes as a plain `{"row,col": "letter"}` object, byte-compatible
    /// with the web game's serialized boards. Decoding rebuilds insertion
    /// order from the document order where the decoder preserves it;
    /// deterministic paths never decode boards, so this is a convenience.
    public init(from decoder: Decoder) throws {
        let dict = try [String: String](from: decoder)
        // Sorted for determinism when document order is unavailable.
        self.init(dict.sorted { $0.key < $1.key }.map { ($0.key, $0.value) })
    }

    public func encode(to encoder: Encoder) throws {
        try storage.encode(to: encoder)
    }
}

extension TileMap: ExpressibleByDictionaryLiteral {
    public init(dictionaryLiteral elements: (CellKey, String)...) {
        self.init(elements)
    }
}
