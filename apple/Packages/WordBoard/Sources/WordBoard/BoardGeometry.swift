import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
import WordCore

/// Board geometry: cell sizing, hit-testing, and the scroll/zoom math the web
/// game solved in `App.tsx` (pinch anchoring 2741–2895, auto-fit 1089–1133,
/// growth compensation 1035–1046, `measureTiles` 136–157, `alignPinch`
/// 165–175). Ported as pure functions over an explicit scroll-offset model so
/// every behavior the notes call load-bearing is unit-testable:
///
///  - zoom scales tiles only, clamped 0.55–1.6;
///  - a pinch anchors a board point *once*, as a fraction of the content, and
///    every frame re-aims it at the fingers — re-running the alignment is
///    harmless;
///  - auto-fit only ever shrinks (cap 1.0, epsilon 0.03, 1-cell pad) and
///    restores the viewport's center relative to the tile box — it never
///    scrolls toward the tiles;
///  - board growth prepends rows/cols and the offset is nudged by exactly
///    that many steps so the crossword doesn't visibly move.
///
/// Coordinate model (the equivalent of the web's `overflow: auto` wrap):
/// content smaller than the viewport is centered ("margin: auto"); larger
/// content scrolls with `offset` = the content point sitting at the viewport
/// origin, clamped to `0 … content − viewport`.

// MARK: - Constants (App.tsx:85–121, styles.css:3,1740)

/// Pointer travel under this (points) counts as a tap, not a drag.
public let TAP_SLOP: Double = 6

/// Holding a touch this long on the board picks the staged word up to drag.
public let HOLD_DRAG_SECONDS: Double = 0.3

/// Two presses on the same tile within this window are a double-press.
public let DOUBLE_PRESS_SECONDS: Double = 0.35

/// Pinch limits, as a multiple of the base cell size.
public let MIN_ZOOM: Double = 0.55
public let MAX_ZOOM: Double = 1.6

/// Auto-fit never enlarges past this, pads the tile box by this many cells,
/// and ignores corrections smaller than this.
public let AUTO_ZOOM_MAX: Double = 1.0
public let FIT_PAD_CELLS = 1
public let ZOOM_EPSILON: Double = 0.03

/// Cell size before zoom: 44pt regular, 38pt compact (styles.css:3, 1739–1741).
public let CELL_BASE_REGULAR: Double = 44
public let CELL_BASE_COMPACT: Double = 38

/// The gap between cells, and the minimum space between two board tiles at
/// any zoom: it is a constant number of points added to the cell step rather
/// than something the pinch scales, so zooming out never closes the lattice
/// up into a solid block.
public let CELL_HAIRLINE: Double = 2

public func clampZoom(_ zoom: Double) -> Double {
    min(MAX_ZOOM, max(MIN_ZOOM, zoom))
}

// MARK: - Metrics

/// The rendered board: which cells are in play and how big they draw.
public struct BoardMetrics: Equatable {
    public var bounds: Bounds
    public var cellBase: Double
    public var zoom: Double

    public init(bounds: Bounds, cellBase: Double = CELL_BASE_REGULAR, zoom: Double = 1) {
        self.bounds = bounds
        self.cellBase = cellBase
        self.zoom = zoom
    }

    /// The CSS `--cell`: base size × pinch zoom.
    public var cellSize: Double { cellBase * zoom }

    /// Distance from one cell's origin to the next (cell + hairline gap).
    public var step: Double { cellSize + CELL_HAIRLINE }

    public var rows: Int { bounds.maxRow - bounds.minRow + 1 }
    public var cols: Int { bounds.maxCol - bounds.minCol + 1 }

    /// The board's rendered size: N cells and the N−1 hairlines between them.
    public var contentSize: CGSize {
        CGSize(
            width: Double(cols) * step - CELL_HAIRLINE,
            height: Double(rows) * step - CELL_HAIRLINE
        )
    }

    /// Where a cell draws, in content coordinates.
    public func rect(of cell: Cell) -> CGRect {
        CGRect(
            x: Double(cell.col - bounds.minCol) * step,
            y: Double(cell.row - bounds.minRow) * step,
            width: cellSize,
            height: cellSize
        )
    }

    /// The cell under a content point — the `elementFromPoint` of the port.
    /// A point in a hairline gap counts toward the cell before it, and points
    /// outside the bounds return nil.
    public func cell(at point: CGPoint) -> Cell? {
        guard point.x >= 0, point.y >= 0 else { return nil }
        let col = Int((point.x / step).rounded(.down))
        let row = Int((point.y / step).rounded(.down))
        guard row < rows, col < cols else { return nil }
        return Cell(row: bounds.minRow + row, col: bounds.minCol + col)
    }

    /// The rectangle the placed tiles span, in content coordinates — the
    /// port of `measureTiles` (App.tsx:136–157), minus the DOM measuring.
    public func rect(ofTileBox box: Bounds) -> CGRect {
        CGRect(
            x: Double(box.minCol - bounds.minCol) * step,
            y: Double(box.minRow - bounds.minRow) * step,
            width: Double(box.maxCol - box.minCol + 1) * step - CELL_HAIRLINE,
            height: Double(box.maxRow - box.minRow + 1) * step - CELL_HAIRLINE
        )
    }
}

/// The rectangle of cells that actually hold tiles, or nil on an empty board
/// (App.tsx tileBox, 1051–1066).
public func tileBox(of board: TileMap) -> Bounds? {
    guard !board.isEmpty else { return nil }
    var minRow = Int.max
    var maxRow = Int.min
    var minCol = Int.max
    var maxCol = Int.min
    for key in board.keys {
        let cell = parseKey(key)
        if cell.row < minRow { minRow = cell.row }
        if cell.row > maxRow { maxRow = cell.row }
        if cell.col < minCol { minCol = cell.col }
        if cell.col > maxCol { maxCol = cell.col }
    }
    return Bounds(minRow: minRow, minCol: minCol, maxRow: maxRow, maxCol: maxCol)
}

// MARK: - Viewport (scroll) model

/// Where the content's top-left corner sits in the scrollable canvas: pushed
/// in to center it when the viewport is bigger ("margin: auto", styles.css
/// 427–430), flush at zero otherwise.
public func contentOrigin(contentSize: CGSize, viewport: CGSize) -> CGPoint {
    CGPoint(
        x: max(0, (viewport.width - contentSize.width) / 2),
        y: max(0, (viewport.height - contentSize.height) / 2)
    )
}

/// How far the content can scroll; zero on an axis it fits on.
public func maxOffset(contentSize: CGSize, viewport: CGSize) -> CGSize {
    CGSize(
        width: max(0, contentSize.width - viewport.width),
        height: max(0, contentSize.height - viewport.height)
    )
}

public func clampOffset(_ offset: CGPoint, contentSize: CGSize, viewport: CGSize) -> CGPoint {
    let limit = maxOffset(contentSize: contentSize, viewport: viewport)
    return CGPoint(
        x: min(max(0, offset.x), limit.width),
        y: min(max(0, offset.y), limit.height)
    )
}

/// The offset that centers the content — the web's new-game scroll
/// (App.tsx:1015–1021).
public func centeredOffset(contentSize: CGSize, viewport: CGSize) -> CGPoint {
    let limit = maxOffset(contentSize: contentSize, viewport: viewport)
    return CGPoint(x: limit.width / 2, y: limit.height / 2)
}

/// A viewport point translated into content coordinates.
public func contentPoint(
    fromViewport point: CGPoint, offset: CGPoint, contentSize: CGSize, viewport: CGSize
) -> CGPoint {
    let origin = contentOrigin(contentSize: contentSize, viewport: viewport)
    return CGPoint(x: point.x - origin.x + offset.x, y: point.y - origin.y + offset.y)
}

/// A content point translated into viewport coordinates.
public func viewportPoint(
    fromContent point: CGPoint, offset: CGPoint, contentSize: CGSize, viewport: CGSize
) -> CGPoint {
    let origin = contentOrigin(contentSize: contentSize, viewport: viewport)
    return CGPoint(x: point.x + origin.x - offset.x, y: point.y + origin.y - offset.y)
}

// MARK: - Pinch anchoring (App.tsx:2744–2895, alignPinch 165–175)

/// The gesture's grip on the board: the zoom it started at and the board
/// point — as a fraction of the content's size — that sat between the
/// fingers. The point is anchored once, at first touch; every frame then
/// aims it back at the fingers, so rounding errors never compound and
/// moving both fingers together pans the board with them.
public struct PinchAnchor: Equatable {
    public var fx: Double
    public var fy: Double
    public var startZoom: Double

    public init(fx: Double, fy: Double, startZoom: Double) {
        self.fx = fx
        self.fy = fy
        self.startZoom = startZoom
    }

    /// Grab the board point under the fingers' midpoint (viewport coords).
    public static func capture(
        midpoint: CGPoint, offset: CGPoint, metrics: BoardMetrics, viewport: CGSize
    ) -> PinchAnchor {
        let size = metrics.contentSize
        let point = contentPoint(
            fromViewport: midpoint, offset: offset, contentSize: size, viewport: viewport)
        return PinchAnchor(
            fx: point.x / size.width, fy: point.y / size.height, startZoom: metrics.zoom)
    }

    /// The zoom for the fingers' current spread relative to their starting
    /// spread, clamped to the pinch limits.
    public func zoom(forScale scale: Double) -> Double {
        clampZoom(startZoom * scale)
    }

    /// The offset that puts the anchored board point exactly under
    /// `midpoint` at the current metrics. Aiming at an absolute spot makes
    /// re-running this harmless: a second call with the same inputs moves
    /// nothing (the web's `alignPinch` invariant).
    public func alignedOffset(
        midpoint: CGPoint, metrics: BoardMetrics, viewport: CGSize
    ) -> CGPoint {
        let size = metrics.contentSize
        let origin = contentOrigin(contentSize: size, viewport: viewport)
        let raw = CGPoint(
            x: origin.x + fx * size.width - midpoint.x,
            y: origin.y + fy * size.height - midpoint.y
        )
        return clampOffset(raw, contentSize: size, viewport: viewport)
    }
}

// MARK: - Auto-fit (App.tsx:1089–1133)

/// Re-pick the zoom so every placed tile fits on screen, padded by one cell.
/// Only ever backs out (cap `AUTO_ZOOM_MAX`), never below `MIN_ZOOM`, and
/// returns nil for changes too small to matter — or when no change is needed
/// at all. The caller pairs a non-nil result with `captureFocus`/
/// `restoreOffset` so the player's focal point stays put through the resize.
public func autoFitZoom(
    tileBox box: Bounds, viewport: CGSize, cellBase: Double, currentZoom: Double
) -> Double? {
    let cols = Double(box.maxCol - box.minCol + 1 + FIT_PAD_CELLS * 2)
    let rows = Double(box.maxRow - box.minRow + 1 + FIT_PAD_CELLS * 2)
    let fitAcross = (viewport.width / cols - CELL_HAIRLINE) / cellBase
    let fitDown = (viewport.height / rows - CELL_HAIRLINE) / cellBase
    let target = min(max(min(fitAcross, fitDown), MIN_ZOOM), AUTO_ZOOM_MAX)
    guard target.isFinite else { return nil }
    guard abs(target - currentZoom) > ZOOM_EPSILON else { return nil }
    return target
}

/// Where the viewport's center sits relative to the tile box, as fractions of
/// its size — noted before a refit so the point the player is looking at can
/// be put straight back (App.tsx:1104–1111).
public struct ViewportFocus: Equatable {
    public var fx: Double
    public var fy: Double

    public init(fx: Double, fy: Double) {
        self.fx = fx
        self.fy = fy
    }
}

public func captureFocus(
    offset: CGPoint, metrics: BoardMetrics, tileBox box: Bounds, viewport: CGSize
) -> ViewportFocus {
    let origin = contentOrigin(contentSize: metrics.contentSize, viewport: viewport)
    let rect = metrics.rect(ofTileBox: box)
    return ViewportFocus(
        fx: (offset.x + viewport.width / 2 - (origin.x + rect.minX)) / rect.width,
        fy: (offset.y + viewport.height / 2 - (origin.y + rect.minY)) / rect.height
    )
}

/// The offset that puts the noted focus point back under the viewport's
/// center at the new metrics (App.tsx:1121–1133).
public func restoreOffset(
    focus: ViewportFocus, metrics: BoardMetrics, tileBox box: Bounds, viewport: CGSize
) -> CGPoint {
    let size = metrics.contentSize
    let origin = contentOrigin(contentSize: size, viewport: viewport)
    let rect = metrics.rect(ofTileBox: box)
    let raw = CGPoint(
        x: origin.x + rect.minX + focus.fx * rect.width - viewport.width / 2,
        y: origin.y + rect.minY + focus.fy * rect.height - viewport.height / 2
    )
    return clampOffset(raw, contentSize: size, viewport: viewport)
}

// MARK: - Board growth compensation (App.tsx:1035–1046)

/// Growing at the top or left prepends rows and columns, which would shove
/// the tiles the player is looking at down and across the screen. Returns the
/// offset nudge — apply it in the same update as the bounds change — that
/// keeps the board from appearing to move at all.
public func growthCompensation(from old: Bounds, to new: Bounds, step: Double) -> CGSize {
    CGSize(
        width: Double(old.minCol - new.minCol) * step,
        height: Double(old.minRow - new.minRow) * step
    )
}
