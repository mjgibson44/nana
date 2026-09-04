import Observation
import SwiftUI
import WordBoard
import WordCore

/// The board viewport's pan/zoom state, with every correction the web game
/// hand-rolled (pinch anchoring, auto-fit, growth compensation) applied
/// through `WordBoard`'s pure math. Owning the offset outright — instead of
/// fighting a ScrollView for it — is what lets zoom and scroll land in the
/// same update, which the port notes call out as the difference between a
/// stable board and one that tears and snaps (ui.md §8.5–8.7).
@Observable @MainActor
final class BoardCamera {
    /// How many columns the opening view fits across the viewport: enough
    /// for a twelve-letter opener with room either side, on a phone.
    static let openingColumns = 16
    /// Where the start square sits in the opening view: this many cells in
    /// from the left edge, so the opener reads left to right from there.
    static let openingInset = 2

    var zoom: Double = 1
    var offset: CGPoint = .zero
    private(set) var viewport: CGSize = .zero
    /// The board area's frame in the screen's "game" coordinate space — the
    /// hit-testing bridge between gestures and cells.
    var frame: CGRect = .zero
    var cellBase: Double = CELL_BASE_REGULAR
    private(set) var bounds = boardBounds(TileMap())

    /// The start square, for the opening view.
    private var anchor = Cell(row: BOARD_SIZE / 2, col: BOARD_SIZE / 2)
    /// A fixed board opens showing all of it, rather than parked on the
    /// start square.
    private var fitWhole = false
    /// A new game asked for the opening view before the viewport had a size.
    private var homePending = true

    private var pinch: PinchAnchor?
    private var pinchMidpoint: CGPoint = .zero

    var metrics: BoardMetrics {
        BoardMetrics(bounds: bounds, cellBase: cellBase, zoom: zoom)
    }

    var pinchActive: Bool { pinch != nil }

    // MARK: Coordinate bridging

    /// The cell under a point in "game" space, or nil off the board area.
    func cell(atGame point: CGPoint) -> Cell? {
        guard frame.contains(point) else { return nil }
        let local = CGPoint(x: point.x - frame.minX, y: point.y - frame.minY)
        let content = contentPoint(
            fromViewport: local, offset: offset, contentSize: metrics.contentSize,
            viewport: viewport)
        return metrics.cell(at: content)
    }

    /// A content-space rect translated into "game" space.
    func gameRect(ofContent rect: CGRect) -> CGRect {
        let origin = viewportPoint(
            fromContent: rect.origin, offset: offset, contentSize: metrics.contentSize,
            viewport: viewport)
        return CGRect(
            x: origin.x + frame.minX, y: origin.y + frame.minY,
            width: rect.width, height: rect.height)
    }

    // MARK: Sizing

    func viewportChanged(to size: CGSize, tileBox box: Bounds?) {
        viewport = size
        if homePending {
            goHome()
        } else {
            // The web refits on viewport resizes too (fitTick, App.tsx:1071).
            autoFit(box: box)
            offset = clamped(offset)
        }
    }

    /// A fresh board: zoomed out far enough for a long opener, with the start
    /// square parked near the left edge and centred vertically — or, for a
    /// board that never grows, the whole of it centred on screen.
    func newGame(
        bounds: Bounds, anchor: Cell = Cell(row: BOARD_SIZE / 2, col: BOARD_SIZE / 2),
        fitWhole: Bool = false
    ) {
        self.bounds = bounds
        self.anchor = anchor
        self.fitWhole = fitWhole
        homePending = true
        goHome()
    }

    /// The zoom that fits the whole board in the viewport, within the pinch
    /// limits: a fifteen-wide board fits a phone; a nineteen needs a pinch.
    var wholeBoardZoom: Double {
        guard viewport.width > 0, viewport.height > 0 else { return 1 }
        let cols = Double(bounds.maxCol - bounds.minCol + 1)
        let rows = Double(bounds.maxRow - bounds.minRow + 1)
        let fitAcross = (viewport.width / cols - CELL_HAIRLINE) / cellBase
        let fitDown = (viewport.height / rows - CELL_HAIRLINE) / cellBase
        return min(AUTO_ZOOM_MAX, max(MIN_ZOOM, min(fitAcross, fitDown)))
    }

    /// The zoom that fits `openingColumns` across the viewport — never past
    /// 1.0 on a wide screen, never below the pinch floor on a narrow one.
    var openingZoom: Double {
        guard viewport.width > 0 else { return 1 }
        let fit = (viewport.width / Double(Self.openingColumns) - CELL_HAIRLINE) / cellBase
        return min(AUTO_ZOOM_MAX, max(MIN_ZOOM, fit))
    }

    private func goHome() {
        guard viewport != .zero else { return }
        homePending = false
        if fitWhole {
            zoom = wholeBoardZoom
            offset = centeredOffset(contentSize: metrics.contentSize, viewport: viewport)
            return
        }
        zoom = openingZoom
        let rect = metrics.rect(of: anchor)
        offset = clamped(
            CGPoint(
                x: rect.minX - Double(Self.openingInset) * metrics.step,
                y: rect.midY - viewport.height / 2))
    }

    /// The board grew. Prepended rows/cols get the same-update scroll nudge
    /// that keeps the crossword from visibly jumping (App.tsx:1035–1046).
    func boundsChanged(to new: Bounds) {
        let old = bounds
        bounds = new
        guard old != new else { return }
        let nudge = growthCompensation(from: old, to: new, step: metrics.step)
        offset = clamped(CGPoint(x: offset.x + nudge.width, y: offset.y + nudge.height))
    }

    // MARK: Panning

    func pan(by delta: CGSize) {
        offset = clamped(CGPoint(x: offset.x - delta.width, y: offset.y - delta.height))
    }

    /// A little momentum on release, in place of the ScrollView deceleration
    /// this container gave up.
    func endPan(velocity: CGSize) {
        let projected = CGPoint(
            x: offset.x - velocity.width * 0.12,
            y: offset.y - velocity.height * 0.12)
        let target = clamped(projected)
        guard target != offset else { return }
        withAnimation(.easeOut(duration: 0.35)) {
            offset = target
        }
    }

    // MARK: Pinch (App.tsx:2744–2895)

    /// Grab the board point under the fingers, once. `midpoint` is the live
    /// two-finger midpoint from `BoardInputBridge`; `startAnchor` is
    /// `MagnifyGesture`'s own estimate, used only when the bridge has nothing
    /// to say (it never attached, or the pinch began before it saw a touch).
    func beginPinch(startAnchor: UnitPoint, midpoint: CGPoint?) {
        pinchMidpoint =
            midpoint
            ?? CGPoint(x: startAnchor.x * viewport.width, y: startAnchor.y * viewport.height)
        pinch = PinchAnchor.capture(
            midpoint: pinchMidpoint, offset: offset, metrics: metrics, viewport: viewport)
    }

    /// Re-aim the anchored point every change: zoom and the matching scroll
    /// correction land in the same update, so the board never tears. Tracking
    /// the *live* midpoint is what makes a pinch that also travels pan the
    /// board with the fingers, the way the web's does (App.tsx:2823–2861).
    func updatePinch(scale: Double, midpoint: CGPoint?) {
        guard let pinch else { return }
        if let midpoint { pinchMidpoint = midpoint }
        zoom = pinch.zoom(forScale: scale)
        offset = pinch.alignedOffset(midpoint: pinchMidpoint, metrics: metrics, viewport: viewport)
    }

    func endPinch() {
        pinch = nil
    }

    // MARK: Auto-fit (App.tsx:1089–1133)

    /// Whenever the tiles change, make sure all of them still fit on screen —
    /// by zooming *out*, never in. The opening view is deliberately wide, and
    /// a pinch the player chose is theirs to keep; the only thing this
    /// corrects is a crossword that has outgrown the viewport. The point the
    /// player was looking at goes straight back.
    func autoFit(box: Bounds?) {
        guard let box, viewport != .zero else { return }
        guard
            let target = autoFitZoom(
                tileBox: box, viewport: viewport, cellBase: cellBase, currentZoom: zoom),
            target < zoom
        else { return }
        let focus = captureFocus(offset: offset, metrics: metrics, tileBox: box, viewport: viewport)
        zoom = target
        offset = restoreOffset(focus: focus, metrics: metrics, tileBox: box, viewport: viewport)
    }

    private func clamped(_ candidate: CGPoint) -> CGPoint {
        clampOffset(candidate, contentSize: metrics.contentSize, viewport: viewport)
    }
}
