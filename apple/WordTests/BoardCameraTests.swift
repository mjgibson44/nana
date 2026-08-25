import SwiftUI
import WordBoard
import WordCore
import XCTest

@testable import Word

/// The camera's pinch and pan behavior. `PinchAnchor` itself is covered in
/// `WordBoard`; what's tested here is the wiring the app owns — that the live
/// midpoint from `BoardInputBridge` actually reaches the alignment, and that
/// the board still behaves when it doesn't.
@MainActor
final class BoardCameraTests: XCTestCase {

    /// A camera on a full 33×33 board with a phone-sized viewport, scrolled to
    /// the middle so there is room to move in every direction.
    private func camera() -> BoardCamera {
        let camera = BoardCamera()
        camera.viewportChanged(to: CGSize(width: 390, height: 600), tileBox: nil)
        camera.newGame(bounds: Bounds(minRow: 0, minCol: 0, maxRow: 32, maxCol: 32))
        return camera
    }

    /// The board point currently under a viewport point, as a fraction of the
    /// content — the thing a pinch promises to hold still.
    private func anchored(_ camera: BoardCamera, under point: CGPoint) -> CGPoint {
        let size = camera.metrics.contentSize
        let content = contentPoint(
            fromViewport: point, offset: camera.offset, contentSize: size,
            viewport: camera.viewport)
        return CGPoint(x: content.x / size.width, y: content.y / size.height)
    }

    // MARK: The fix

    func testFingersThatTravelWhilePinchingPanTheBoard() {
        let camera = camera()
        let start = CGPoint(x: 195, y: 300)
        let grabbed = anchored(camera, under: start)

        camera.beginPinch(startAnchor: .center, midpoint: start)
        // Same spread, fingers slid 80pt left and 40pt up.
        let moved = CGPoint(x: 115, y: 260)
        camera.updatePinch(scale: 1, midpoint: moved)

        XCTAssertEqual(camera.zoom, 1, accuracy: 1e-9, "an unchanged spread must not zoom")
        let nowUnderFingers = anchored(camera, under: moved)
        XCTAssertEqual(nowUnderFingers.x, grabbed.x, accuracy: 1e-9)
        XCTAssertEqual(nowUnderFingers.y, grabbed.y, accuracy: 1e-9)
    }

    func testTheGrabbedPointStaysUnderTheFingersWhileTheyBothZoomAndTravel() {
        let camera = camera()
        let start = CGPoint(x: 250, y: 400)
        let grabbed = anchored(camera, under: start)

        camera.beginPinch(startAnchor: .center, midpoint: start)
        for (scale, midpoint) in [
            (1.1, CGPoint(x: 240, y: 380)),
            (1.25, CGPoint(x: 210, y: 330)),
            (1.4, CGPoint(x: 180, y: 300)),
        ] {
            camera.updatePinch(scale: scale, midpoint: midpoint)
            let under = anchored(camera, under: midpoint)
            XCTAssertEqual(under.x, grabbed.x, accuracy: 1e-9)
            XCTAssertEqual(under.y, grabbed.y, accuracy: 1e-9)
        }
        XCTAssertEqual(camera.zoom, 1.4, accuracy: 1e-9)
    }

    // MARK: The fallback

    func testWithoutABridgeMidpointThePinchAnchorsOnTheGestureStartAnchor() {
        let camera = camera()
        camera.beginPinch(startAnchor: UnitPoint(x: 0.25, y: 0.75), midpoint: nil)
        let expected = CGPoint(x: 0.25 * 390, y: 0.75 * 600)
        let grabbed = anchored(camera, under: expected)

        camera.updatePinch(scale: 1.3, midpoint: nil)

        XCTAssertEqual(camera.zoom, 1.3, accuracy: 1e-9)
        let under = anchored(camera, under: expected)
        XCTAssertEqual(under.x, grabbed.x, accuracy: 1e-9)
        XCTAssertEqual(under.y, grabbed.y, accuracy: 1e-9)
    }

    func testAMidpointArrivingMidPinchIsAdoptedWithoutRegrabbing() {
        // The bridge can miss the first frame; picking it up later must aim at
        // the point the fingers originally grabbed, not grab a new one.
        let camera = camera()
        let start = CGPoint(x: 195, y: 300)
        let grabbed = anchored(camera, under: start)

        camera.beginPinch(startAnchor: .center, midpoint: start)
        camera.updatePinch(scale: 1.2, midpoint: nil)
        let moved = CGPoint(x: 150, y: 250)
        camera.updatePinch(scale: 1.2, midpoint: moved)

        let under = anchored(camera, under: moved)
        XCTAssertEqual(under.x, grabbed.x, accuracy: 1e-9)
        XCTAssertEqual(under.y, grabbed.y, accuracy: 1e-9)
    }

    func testUpdatesBeforeAPinchBeginsDoNothing() {
        let camera = camera()
        let offset = camera.offset
        camera.updatePinch(scale: 2, midpoint: CGPoint(x: 10, y: 10))
        XCTAssertEqual(camera.zoom, 1)
        XCTAssertEqual(camera.offset, offset)
    }

    // MARK: Scroll-to-pan (macOS)

    func testAScrollPanMovesTheContentWithTheGesture() {
        let camera = camera()
        let before = camera.offset
        camera.pan(by: ScrollPan.panDelta(x: 0, y: 30, precise: true))
        XCTAssertEqual(camera.offset.y, before.y - 30, accuracy: 1e-9)
        XCTAssertEqual(camera.offset.x, before.x, accuracy: 1e-9)
    }

    func testAScrollPanCannotLeaveTheBoard() {
        let camera = camera()
        let content = camera.metrics.contentSize

        // Scrolling the content up far past the end parks at the far edge,
        // never beyond it.
        for _ in 0..<200 {
            camera.pan(by: ScrollPan.panDelta(x: -50, y: -50, precise: true))
        }
        XCTAssertEqual(camera.offset.x, content.width - camera.viewport.width, accuracy: 1e-9)
        XCTAssertEqual(camera.offset.y, content.height - camera.viewport.height, accuracy: 1e-9)

        // And back the other way to the origin.
        for _ in 0..<200 {
            camera.pan(by: ScrollPan.panDelta(x: 50, y: 50, precise: true))
        }
        XCTAssertEqual(camera.offset.x, 0, accuracy: 1e-9)
        XCTAssertEqual(camera.offset.y, 0, accuracy: 1e-9)
    }
}
