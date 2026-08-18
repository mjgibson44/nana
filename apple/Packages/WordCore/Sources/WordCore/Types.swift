/// Core shared types, ported from `src/game/types.ts`.
///
/// The board stays keyed by `"row,col"` strings and iterates in insertion
/// order (see `TileMap`) because the seeded generator's determinism contract
/// observes JS object-key order — see docs/apple-port-plan.md §5.

public typealias CellKey = String

public enum Direction: String, Codable, Equatable, CaseIterable {
    case across
    case down
}

public struct Cell: Hashable, Codable {
    public var row: Int
    public var col: Int

    public init(row: Int, col: Int) {
        self.row = row
        self.col = col
    }
}

/// The rectangle of cells currently in play, inclusive on all four sides.
/// The board grows as tiles near its edge, so it can run into negative
/// rows and columns — cell keys handle that fine.
public struct Bounds: Equatable, Codable {
    public var minRow: Int
    public var minCol: Int
    public var maxRow: Int
    public var maxCol: Int

    public init(minRow: Int, minCol: Int, maxRow: Int, maxCol: Int) {
        self.minRow = minRow
        self.minCol = minCol
        self.maxRow = maxRow
        self.maxCol = maxCol
    }

    /// The old "board is size × size from the origin" shorthand.
    /// Mirrors `asBounds(size)` for a plain number in TS.
    public init(size: Int) {
        self.init(minRow: 0, minCol: 0, maxRow: size - 1, maxCol: size - 1)
    }

    public func contains(row: Int, col: Int) -> Bool {
        row >= minRow && col >= minCol && row <= maxRow && col <= maxCol
    }
}

@inlinable
public func keyOf(_ row: Int, _ col: Int) -> CellKey {
    "\(row),\(col)"
}

@inlinable
public func parseKey(_ key: CellKey) -> Cell {
    let comma = key.firstIndex(of: ",")!
    let row = Int(key[key.startIndex..<comma])!
    let col = Int(key[key.index(after: comma)...])!
    return Cell(row: row, col: col)
}
