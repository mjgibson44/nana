import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Testing

@testable import WordBoard

@Suite("ScrollPan")
struct ScrollPanTests {
    @Test func preciseDeltasPassStraightThrough() {
        // A trackpad already reports points; rescaling them would make the
        // board slide further than the fingers did.
        #expect(ScrollPan.panDelta(x: 12, y: -30, precise: true) == CGSize(width: 12, height: -30))
    }

    @Test func wheelLinesBecomePoints() {
        let delta = ScrollPan.panDelta(x: 0, y: 3, precise: false)
        #expect(delta == CGSize(width: 0, height: 3 * ScrollPan.lineHeight))
    }

    @Test func aNotchMovesLessThanOneCell() {
        // Keeps a wheel feeling like a step rather than a jump (the cell step
        // is CELL_BASE_REGULAR + hairline).
        let notch = ScrollPan.panDelta(x: 0, y: 1, precise: false).height
        #expect(notch < CELL_BASE_REGULAR + CELL_HAIRLINE)
        #expect(notch > 0)
    }

    @Test func signIsPreservedSoTheContentTracksTheGesture() {
        // BoardCamera.pan subtracts the delta from the offset, so a positive
        // scrolling delta has to stay positive to scroll the content the way
        // AppKit already decided the player wants it.
        #expect(ScrollPan.panDelta(x: -5, y: 5, precise: true).width < 0)
        #expect(ScrollPan.panDelta(x: -5, y: 5, precise: true).height > 0)
    }

    @Test func restingFingersAreIgnored() {
        #expect(ScrollPan.panDelta(x: 0, y: 0, precise: true) == .zero)
        #expect(ScrollPan.panDelta(x: 0.001, y: -0.002, precise: true) == .zero)
    }

    @Test func theDeadZoneIsAppliedAfterScalingSoSlowWheelsStillCount() {
        // 1/128 of a line is under the dead zone raw, but a line is 16pt, so
        // it clears once scaled — the check has to come after the scaling or
        // slow wheel scrolls would be silently swallowed. (Powers of two keep
        // the expectation exact in binary.)
        let lines = 0.0078125
        #expect(lines < ScrollPan.deadZone)
        #expect(ScrollPan.panDelta(x: 0, y: lines, precise: false).height == 0.125)
    }

    @Test func nonFiniteDeltasAreDropped() {
        #expect(ScrollPan.panDelta(x: .nan, y: 1, precise: true) == .zero)
        #expect(ScrollPan.panDelta(x: 1, y: .infinity, precise: true) == .zero)
    }
}
