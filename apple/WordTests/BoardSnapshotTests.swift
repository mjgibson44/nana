import SwiftUI
import WordBoard
import WordCore
import XCTest

@testable import Word

/// Renders the real model + board pipeline to a PNG for eyeballing during
/// development: a seeded deal, an opener and a word attached through it via
/// the real commit funnel. Written to /tmp/word-board-snapshot.png.
@MainActor
final class BoardSnapshotTests: XCTestCase {
    func testSnapshotPlayedBoard() async throws {
        let model = GameModel()
        model.newGame(seed: "hello")
        await model.loadDictionary()

        try TestPlays.placeOpener(on: model)
        try TestPlays.attachWord(on: model)
        XCTAssertGreaterThan(model.board.count, 3, "two words should be down")

        var metrics = BoardMetrics(bounds: model.bounds, cellBase: 38, zoom: 0.56)
        if let box = model.tileBounds {
            metrics.bounds = Bounds(
                minRow: box.minRow - 4, minCol: box.minCol - 2,
                maxRow: box.maxRow + 6, maxCol: box.maxCol + 8)
        }
        let scene = BoardScene(
            metrics: metrics,
            tiles: model.board.entries.map { (key: $0.key, letter: $0.value) })
        let renderer = ImageRenderer(content: BoardContentView(scene: scene))
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.cgImage)
        let url = URL(fileURLWithPath: "/tmp/word-board-snapshot.png")
        let dest = try XCTUnwrap(
            CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(dest, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
    }

    /// The opener previewing from the start square, before it's confirmed.
    func testSnapshotOpenerPreview() async throws {
        let model = GameModel()
        model.newGame(seed: "hello")
        await model.loadDictionary()
        guard let (_, indices) = TestPlays.spellableWord(in: model) else {
            throw XCTSkip("this rack can't spell an opener")
        }
        for index in indices { model.togglePick(index) }
        XCTAssertFalse(model.preview.isEmpty)

        let metrics = BoardMetrics(
            bounds: Bounds(
                minRow: GameModel.startCell.row - 3, minCol: GameModel.startCell.col - 2,
                maxRow: GameModel.startCell.row + 3, maxCol: GameModel.startCell.col + 12),
            cellBase: 38, zoom: 0.56)
        let scene = BoardScene(metrics: metrics, tiles: [], preview: model.preview)
        let renderer = ImageRenderer(content: BoardContentView(scene: scene))
        renderer.scale = 2
        XCTAssertNotNil(renderer.cgImage)
    }
}
