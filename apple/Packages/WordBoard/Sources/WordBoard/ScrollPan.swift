import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// Turning a Mac scroll gesture into a board pan.
///
/// The web game never needed this — a browser's `overflow: auto` wrap panned
/// itself, and the port gave that up on purpose to own the offset (ui.md
/// §8.5–8.7). Owning it means the trackpad's two-finger scroll and a mouse
/// wheel have to be translated by hand, which is all this file is: the
/// arithmetic lives here, pure, so it tests on Linux with the rest of
/// `WordBoard` and the AppKit event plumbing above it stays a thin sensor.
public enum ScrollPan {
    /// A wheel notch is reported in lines, not points. 16pt is AppKit's
    /// conventional line height and lands a notch a little under half a cell
    /// (`CELL_BASE_REGULAR` 44) — enough to feel like a step, small enough
    /// that a flick doesn't fling the board off screen.
    public static let lineHeight: Double = 16

    /// Below this, a scroll is noise from a resting hand on the trackpad.
    public static let deadZone: Double = 0.01

    /// The pan delta for one scroll event, in points.
    ///
    /// Sign convention matches `BoardCamera.pan(by:)`, which moves the content
    /// *with* the gesture (`offset -= delta`) — the same direction the web's
    /// scroll container moved. AppKit has already applied the player's
    /// natural-scrolling preference to the deltas by the time they arrive, so
    /// there is deliberately no inversion here to second-guess it.
    ///
    /// - Parameters:
    ///   - x: the event's horizontal scrolling delta.
    ///   - y: the event's vertical scrolling delta.
    ///   - precise: true for a trackpad or Magic Mouse, whose deltas are
    ///     already in points; false for a wheel, whose deltas are in lines.
    /// - Returns: the pan delta, or `.zero` for a non-event.
    public static func panDelta(x: Double, y: Double, precise: Bool) -> CGSize {
        guard x.isFinite, y.isFinite else { return .zero }
        let scale = precise ? 1 : lineHeight
        let dx = x * scale
        let dy = y * scale
        guard abs(dx) > deadZone || abs(dy) > deadZone else { return .zero }
        return CGSize(width: dx, height: dy)
    }
}
