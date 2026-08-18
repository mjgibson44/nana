import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Testing
import WordCore

@testable import WordBoard

// MARK: - Metrics

@Suite("BoardMetrics")
struct BoardMetricsTests {
    let metrics = BoardMetrics(
        bounds: Bounds(minRow: 0, minCol: 0, maxRow: 32, maxCol: 32),
        cellBase: 44, zoom: 1)

    @Test func cellSizeScalesWithZoom() {
        #expect(metrics.cellSize == 44)
        #expect(metrics.step == 45)
        var zoomed = metrics
        zoomed.zoom = 0.55
        #expect(zoomed.cellSize == 44 * 0.55)
        #expect(zoomed.step == 44 * 0.55 + 1)
    }

    @Test func contentSizeCountsHairlinesBetweenCellsOnly() {
        // 33 cells and 32 hairlines: 33*45 - 1.
        #expect(metrics.contentSize == CGSize(width: 1484, height: 1484))
    }

    @Test func rectOfCellAtOriginAndBeyond() {
        #expect(metrics.rect(of: Cell(row: 0, col: 0)) == CGRect(x: 0, y: 0, width: 44, height: 44))
        #expect(
            metrics.rect(of: Cell(row: 2, col: 5))
                == CGRect(x: 5 * 45, y: 2 * 45, width: 44, height: 44))
    }

    @Test func rectHonorsNegativeBounds() {
        let grown = BoardMetrics(
            bounds: Bounds(minRow: -3, minCol: -2, maxRow: 32, maxCol: 32),
            cellBase: 44, zoom: 1)
        // The first rendered cell is (-3,-2), at the content origin.
        #expect(grown.rect(of: Cell(row: -3, col: -2)).origin == CGPoint(x: 0, y: 0))
        #expect(grown.rect(of: Cell(row: 0, col: 0)).origin == CGPoint(x: 2 * 45, y: 3 * 45))
    }

    @Test func cellAtRoundTripsRect() {
        for cell in [Cell(row: 0, col: 0), Cell(row: 16, col: 16), Cell(row: 32, col: 32)] {
            let rect = metrics.rect(of: cell)
            #expect(metrics.cell(at: CGPoint(x: rect.midX, y: rect.midY)) == cell)
            #expect(metrics.cell(at: rect.origin) == cell)
        }
    }

    @Test func hairlineGapCountsTowardThePrecedingCell() {
        // x = 44.5 sits in the gap after column 0.
        #expect(metrics.cell(at: CGPoint(x: 44.5, y: 10)) == Cell(row: 0, col: 0))
    }

    @Test func pointsOutsideContentMissEveryCell() {
        #expect(metrics.cell(at: CGPoint(x: -1, y: 10)) == nil)
        #expect(metrics.cell(at: CGPoint(x: 10, y: -0.001)) == nil)
        #expect(metrics.cell(at: CGPoint(x: 33 * 45, y: 10)) == nil)
        #expect(metrics.cell(at: CGPoint(x: 10, y: 5000)) == nil)
    }

    @Test func cellAtWorksAtEveryZoom() {
        for zoom in [MIN_ZOOM, 0.8, 1.0, MAX_ZOOM] {
            let m = BoardMetrics(bounds: metrics.bounds, cellBase: 44, zoom: zoom)
            let rect = m.rect(of: Cell(row: 7, col: 20))
            #expect(m.cell(at: CGPoint(x: rect.midX, y: rect.midY)) == Cell(row: 7, col: 20))
        }
    }

    @Test func tileBoxRectSpansItsCells() {
        let box = Bounds(minRow: 10, minCol: 12, maxRow: 14, maxCol: 20)
        let rect = metrics.rect(ofTileBox: box)
        // 9 cols / 5 rows of cells and the hairlines between them.
        #expect(rect == CGRect(x: 12 * 45, y: 10 * 45, width: 9 * 45 - 1, height: 5 * 45 - 1))
    }

    @Test func tileBoxOfBoard() {
        #expect(tileBox(of: TileMap()) == nil)
        var board = TileMap()
        board[keyOf(16, 16)] = "a"
        board[keyOf(14, 18)] = "b"
        board[keyOf(17, 15)] = "c"
        #expect(tileBox(of: board) == Bounds(minRow: 14, minCol: 15, maxRow: 17, maxCol: 18))
    }
}

// MARK: - Viewport model

@Suite("Viewport scroll model")
struct ViewportModelTests {
    @Test func smallContentCentersLikeMarginAuto() {
        let origin = contentOrigin(
            contentSize: CGSize(width: 200, height: 100),
            viewport: CGSize(width: 400, height: 400))
        #expect(origin == CGPoint(x: 100, y: 150))
    }

    @Test func largeContentSitsFlush() {
        let origin = contentOrigin(
            contentSize: CGSize(width: 1484, height: 1484),
            viewport: CGSize(width: 400, height: 400))
        #expect(origin == .zero)
    }

    @Test func offsetsClampToScrollableRange() {
        let content = CGSize(width: 1000, height: 300)
        let viewport = CGSize(width: 400, height: 400)
        #expect(
            clampOffset(CGPoint(x: -50, y: 10), contentSize: content, viewport: viewport)
                == CGPoint(x: 0, y: 0))
        #expect(
            clampOffset(CGPoint(x: 9999, y: -1), contentSize: content, viewport: viewport)
                == CGPoint(x: 600, y: 0))
    }

    @Test func centeredOffsetIsHalfTheScrollRange() {
        let offset = centeredOffset(
            contentSize: CGSize(width: 1484, height: 1484),
            viewport: CGSize(width: 400, height: 600))
        #expect(offset == CGPoint(x: (1484 - 400) / 2, y: (1484 - 600) / 2))
    }

    @Test func viewportContentPointsRoundTrip() {
        let content = CGSize(width: 1484, height: 1484)
        let viewport = CGSize(width: 400, height: 400)
        let offset = CGPoint(x: 300, y: 500)
        let vp = CGPoint(x: 123, y: 45)
        let cp = contentPoint(
            fromViewport: vp, offset: offset, contentSize: content, viewport: viewport)
        #expect(cp == CGPoint(x: 423, y: 545))
        #expect(
            viewportPoint(fromContent: cp, offset: offset, contentSize: content, viewport: viewport)
                == vp)
    }

    @Test func centeredContentShiftsPointConversions() {
        let content = CGSize(width: 200, height: 200)
        let viewport = CGSize(width: 400, height: 400)
        // Content is centered at (100,100); its origin in viewport coords is there.
        let cp = contentPoint(
            fromViewport: CGPoint(x: 100, y: 100), offset: .zero,
            contentSize: content, viewport: viewport)
        #expect(cp == .zero)
    }
}

// MARK: - Pinch anchoring

@Suite("Pinch anchoring")
struct PinchAnchorTests {
    let bounds = Bounds(minRow: 0, minCol: 0, maxRow: 32, maxCol: 32)
    let viewport = CGSize(width: 400, height: 600)

    @Test func alignmentIsIdempotent() {
        // The web comment's invariant: re-running the alignment with the same
        // note moves nothing.
        let metrics = BoardMetrics(bounds: bounds, cellBase: 44, zoom: 1)
        let offset = CGPoint(x: 320, y: 410)
        let mid = CGPoint(x: 150, y: 220)
        let anchor = PinchAnchor.capture(
            midpoint: mid, offset: offset, metrics: metrics, viewport: viewport)
        let aligned = anchor.alignedOffset(midpoint: mid, metrics: metrics, viewport: viewport)
        #expect(abs(aligned.x - offset.x) < 1e-9)
        #expect(abs(aligned.y - offset.y) < 1e-9)
        let again = anchor.alignedOffset(midpoint: mid, metrics: metrics, viewport: viewport)
        #expect(again == aligned)
    }

    @Test func anchoredPointStaysUnderTheFingersThroughAZoom() {
        var metrics = BoardMetrics(bounds: bounds, cellBase: 44, zoom: 1)
        let offset = CGPoint(x: 320, y: 410)
        let mid = CGPoint(x: 150, y: 220)
        let anchor = PinchAnchor.capture(
            midpoint: mid, offset: offset, metrics: metrics, viewport: viewport)
        let grabbed = contentPoint(
            fromViewport: mid, offset: offset, contentSize: metrics.contentSize,
            viewport: viewport)
        let fraction = CGPoint(
            x: grabbed.x / metrics.contentSize.width,
            y: grabbed.y / metrics.contentSize.height)

        metrics.zoom = anchor.zoom(forScale: 1.3)
        let newOffset = anchor.alignedOffset(midpoint: mid, metrics: metrics, viewport: viewport)
        // The same *fraction* of the (now larger) board sits back under the fingers.
        let point = CGPoint(
            x: fraction.x * metrics.contentSize.width,
            y: fraction.y * metrics.contentSize.height)
        let onScreen = viewportPoint(
            fromContent: point, offset: newOffset, contentSize: metrics.contentSize,
            viewport: viewport)
        #expect(abs(onScreen.x - mid.x) < 1e-9)
        #expect(abs(onScreen.y - mid.y) < 1e-9)
    }

    @Test func movingTheMidpointPansTheBoard() {
        // Zoom pinned at a limit, fingers translating: the anchored point
        // follows the fingers — one gesture does both.
        let metrics = BoardMetrics(bounds: bounds, cellBase: 44, zoom: 1)
        let offset = CGPoint(x: 320, y: 410)
        let anchor = PinchAnchor.capture(
            midpoint: CGPoint(x: 150, y: 220), offset: offset, metrics: metrics,
            viewport: viewport)
        let moved = anchor.alignedOffset(
            midpoint: CGPoint(x: 180, y: 260), metrics: metrics, viewport: viewport)
        #expect(abs(moved.x - (offset.x - 30)) < 1e-9)
        #expect(abs(moved.y - (offset.y - 40)) < 1e-9)
    }

    @Test func zoomForScaleClampsToPinchLimits() {
        let anchor = PinchAnchor(fx: 0.5, fy: 0.5, startZoom: 1)
        #expect(anchor.zoom(forScale: 0.01) == MIN_ZOOM)
        #expect(anchor.zoom(forScale: 100) == MAX_ZOOM)
        #expect(anchor.zoom(forScale: 1.2) == 1.2)
    }

    @Test func alignedOffsetClampsAtTheEdges() {
        let metrics = BoardMetrics(bounds: bounds, cellBase: 44, zoom: 1)
        // Anchor at the top-left corner, fingers dragged far right/down:
        // the raw offset would go negative.
        let anchor = PinchAnchor(fx: 0, fy: 0, startZoom: 1)
        let aligned = anchor.alignedOffset(
            midpoint: CGPoint(x: 390, y: 590), metrics: metrics, viewport: viewport)
        #expect(aligned == .zero)
    }
}

// MARK: - Auto-fit

@Suite("Auto-fit zoom")
struct AutoFitTests {
    let viewport = CGSize(width: 400, height: 600)

    @Test func picksTheTighterAxisWithPadding() {
        // 10×5 tiles, padded to 12×7: across is the constraint.
        let box = Bounds(minRow: 0, minCol: 0, maxRow: 4, maxCol: 9)
        let target = autoFitZoom(tileBox: box, viewport: viewport, cellBase: 44, currentZoom: 1)
        let expected = (400.0 / 12 - 1) / 44
        #expect(target != nil)
        #expect(abs(target! - expected) < 1e-9)
    }

    @Test func neverEnlargesPastTheCap() {
        // A tiny crossword would "fit" at zoom 3 — the fit must stay at 1.
        let box = Bounds(minRow: 16, minCol: 16, maxRow: 16, maxCol: 17)
        #expect(
            autoFitZoom(tileBox: box, viewport: viewport, cellBase: 44, currentZoom: 1) == nil)
        // And from a pinched-out state it comes back *up* to at most 1.
        let restored = autoFitZoom(
            tileBox: box, viewport: viewport, cellBase: 44, currentZoom: 0.6)
        #expect(restored == AUTO_ZOOM_MAX)
    }

    @Test func neverShrinksBelowMinZoom() {
        let box = Bounds(minRow: 0, minCol: 0, maxRow: 60, maxCol: 60)
        let target = autoFitZoom(tileBox: box, viewport: viewport, cellBase: 44, currentZoom: 1)
        #expect(target == MIN_ZOOM)
    }

    @Test func ignoresChangesWithinEpsilon() {
        let box = Bounds(minRow: 0, minCol: 0, maxRow: 4, maxCol: 9)
        let target = autoFitZoom(tileBox: box, viewport: viewport, cellBase: 44, currentZoom: 1)!
        #expect(
            autoFitZoom(
                tileBox: box, viewport: viewport, cellBase: 44,
                currentZoom: target + ZOOM_EPSILON * 0.9) == nil)
        #expect(
            autoFitZoom(
                tileBox: box, viewport: viewport, cellBase: 44,
                currentZoom: target + ZOOM_EPSILON * 1.5) != nil)
    }

    @Test func focusCaptureRestoreKeepsTheCenterPoint() {
        let bounds = Bounds(minRow: 0, minCol: 0, maxRow: 32, maxCol: 32)
        var metrics = BoardMetrics(bounds: bounds, cellBase: 44, zoom: 1)
        let box = Bounds(minRow: 10, minCol: 10, maxRow: 22, maxCol: 22)
        let offset = CGPoint(x: 500, y: 480)

        let focus = captureFocus(offset: offset, metrics: metrics, tileBox: box, viewport: viewport)
        metrics.zoom = 0.7
        let restored = restoreOffset(
            focus: focus, metrics: metrics, tileBox: box, viewport: viewport)

        // The point of the tile box that was at the viewport center still is.
        let rect = metrics.rect(ofTileBox: box)
        let centerContent = CGPoint(
            x: rect.minX + focus.fx * rect.width,
            y: rect.minY + focus.fy * rect.height)
        let onScreen = viewportPoint(
            fromContent: centerContent, offset: restored, contentSize: metrics.contentSize,
            viewport: viewport)
        #expect(abs(onScreen.x - viewport.width / 2) < 1e-9)
        #expect(abs(onScreen.y - viewport.height / 2) < 1e-9)
    }

    @Test func restoreClampsToTheScrollRange() {
        let bounds = Bounds(minRow: 0, minCol: 0, maxRow: 32, maxCol: 32)
        let metrics = BoardMetrics(bounds: bounds, cellBase: 44, zoom: MIN_ZOOM)
        let box = Bounds(minRow: 0, minCol: 0, maxRow: 2, maxCol: 2)
        // A focus far past the box's corner would land off the scroll range.
        let restored = restoreOffset(
            focus: ViewportFocus(fx: 40, fy: 40), metrics: metrics, tileBox: box,
            viewport: viewport)
        let limit = maxOffset(contentSize: metrics.contentSize, viewport: viewport)
        #expect(restored.x <= limit.width && restored.y <= limit.height)
        #expect(restored.x >= 0 && restored.y >= 0)
    }
}

// MARK: - Growth compensation

@Suite("Board growth compensation")
struct GrowthCompensationTests {
    @Test func prependedRowsAndColsNudgeTheOffsetByWholeSteps() {
        let old = Bounds(minRow: 0, minCol: 0, maxRow: 32, maxCol: 32)
        let new = Bounds(minRow: -3, minCol: -2, maxRow: 32, maxCol: 32)
        let nudge = growthCompensation(from: old, to: new, step: 45)
        #expect(nudge == CGSize(width: 90, height: 135))
    }

    @Test func growthAtBottomRightNeedsNoCompensation() {
        let old = Bounds(minRow: 0, minCol: 0, maxRow: 32, maxCol: 32)
        let new = Bounds(minRow: 0, minCol: 0, maxRow: 40, maxCol: 38)
        #expect(growthCompensation(from: old, to: new, step: 45) == .zero)
    }

    @Test func aWatchedCellDoesNotMoveOnScreen() {
        // The point of the whole exercise: same cell, same screen position,
        // before and after rows/cols are prepended.
        let viewport = CGSize(width: 400, height: 600)
        let oldMetrics = BoardMetrics(
            bounds: Bounds(minRow: 0, minCol: 0, maxRow: 32, maxCol: 32), cellBase: 44, zoom: 1)
        let newMetrics = BoardMetrics(
            bounds: Bounds(minRow: -2, minCol: -1, maxRow: 32, maxCol: 32), cellBase: 44, zoom: 1)
        let offset = CGPoint(x: 400, y: 300)
        let watched = Cell(row: 8, col: 8)

        let before = viewportPoint(
            fromContent: oldMetrics.rect(of: watched).origin, offset: offset,
            contentSize: oldMetrics.contentSize, viewport: viewport)

        let nudge = growthCompensation(
            from: oldMetrics.bounds, to: newMetrics.bounds, step: newMetrics.step)
        let compensated = CGPoint(x: offset.x + nudge.width, y: offset.y + nudge.height)
        let after = viewportPoint(
            fromContent: newMetrics.rect(of: watched).origin, offset: compensated,
            contentSize: newMetrics.contentSize, viewport: viewport)

        #expect(before == after)
    }
}
