import SwiftUI
import WordBoard
import WordCore
import XCTest

@testable import Word

/// Renders the real model + board pipeline to a PNG for eyeballing during
/// development: a seeded deal, a few commits through the real commit funnel,
/// a staged word previewing. Written to /tmp/word-board-snapshot.png.
@MainActor
final class BoardSnapshotTests: XCTestCase {
    func testSnapshotPlayedBoard() async throws {
        let model = GameModel()
        model.newGame(seed: "hello")
        await model.loadDictionary()

        // Play the hidden solution's words through the real commit funnel:
        // stage picks by rack index, anchor, commit.
        let puzzle = try generatePuzzle(
            wordPool: commonWords, tileCount: ENDLESS_START_TILES, rng: seededRng("hello"))
        if let solution = puzzle.solution {
            for (key, letter) in solution.entries {
                let index = findAvailable(rack: model.rack, letter: letter, taken: [])
                guard index != -1 else { continue }
                model.cellClick(key)
                model.togglePick(index)
                if let target = model.target { model.commit(target.key, target.dir) }
            }
        }
        XCTAssertFalse(model.board.isEmpty, "some tiles should have landed")

        // Stage a word so the preview ghosts + cursor render too.
        if !model.rack.isEmpty {
            model.togglePick(0)
            if model.rack.count > 1 { model.togglePick(1) }
            model.cellClick(keyOf(10, 10))
        }

        var metrics = BoardMetrics(bounds: model.bounds, cellBase: 44, zoom: 1)
        if let box = model.tileBounds {
            metrics.bounds = Bounds(
                minRow: box.minRow - 2, minCol: box.minCol - 2,
                maxRow: box.maxRow + 6, maxCol: box.maxCol + 6)
        }
        let scene = BoardScene(
            metrics: metrics,
            tiles: model.board.entries.map { (key: $0.key, letter: $0.value) },
            feedback: model.cellFeedback,
            preview: model.preview,
            previewGaps: model.previewGaps,
            cursorKey: model.cursorKey,
            selectedKey: model.selectedKey)
        let renderer = ImageRenderer(content: BoardContentView(scene: scene))
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.cgImage)
        let url = URL(fileURLWithPath: "/tmp/word-board-snapshot.png")
        let dest = try XCTUnwrap(
            CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(dest, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
    }
}
