import SwiftUI
import WordBoard
import WordCore
import XCTest

@testable import Word

/// The board draws the whole lattice — over 1,400pt square at default zoom —
/// and it must never be the layout's *ideal* size. When it was, macOS took it
/// as the window's minimum: the window opened 1,714pt tall on a 1,084pt
/// screen, couldn't be resized down, and the pile fell off the bottom
/// entirely. These tests measure the minimum size the screens actually
/// demand, so that can't come back.
@MainActor
final class WindowSizingTests: XCTestCase {
    /// Comfortably smaller than any laptop screen. Height is the dimension the
    /// bug lived in, so it is held strictly.
    private let maxHeight: CGFloat = 520
    private let maxWidth: CGFloat = 700

    private func playedModel() async throws -> GameModel {
        let model = GameModel()
        model.newGame(seed: "sizing", pace: .regular, now: .now)
        await model.loadDictionary()
        try TestPlays.placeOpener(on: model)
        return model
    }

    #if os(macOS)
    /// `fittingSize` is the smallest size a hosting view will accept — exactly
    /// what AppKit turns into the window's minimum.
    private func minimumSize<V: View>(of view: V) -> CGSize {
        NSHostingView(rootView: view).fittingSize
    }

    func testTheGameScreenFitsInASmallWindow() async throws {
        let size = try await minimumSize(of: GameScreen(model: playedModel()))
        XCTAssertLessThanOrEqual(
            size.height, maxHeight,
            "the game screen demands \(size.height)pt of height — something inside it "
                + "(the board? the pile?) is sizing the window again")
        XCTAssertLessThanOrEqual(size.width, maxWidth, "the game screen demands \(size.width)pt of width")
    }

    func testTheHomeScreenFitsInASmallWindow() {
        let size = minimumSize(
            of: HomeScreen(hasSavedGame: true, onResume: {}, onSolo: {}, onBattle: {}))
        XCTAssertLessThanOrEqual(size.height, maxHeight)
        XCTAssertLessThanOrEqual(size.width, maxWidth)
    }

    /// The word row is one line however long the word, and always one tile
    /// tall — a row that grew a second line would push the board up as the
    /// word was being typed.
    func testTheWordRowIsOneTileTallAtAnyLength() {
        func row(_ count: Int) -> CGSize {
            minimumSize(
                of: WordRowView(
                    picks: (0..<count).map { Pick(letter: "a", rackIndex: $0) },
                    verdict: .good, tileSize: 33, width: 358, onRemove: { _ in }))
        }
        XCTAssertEqual(row(1).height, 33, accuracy: 0.5)
        XCTAssertEqual(row(8).height, 33, accuracy: 0.5)
        XCTAssertEqual(row(PILE_LIMIT).height, 33, accuracy: 0.5)
    }

    /// The pile is always three rows: full or empty, it asks for the same
    /// height, so the board above it never jumps as tiles come and go.
    func testThePileIsAlwaysThreeRowsTall() {
        let empty = minimumSize(
            of: PileView(letters: [], picked: [], tileSize: 32, onTap: { _ in }))
        let full = minimumSize(
            of: PileView(
                letters: Array(repeating: "r", count: PILE_LIMIT), picked: [],
                tileSize: 32, onTap: { _ in }))
        XCTAssertEqual(empty.height, full.height)
        XCTAssertEqual(empty.height, 32 * 3 + Spacing.tileGap * 2, accuracy: 0.5)
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

    /// A render at the Mac window's opening size, for eyeballing that the
    /// header, board, word row, pile and buttons are all on screen together.
    func testGameScreenRendersAtWindowSize() async throws {
        let renderer = ImageRenderer(
            content: try await GameScreen(model: playedModel())
                .frame(width: 440, height: 900)
                .environment(\.colorScheme, .dark))
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
