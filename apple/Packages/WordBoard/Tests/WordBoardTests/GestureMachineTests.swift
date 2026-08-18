import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Testing
import WordCore

@testable import WordBoard

/// Every scenario drives the machine with raw events and checks the exact
/// intent stream — the port of the behaviors inventoried in
/// `docs/apple-port-notes/ui.md` §3 and §8.
@Suite("GestureMachine")
struct GestureMachineTests {
    typealias M = GestureMachine
    typealias E = GestureMachine.Effect

    let cell = Cell(row: 16, col: 16)
    let other = Cell(row: 4, col: 9)

    func down(
        _ m: inout M, id: Int = 1, kind: M.PointerKind = .touch,
        at point: CGPoint = CGPoint(x: 100, y: 100), target: M.DownTarget,
        time: Double = 0, context: M.Context = M.Context()
    ) -> [E] {
        m.handle(.down(id: id, kind: kind, location: point, target: target, time: time, context: context))
    }

    func move(
        _ m: inout M, id: Int = 1, to point: CGPoint, time: Double = 0
    ) -> [E] {
        m.handle(.move(id: id, location: point, time: time))
    }

    func up(
        _ m: inout M, id: Int = 1, at point: CGPoint = CGPoint(x: 100, y: 100),
        time: Double = 0, velocity: CGSize = .zero
    ) -> [E] {
        m.handle(.up(id: id, location: point, time: time, velocity: velocity))
    }

    // MARK: Rack tiles (ui.md §3.2–3.3)

    @Test func rackTilePressLiftsTheGhostImmediately() {
        var m = M()
        let effects = down(&m, target: .rackTile(index: 3, letter: "r"))
        #expect(effects == [
            .beginDrag(source: .rack(index: 3, letter: "r"), at: CGPoint(x: 100, y: 100))
        ])
    }

    @Test func rackTileTapTogglesThePick() {
        var m = M()
        _ = down(&m, target: .rackTile(index: 3, letter: "r"))
        let effects = up(&m, at: CGPoint(x: 103, y: 98))
        #expect(effects == [.endDrag(drop: nil), .tapRackTile(index: 3)])
        #expect(m.state == .idle)
    }

    @Test func rackTileDragDropsWhereItEnded() {
        var m = M()
        _ = down(&m, target: .rackTile(index: 0, letter: "a"))
        #expect(move(&m, to: CGPoint(x: 140, y: 90)) == [.dragMoved(CGPoint(x: 140, y: 90))])
        let effects = up(&m, at: CGPoint(x: 200, y: 300))
        #expect(effects == [.endDrag(drop: CGPoint(x: 200, y: 300))])
    }

    @Test func aDragThatWandersBackToItsStartIsATapLikeTheWeb() {
        // The web decides tap-vs-drag purely from the *final* position
        // (App.tsx:2443): a ghost carried away and brought back within the
        // slop reads as putting the tile down again, i.e. a tap.
        var m = M()
        _ = down(&m, target: .rackTile(index: 0, letter: "a"))
        _ = move(&m, to: CGPoint(x: 200, y: 200))
        let effects = up(&m, at: CGPoint(x: 100.5, y: 100))
        #expect(effects == [.endDrag(drop: nil), .tapRackTile(index: 0)])
    }

    @Test func slopBoundaryMatchesTheWeb() {
        // Web: tap iff |dx| < 6 AND |dy| < 6 (App.tsx:2443).
        var m = M()
        _ = down(&m, target: .rackTile(index: 1, letter: "b"))
        #expect(up(&m, at: CGPoint(x: 105.9, y: 105.9)) == [
            .endDrag(drop: nil), .tapRackTile(index: 1),
        ])
        _ = down(&m, target: .rackTile(index: 1, letter: "b"))
        #expect(up(&m, at: CGPoint(x: 106, y: 100)) == [
            .endDrag(drop: CGPoint(x: 106, y: 100))
        ])
    }

    // MARK: Board tiles (ui.md §3.4, 3.6, 3.7)

    @Test func boardTileTapSelects() {
        var m = M()
        _ = down(&m, target: .boardTile(cell: cell, letter: "c"))
        #expect(up(&m) == [.endDrag(drop: nil), .tapBoardTile(cell)])
    }

    @Test func boardTileDragMovesTheTile() {
        var m = M()
        let start = down(&m, target: .boardTile(cell: cell, letter: "c"))
        #expect(start == [
            .beginDrag(source: .board(cell: cell, letter: "c"), at: CGPoint(x: 100, y: 100))
        ])
        _ = move(&m, to: CGPoint(x: 60, y: 100))
        #expect(up(&m, at: CGPoint(x: 60, y: 100)) == [.endDrag(drop: CGPoint(x: 60, y: 100))])
    }

    @Test func doublePressFiresOnTheSecondDownWithoutDragLatency() {
        var m = M()
        // First press starts its drag immediately — no waiting on a double.
        let first = down(&m, target: .boardTile(cell: cell, letter: "c"), time: 1.0)
        #expect(first.first == .beginDrag(source: .board(cell: cell, letter: "c"), at: CGPoint(x: 100, y: 100)))
        _ = up(&m, time: 1.05)
        // Second press inside 350ms: rotate/return, and no new drag.
        let second = down(&m, target: .boardTile(cell: cell, letter: "c"), time: 1.2)
        #expect(second == [.doubleTapBoardTile(cell)])
        // Its release is spent silence.
        #expect(up(&m, time: 1.25) == [])
        #expect(m.state == .idle)
    }

    @Test func doublePressWindowIsStrict() {
        var m = M()
        _ = down(&m, target: .boardTile(cell: cell, letter: "c"), time: 0)
        _ = up(&m, time: 0.05)
        // Exactly 350ms later is too late (web: strictly < 350).
        let second = down(&m, target: .boardTile(cell: cell, letter: "c"), time: DOUBLE_PRESS_SECONDS)
        #expect(second == [
            .beginDrag(source: .board(cell: cell, letter: "c"), at: CGPoint(x: 100, y: 100))
        ])
    }

    @Test func doublePressNeedsTheSameCell() {
        var m = M()
        _ = down(&m, target: .boardTile(cell: cell, letter: "c"), time: 0)
        _ = up(&m, time: 0.05)
        let second = down(&m, target: .boardTile(cell: other, letter: "d"), time: 0.1)
        #expect(second == [
            .beginDrag(source: .board(cell: other, letter: "d"), at: CGPoint(x: 100, y: 100))
        ])
    }

    @Test func aThirdPressStartsANewCycle() {
        var m = M()
        _ = down(&m, target: .boardTile(cell: cell, letter: "c"), time: 0)
        _ = up(&m, time: 0.05)
        _ = down(&m, target: .boardTile(cell: cell, letter: "c"), time: 0.1)  // double fires
        _ = up(&m, time: 0.15)
        // The double cleared the press record: this one is a fresh first press.
        let third = down(&m, target: .boardTile(cell: cell, letter: "c"), time: 0.2)
        #expect(third == [
            .beginDrag(source: .board(cell: cell, letter: "c"), at: CGPoint(x: 100, y: 100))
        ])
    }

    @Test func aQuickDragThenPressStillCountsAsADouble() {
        // Faithful web quirk: lastPress is recorded at down even if the press
        // becomes a drag (App.tsx:2586–2587).
        var m = M()
        _ = down(&m, target: .boardTile(cell: cell, letter: "c"), time: 0)
        _ = move(&m, to: CGPoint(x: 200, y: 200), time: 0.1)
        _ = up(&m, at: CGPoint(x: 200, y: 200), time: 0.15)
        let next = down(&m, target: .boardTile(cell: cell, letter: "c"), time: 0.3)
        #expect(next == [.doubleTapBoardTile(cell)])
    }

    // MARK: Locked (battle) boards (ui.md §8.13)

    @Test func lockedBoardTileTapsAtPressTimeAndNeverDrags() {
        var m = M()
        let locked = M.Context(boardLocked: true)
        let effects = down(&m, target: .boardTile(cell: cell, letter: "c"), context: locked)
        #expect(effects == [.tapBoardTile(cell)])
        // Movement does nothing; the press is spent.
        #expect(move(&m, to: CGPoint(x: 300, y: 300)) == [])
        #expect(up(&m, at: CGPoint(x: 300, y: 300)) == [])
    }

    @Test func lockedBoardHasNoDoublePress() {
        var m = M()
        let locked = M.Context(boardLocked: true)
        _ = down(&m, target: .boardTile(cell: cell, letter: "c"), time: 0, context: locked)
        _ = up(&m, time: 0.05)
        let second = down(&m, target: .boardTile(cell: cell, letter: "c"), time: 0.1, context: locked)
        #expect(second == [.tapBoardTile(cell)])
    }

    @Test func lockedBoardStillArmsTheHoldPreview() {
        // Aiming the staged word stays allowed on locked boards.
        var m = M()
        let context = M.Context(boardLocked: true, hasStagedPicks: true)
        let effects = down(&m, target: .boardEmpty(cell: cell), context: context)
        #expect(effects == [.scheduleHold(id: 1)])
    }

    // MARK: Empty board: taps and pans (ui.md §3.1, §8.2)

    @Test func emptyCellTapAnchors() {
        var m = M()
        _ = down(&m, kind: .mouse, target: .boardEmpty(cell: cell))
        #expect(up(&m, at: CGPoint(x: 102, y: 99)) == [.tapBoardCell(cell)])
    }

    @Test func gutterTapDoesNothing() {
        var m = M()
        _ = down(&m, kind: .mouse, target: .boardEmpty(cell: nil))
        #expect(up(&m) == [])
    }

    @Test func emptyBoardDragPans() {
        var m = M()
        _ = down(&m, kind: .touch, target: .boardEmpty(cell: cell))
        let first = move(&m, to: CGPoint(x: 110, y: 95))
        #expect(first == [.beginPan, .panBy(CGSize(width: 10, height: -5))])
        #expect(move(&m, to: CGPoint(x: 115, y: 95)) == [.panBy(CGSize(width: 5, height: 0))])
        #expect(
            up(&m, at: CGPoint(x: 115, y: 95), velocity: CGSize(width: 120, height: 0))
                == [.endPan(velocity: CGSize(width: 120, height: 0))])
    }

    @Test func panWaitsForSlop() {
        var m = M()
        _ = down(&m, kind: .touch, target: .boardEmpty(cell: cell))
        #expect(move(&m, to: CGPoint(x: 104, y: 103)) == [])
        #expect(move(&m, to: CGPoint(x: 106, y: 103)) == [
            .beginPan, .panBy(CGSize(width: 6, height: 3)),
        ])
    }

    @Test func tilesNeverPanTheBoard() {
        // Dragging a tile must not scroll — the down target decides.
        var m = M()
        _ = down(&m, target: .boardTile(cell: cell, letter: "c"))
        let effects = move(&m, to: CGPoint(x: 400, y: 400))
        #expect(effects == [.dragMoved(CGPoint(x: 400, y: 400))])
        #expect(!effects.contains(.beginPan))
    }

    // MARK: Hold-to-drag preview (ui.md §3.9, §8.3)

    let staged = M.Context(hasStagedPicks: true)

    @Test func holdArmsOnlyWithLettersStaged() {
        var m = M()
        #expect(down(&m, kind: .touch, target: .boardEmpty(cell: cell)) == [])
        _ = up(&m)
        #expect(down(&m, kind: .touch, target: .boardEmpty(cell: cell), context: staged) == [
            .scheduleHold(id: 1)
        ])
    }

    @Test func holdIsATouchAndPenAffordanceNeverMouse() {
        var m = M()
        #expect(down(&m, kind: .mouse, target: .boardEmpty(cell: cell), context: staged) == [])
        _ = up(&m)
        #expect(down(&m, kind: .pen, target: .boardEmpty(cell: cell), context: staged) == [
            .scheduleHold(id: 1)
        ])
    }

    @Test func holdFiringStartsThePreviewDragAtThePressPoint() {
        var m = M()
        _ = down(&m, kind: .touch, target: .boardEmpty(cell: cell), context: staged)
        #expect(m.handle(.holdFired(id: 1)) == [.beginPreviewDrag(at: CGPoint(x: 100, y: 100))])
        #expect(move(&m, to: CGPoint(x: 150, y: 150)) == [.previewDragMoved(CGPoint(x: 150, y: 150))])
        #expect(up(&m, at: CGPoint(x: 160, y: 170)) == [.endPreviewDrag(at: CGPoint(x: 160, y: 170))])
    }

    @Test func movementBeforeTheHoldCancelsIntoAPan() {
        var m = M()
        _ = down(&m, kind: .touch, target: .boardEmpty(cell: cell), context: staged)
        let effects = move(&m, to: CGPoint(x: 110, y: 100))
        #expect(effects == [.cancelHold, .beginPan, .panBy(CGSize(width: 10, height: 0))])
        // The timer was cancelled; a late fire must not resurrect it.
        #expect(m.handle(.holdFired(id: 1)) == [])
    }

    @Test func releaseBeforeTheHoldIsATap() {
        var m = M()
        _ = down(&m, kind: .touch, target: .boardEmpty(cell: cell), context: staged)
        #expect(up(&m, at: CGPoint(x: 101, y: 101)) == [.cancelHold, .tapBoardCell(cell)])
        #expect(m.handle(.holdFired(id: 1)) == [])
    }

    @Test func previewDragNeverPans() {
        var m = M()
        _ = down(&m, kind: .touch, target: .boardEmpty(cell: cell), context: staged)
        _ = m.handle(.holdFired(id: 1))
        #expect(m.ownsPointer)
        let effects = move(&m, to: CGPoint(x: 300, y: 300))
        #expect(!effects.contains(.beginPan))
    }

    @Test func previewDragCancelDoesNotAnchor() {
        var m = M()
        _ = down(&m, kind: .touch, target: .boardEmpty(cell: cell), context: staged)
        _ = m.handle(.holdFired(id: 1))
        #expect(m.handle(.cancel(id: 1)) == [.cancelPreviewDrag])
    }

    @Test func staleHoldTimerIsIgnored() {
        var m = M()
        _ = down(&m, kind: .touch, target: .boardEmpty(cell: cell), context: staged)
        _ = up(&m, at: CGPoint(x: 100, y: 100))
        #expect(m.handle(.holdFired(id: 1)) == [])
        // And a fire for a pointer that never pressed.
        #expect(m.handle(.holdFired(id: 99)) == [])
    }

    // MARK: Pointer identity (ui.md §8.15)

    @Test func aSecondFingerCannotHijackADrag() {
        var m = M()
        _ = down(&m, id: 1, target: .rackTile(index: 0, letter: "a"))
        // A second pointer pressing, moving and lifting changes nothing.
        #expect(down(&m, id: 2, target: .boardTile(cell: cell, letter: "c")) == [])
        #expect(move(&m, id: 2, to: CGPoint(x: 300, y: 300)) == [])
        #expect(up(&m, id: 2, at: CGPoint(x: 300, y: 300)) == [])
        // The original drag is still live.
        #expect(move(&m, id: 1, to: CGPoint(x: 150, y: 100)) == [.dragMoved(CGPoint(x: 150, y: 100))])
        #expect(up(&m, id: 1, at: CGPoint(x: 150, y: 100)) == [.endDrag(drop: CGPoint(x: 150, y: 100))])
    }

    @Test func cancelEndsEachGestureQuietly() {
        var m = M()
        _ = down(&m, target: .rackTile(index: 0, letter: "a"))
        #expect(m.handle(.cancel(id: 1)) == [.endDrag(drop: nil)])

        _ = down(&m, kind: .touch, target: .boardEmpty(cell: cell), context: staged)
        #expect(m.handle(.cancel(id: 1)) == [.cancelHold])

        _ = down(&m, kind: .touch, target: .boardEmpty(cell: cell))
        _ = move(&m, to: CGPoint(x: 130, y: 100))
        #expect(m.handle(.cancel(id: 1)) == [.endPan(velocity: .zero)])
    }

    @Test func cancelForAnotherPointerIsIgnored() {
        var m = M()
        _ = down(&m, target: .rackTile(index: 0, letter: "a"))
        #expect(m.handle(.cancel(id: 7)) == [])
        #expect(up(&m) == [.endDrag(drop: nil), .tapRackTile(index: 0)])
    }

    // MARK: Pinch interplay (ui.md §8.15, §3.10)

    @Test func pinchCancelsAPanAndAPress() {
        var m = M()
        _ = down(&m, kind: .touch, target: .boardEmpty(cell: cell))
        _ = move(&m, to: CGPoint(x: 130, y: 100))
        #expect(m.handle(.pinchBegan) == [.endPan(velocity: .zero)])

        _ = down(&m, kind: .touch, target: .boardEmpty(cell: cell), context: staged)
        #expect(m.handle(.pinchBegan) == [.cancelHold])
        #expect(m.state == .idle)
    }

    @Test func pinchCancelsADragAndThePreview() {
        var m = M()
        _ = down(&m, target: .boardTile(cell: cell, letter: "c"))
        #expect(m.handle(.pinchBegan) == [.endDrag(drop: nil)])

        _ = down(&m, kind: .touch, target: .boardEmpty(cell: cell), context: staged)
        _ = m.handle(.holdFired(id: 1))
        #expect(m.handle(.pinchBegan) == [.cancelPreviewDrag])
    }

    @Test func pinchWhileIdleIsSilent() {
        var m = M()
        #expect(m.handle(.pinchBegan) == [])
    }

    // MARK: External drags (word-controls grab)

    @Test func boardIsInertUnderAnExternalWordDrag() {
        var m = M()
        let context = M.Context(hasStagedPicks: true, externalDragActive: true)
        #expect(down(&m, target: .boardTile(cell: cell, letter: "c"), context: context) == [])
        #expect(down(&m, target: .boardEmpty(cell: cell), context: context) == [])
        #expect(m.state == .idle)
    }

    // MARK: ownsPointer (drives .scrollDisabled-style decisions)

    @Test func ownsPointerTracksClaimingStates() {
        var m = M()
        #expect(!m.ownsPointer)
        _ = down(&m, kind: .touch, target: .boardEmpty(cell: cell), context: staged)
        #expect(!m.ownsPointer)  // could still become a pan
        _ = m.handle(.holdFired(id: 1))
        #expect(m.ownsPointer)
        _ = up(&m, at: CGPoint(x: 100, y: 100))
        #expect(!m.ownsPointer)
        _ = down(&m, target: .rackTile(index: 0, letter: "a"))
        #expect(m.ownsPointer)
    }
}
