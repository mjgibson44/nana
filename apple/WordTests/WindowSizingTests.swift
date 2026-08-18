import SwiftUI
import WordBoard
import WordCore
import XCTest

@testable import Word

/// The board draws the whole lattice — over 1,400pt square at default zoom —
/// and it must never be the layout's *ideal* size. When it was, macOS took it
/// as the window's minimum: the window opened 1,714pt tall on a 1,084pt
/// screen, couldn't be resized down, and the word bar and pile fell off the
/// bottom entirely. These tests measure the minimum size the screens actually
/// demand, so that can't come back.
@MainActor
final class WindowSizingTests: XCTestCase {
    /// Comfortably smaller than any laptop screen. Height is the dimension the
    /// bug lived in (a 1,714pt-tall window on a 1,084pt screen), so it is held
    /// strictly; width is looser because the tutorial's instruction text
    /// legitimately wants a readable line length.
    private let maxHeight: CGFloat = 520
    private let maxWidth: CGFloat = 700

    private func playedModel() -> GameModel {
        let model = GameModel()
        model.newGame(seed: "sizing", pace: .regular, now: .now)
        model.cellClick(keyOf(16, 16))
        model.togglePick(0)
        if let target = model.target { model.commit(target.key, target.dir) }
        return model
    }

    #if os(macOS)
    /// `fittingSize` is the smallest size a hosting view will accept — exactly
    /// what AppKit turns into the window's minimum.
    private func minimumSize<V: View>(of view: V) -> CGSize {
        NSHostingView(rootView: view).fittingSize
    }

    func testTheGameScreenFitsInASmallWindow() {
        let size = minimumSize(of: GameScreen(model: playedModel()))
        XCTAssertLessThanOrEqual(
            size.height, maxHeight,
            "the game screen demands \(size.height)pt of height — something inside it "
                + "(the board? the pile?) is sizing the window again")
        XCTAssertLessThanOrEqual(size.width, maxWidth, "the game screen demands \(size.width)pt of width")
    }

    func testTheTutorialScreenFitsToo() {
        let model = GameModel()
        model.newTutorial()
        let size = minimumSize(of: GameScreen(model: model))
        XCTAssertLessThanOrEqual(size.height, maxHeight)
        XCTAssertLessThanOrEqual(size.width, maxWidth)
    }

    func testTheHomeScreenFitsInASmallWindow() {
        let size = minimumSize(
            of: HomeScreen(
                hasSavedGame: true, onResume: {}, onChoose: { _ in }, onTutorial: {},
                onStats: {}, onSettings: {}))
        XCTAssertLessThanOrEqual(size.height, maxHeight)
        XCTAssertLessThanOrEqual(size.width, maxWidth)
    }
    #endif

    #if os(macOS)
    /// The pile is the other view that can run away: a bare `LazyVGrid` asked
    /// for its ideal size stacks every tile into a single column.
    func testThePileStaysABoundedHeight() {
        let model = playedModel()
        let size = minimumSize(
            of: RackView(
                letters: model.rack, hiddenIndex: nil, picks: [], pointerEvent: { _ in },
                downTarget: { index, letter in .rackTile(index: index, letter: letter) },
                onShuffle: {}))
        XCTAssertLessThanOrEqual(
            size.height, 220,
            "the pile demands \(size.height)pt — it should scroll past a few rows, not grow")
        XCTAssertGreaterThan(size.height, 40, "but it must still show a row of tiles")
    }
    #endif

    /// The board's own content is *supposed* to be huge — that's the lattice.
    /// This pins the premise the tests above rest on, so a future change that
    /// shrinks the lattice doesn't quietly make them vacuous.
    func testTheBoardContentIsIndeedLargerThanAnyWindow() {
        let metrics = BoardMetrics(
            bounds: Bounds(minRow: 0, minCol: 0, maxRow: 32, maxCol: 32), cellBase: 44, zoom: 1)
        XCTAssertGreaterThan(metrics.contentSize.height, 1_400)
        XCTAssertGreaterThan(metrics.contentSize.width, 1_400)
    }

    /// A render at a real window size, for eyeballing that the header, word bar
    /// and pile are all on screen together.
    func testGameScreenRendersAtWindowSize() throws {
        let renderer = ImageRenderer(
            content: GameScreen(model: playedModel())
                .frame(width: 980, height: 760)
                .environment(\.colorScheme, .light))
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.cgImage)
        let url = URL(fileURLWithPath: "/tmp/word-game-at-window-size.png")
        if let dest = CGImageDestinationCreateWithURL(
            url as CFURL, "public.png" as CFString, 1, nil)
        {
            CGImageDestinationAddImage(dest, image, nil)
            CGImageDestinationFinalize(dest)
        }
    }
}
