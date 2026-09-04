import SwiftUI
import WordBoard
import WordCore
import XCTest

@testable import Word

/// The plan's §11 zoom-out gate: at max zoom-out the full lattice is 1,100+
/// visible cells, and the stylesheet itself warns about the count. The board
/// is designed to pass — one Canvas pass draws the lattice, and only occupied
/// cells become views — but the gate stays a measured test, not an assumption.
@MainActor
final class BoardRenderTests: XCTestCase {

    /// A busy full-size board: 33×33 bounds, 240 placed tiles.
    private func fullBoardScene() -> BoardScene {
        let bounds = Bounds(minRow: 0, minCol: 0, maxRow: 32, maxCol: 32)
        let metrics = BoardMetrics(bounds: bounds, cellBase: 44, zoom: MIN_ZOOM)
        var tiles: [(key: CellKey, letter: String)] = []
        let letters = "abcdefghijklmnopqrstuvwxyz".map(String.init)
        for row in stride(from: 1, through: 31, by: 2) {
            for col in stride(from: 1, through: 31, by: 2) {
                tiles.append((key: keyOf(row, col), letter: letters[(row + col) % 26]))
            }
        }
        return BoardScene(metrics: metrics, tiles: tiles)
    }

    func testFullBoardAtMaxZoomOutRenders() throws {
        let renderer = ImageRenderer(content: BoardContentView(scene: fullBoardScene()))
        renderer.scale = 2
        XCTAssertNotNil(renderer.cgImage, "the full board must render offscreen")
    }

    func testFullBoardAtMaxZoomOutRenderTime() throws {
        let scene = fullBoardScene()
        measure {
            let renderer = ImageRenderer(content: BoardContentView(scene: scene))
            renderer.scale = 2
            _ = renderer.cgImage
        }
    }
}
