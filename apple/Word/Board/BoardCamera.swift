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
    var zoom: Double = 1
    var offset: CGPoint = .zero
    private(set) var viewport: CGSize = .zero
    /// The board area's frame in the screen's "game" coordinate space — the
    /// hit-testing bridge between gestures and cells.
    var frame: CGRect = .zero
    var cellBase: Double = CELL_BASE_REGULAR
    private(set) var bounds = boardBounds(TileMap())

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

    /// A content-space rect translated into "game" space (for hit-testing
    /// chrome like the rotate control).
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
        let first = viewport == .zero
        viewport = size
        if first {
            center()
        } else {
            // The web refits on viewport resizes too (fitTick, App.tsx:1071).
            autoFit(box: box)
            offset = clamped(offset)
        }
    }

    /// Center the board — the web's new-game scroll (App.tsx:1015–1021).
    func center() {
        offset = centeredOffset(contentSize: metrics.contentSize, viewport: viewport)
    }

    func newGame(bounds: Bounds) {
        self.bounds = bounds
        zoom = 1
        center()
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

    /// Grab the board point under the fingers, once. `startAnchor` is the
    /// gesture's initial midpoint as a fraction of the board area.
    func beginPinch(startAnchor: UnitPoint) {
        pinchMidpoint = CGPoint(
            x: startAnchor.x * viewport.width, y: startAnchor.y * viewport.height)
        pinch = PinchAnchor.capture(
            midpoint: pinchMidpoint, offset: offset, metrics: metrics, viewport: viewport)
    }

    /// Re-aim the anchored point every change: zoom and the matching scroll
    /// correction land in the same update, so the board never tears.
    func updatePinch(scale: Double) {
        guard let pinch else { return }
        zoom = pinch.zoom(forScale: scale)
        offset = pinch.alignedOffset(midpoint: pinchMidpoint, metrics: metrics, viewport: viewport)
    }

    func endPinch() {
        pinch = nil
    }

    // MARK: Auto-fit (App.tsx:1089–1133)

    /// Whenever the tiles change, re-pick the zoom that shows all of them —
    /// shrink-only — and put the point the player was looking at straight
    /// back. Never scrolls toward the tiles.
    func autoFit(box: Bounds?) {
        guard let box, viewport != .zero else { return }
        guard
            let target = autoFitZoom(
                tileBox: box, viewport: viewport, cellBase: cellBase, currentZoom: zoom)
        else { return }
        let focus = captureFocus(offset: offset, metrics: metrics, tileBox: box, viewport: viewport)
        zoom = target
        offset = restoreOffset(focus: focus, metrics: metrics, tileBox: box, viewport: viewport)
    }

    private func clamped(_ candidate: CGPoint) -> CGPoint {
        clampOffset(candidate, contentSize: metrics.contentSize, viewport: viewport)
    }
}
