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

    /// The widest selected-word popover is a crossing: two named runs, with a
    /// disabled rotate affordance in one row. Keep a render around for visual
    /// review while the app's chrome is still evolving.
    func testSnapshotCrossingWordControls() throws {
        let controls = WordControlsView(
            words: [
                WordRun(
                    word: "orbit", direction: .across,
                    cells: (0..<5).map { keyOf(4, $0) }),
                WordRun(
                    word: "ray", direction: .down,
                    cells: (0..<3).map { keyOf($0 + 4, 0) }),
            ],
            canRotate: { $0.direction == .across },
            onGrabBegan: { _, _ in },
            onGrabMoved: { _ in },
            onGrabEnded: { _ in },
            onGrabCancelled: {},
            onRotate: { _ in },
            onRemove: { _ in },
            onHighlight: { _ in })
            .padding(18)
            .background(Ink.boardBg)

        let renderer = ImageRenderer(content: controls)
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.cgImage)
        let url = URL(fileURLWithPath: "/tmp/word-controls-snapshot.png")
        let dest = try XCTUnwrap(
            CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(dest, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
    }

    func testSnapshotSoloSummary() throws {
        let summary = SoloSummaryView(
            words: [
                ScoredWord(word: "crossword", points: 36),
                ScoredWord(word: "orbit", points: 10),
                ScoredWord(word: "solar", points: 10),
                ScoredWord(word: "ray", points: 3),
            ],
            score: 84,
            onPlayAgain: {},
            onSeeBoard: {},
            scrollable: false)
            .frame(width: 390, height: 844, alignment: .top)
            .background(Ink.bg)

        let renderer = ImageRenderer(content: summary)
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.cgImage)
        let url = URL(fileURLWithPath: "/tmp/solo-summary-snapshot.png")
        let dest = try XCTUnwrap(
            CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(dest, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
    }

    func testSnapshotCompactSoloHeader() throws {
        let header = SoloHeaderView(
            score: 84,
            complete: false,
            seconds: 12,
            timerLabel: "Next tiles",
            looseTiles: 22,
            gaugeTone: .over,
            bonusEarned: false,
            canPause: true,
            onPause: {},
            onNewDeal: {},
            onShowSummary: {},
            pace: .fast,
            onChoosePace: { _ in })
            .environment(\.horizontalSizeClass, .compact)
            .frame(width: 390)

        let renderer = ImageRenderer(content: header)
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.cgImage)
        let url = URL(fileURLWithPath: "/tmp/solo-header-snapshot.png")
        let dest = try XCTUnwrap(
            CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(dest, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
    }
}
