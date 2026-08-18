import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
import WordCore

/// The board's unified pointer pipeline as a pure state machine: pointer
/// events in, intents out. Ported from the web game's window-level pointer
/// handling (`App.tsx` — startDrag/dropAt 2418–2533, board-tile double-press
/// 2551–2600, hold-to-drag preview 2607–2711) where tap-vs-drag is decided
/// *after the fact* by a 6px slop and every drop is hit-tested in screen
/// coordinates.
///
/// The machine is deliberately blind to views, timers, and hit-testing:
///
///  - the caller says what was under the pointer at press time (`DownTarget`)
///    and hit-tests drop locations itself when a `.endDrag(drop:)` comes out;
///  - time arrives as event timestamps, and the hold timer is the caller's:
///    the machine emits `.scheduleHold`/`.cancelHold` and the caller feeds
///    back `.holdFired` — so a test can play any interleaving without waiting.
///
/// Behaviors under test (the traps the port notes call out):
///
///  - tap vs drag by slop: travel under `TAP_SLOP` on both axes is a tap;
///  - a completed drag is never also a tap (the web's `swallowNextClick`
///    intent, without the mechanism);
///  - tiles never pan the board, empty cells do — the down target decides,
///    not gesture priorities;
///  - double-press on a board tile is manual (same cell within 350ms), and
///    the first press still starts its drag immediately — no added latency;
///  - hold-to-drag preview: 300ms hold on empty board, touch/pen only, only
///    with letters staged; movement past slop before the timer cancels into
///    a pan; release aims a cell without committing;
///  - a locked (battle) board keeps taps but loses tile drags, selection and
///    double-press;
///  - every gesture is keyed to the pointer that started it — a second
///    finger can't hijack it — and a pinch cancels pans, not tile drags.
public struct GestureMachine {

    // MARK: Vocabulary

    public enum PointerKind: Equatable {
        case touch
        case pen
        case mouse
    }

    /// What sat under the pointer when it came down — the caller's hit-test.
    public enum DownTarget: Equatable {
        case rackTile(index: Int, letter: String)
        case boardTile(cell: Cell, letter: String)
        /// Board background: an empty cell, or the gutter around the grid.
        case boardEmpty(cell: Cell?)
    }

    /// What a ghost tile being dragged came from (App.tsx `DragSource`).
    public enum DragSource: Equatable {
        case rack(index: Int, letter: String)
        case board(cell: Cell, letter: String)
    }

    /// Facts the machine can't know on its own, sampled at press time.
    public struct Context: Equatable {
        /// Battle: placed tiles are permanent (no drag, no select, no
        /// double-press return).
        public var boardLocked: Bool
        /// Letters are staged for the current word — the hold-to-drag
        /// preview only exists while there's a word to aim.
        public var hasStagedPicks: Bool
        /// An externally run drag (the word-controls grab) owns the pointer;
        /// board presses must stay inert under it.
        public var externalDragActive: Bool

        public init(
            boardLocked: Bool = false,
            hasStagedPicks: Bool = false,
            externalDragActive: Bool = false
        ) {
            self.boardLocked = boardLocked
            self.hasStagedPicks = hasStagedPicks
            self.externalDragActive = externalDragActive
        }
    }

    public enum Event: Equatable {
        case down(
            id: Int, kind: PointerKind, location: CGPoint, target: DownTarget,
            time: Double, context: Context)
        case move(id: Int, location: CGPoint, time: Double)
        case up(id: Int, location: CGPoint, time: Double, velocity: CGSize)
        case cancel(id: Int)
        /// The hold timer the caller was asked to schedule has fired.
        case holdFired(id: Int)
        /// A second finger started a pinch: pans and presses yield to it.
        case pinchBegan
    }

    /// What the app should do — the only way the machine speaks.
    public enum Effect: Equatable {
        /// Lift a tile: show its ghost at the pointer, hide the source tile.
        /// Emitted at press time, exactly like the web (the tap/drag call is
        /// made later, at release).
        case beginDrag(source: DragSource, at: CGPoint)
        case dragMoved(CGPoint)
        /// Put the ghost down. A location means a real drag ended there —
        /// hit-test it and apply the drop; nil means the gesture resolved to
        /// something else (a tap, a cancel) and only the ghost goes away.
        case endDrag(drop: CGPoint?)
        /// Tap on a rack tile: claim or release it for the current word.
        case tapRackTile(index: Int)
        /// Tap on a board tile: `selectTile` (aim a staged gap through it,
        /// or select it for deletion + anchor).
        case tapBoardTile(Cell)
        /// Two presses on the same tile within the window: rotate the word
        /// about its first letter, or return the letter to the pile.
        case doubleTapBoardTile(Cell)
        /// Tap on an empty cell: anchor the staged word there (`onCellClick`).
        case tapBoardCell(Cell)
        /// Start (or abandon) the hold-to-drag countdown for this press.
        case scheduleHold(id: Int)
        case cancelHold
        /// The board is being panned by an empty-cell drag.
        case beginPan
        case panBy(CGSize)
        case endPan(velocity: CGSize)
        /// The hold fired: the staged word's preview follows the finger from
        /// here (a held anchor reverts to spell). Scrolling must stay off
        /// while this runs — the machine simply never pans during it.
        case beginPreviewDrag(at: CGPoint)
        case previewDragMoved(CGPoint)
        /// Fingers up: aim the preview at the cell under this point —
        /// anchored, not committed.
        case endPreviewDrag(at: CGPoint)
        case cancelPreviewDrag
    }

    // MARK: State

    enum State: Equatable {
        case idle
        /// A press on a tile: its ghost is up; slop decides tap or drag at
        /// release.
        case tileDrag(id: Int, start: CGPoint, source: DragSource)
        /// A press on empty board: could still become a tap, a pan, or (if
        /// armed) the hold preview.
        case emptyPress(id: Int, start: CGPoint, cell: Cell?, holdArmed: Bool)
        case panning(id: Int, last: CGPoint)
        case previewDrag(id: Int)
        /// The press was fully handled at down (double-press, locked-board
        /// tap); everything until its release is noise.
        case spent(id: Int)
    }

    private(set) var state: State = .idle

    /// The last unlocked board-tile press, for manual double-press detection
    /// (App.tsx:2554). Recorded on every such press, cleared when a double
    /// fires — exactly the web's bookkeeping.
    private var lastBoardTilePress: (cell: Cell, time: Double)?

    public init() {}

    /// True while a gesture that must veto board scrolling is running.
    public var ownsPointer: Bool {
        switch state {
        case .idle, .emptyPress: return false
        default: return true
        }
    }

    // MARK: The machine

    public mutating func handle(_ event: Event) -> [Effect] {
        switch event {
        case let .down(id, kind, location, target, time, context):
            return handleDown(
                id: id, kind: kind, location: location, target: target,
                time: time, context: context)
        case let .move(id, location, _):
            return handleMove(id: id, location: location)
        case let .up(id, location, _, velocity):
            return handleUp(id: id, location: location, velocity: velocity)
        case let .cancel(id):
            return handleCancel(id: id)
        case let .holdFired(id):
            return handleHoldFired(id: id)
        case .pinchBegan:
            return handlePinchBegan()
        }
    }

    private mutating func handleDown(
        id: Int, kind: PointerKind, location: CGPoint, target: DownTarget,
        time: Double, context: Context
    ) -> [Effect] {
        // One gesture at a time: whoever's mid-gesture keeps the floor, and
        // an external drag (word grab) owns the pointer outright.
        guard state == .idle, !context.externalDragActive else { return [] }

        switch target {
        case let .rackTile(index, letter):
            state = .tileDrag(id: id, start: location, source: .rack(index: index, letter: letter))
            return [.beginDrag(source: .rack(index: index, letter: letter), at: location)]

        case let .boardTile(cell, letter):
            // A locked board's tiles are permanent: no dragging, no
            // double-tap return. The tap still lands — and it lands at press
            // time, like the web (App.tsx:2561–2566).
            if context.boardLocked {
                state = .spent(id: id)
                return [.tapBoardTile(cell)]
            }
            if let last = lastBoardTilePress, last.cell == cell,
                time - last.time < DOUBLE_PRESS_SECONDS
            {
                lastBoardTilePress = nil
                state = .spent(id: id)
                return [.doubleTapBoardTile(cell)]
            }
            lastBoardTilePress = (cell, time)
            state = .tileDrag(id: id, start: location, source: .board(cell: cell, letter: letter))
            return [.beginDrag(source: .board(cell: cell, letter: letter), at: location)]

        case let .boardEmpty(cell):
            // The hold is a touch (and pen) affordance — mouse users aim by
            // hovering — and only exists while a word is staged.
            let holdArmed = kind != .mouse && context.hasStagedPicks
            state = .emptyPress(id: id, start: location, cell: cell, holdArmed: holdArmed)
            return holdArmed ? [.scheduleHold(id: id)] : []
        }
    }

    private mutating func handleMove(id: Int, location: CGPoint) -> [Effect] {
        switch state {
        case let .tileDrag(dragID, _, _) where dragID == id:
            return [.dragMoved(location)]

        case let .emptyPress(pressID, start, _, holdArmed) where pressID == id:
            // Real movement before the hold fires means a pan.
            guard passesSlop(from: start, to: location) else { return [] }
            state = .panning(id: id, last: location)
            var effects: [Effect] = holdArmed ? [.cancelHold] : []
            effects.append(.beginPan)
            effects.append(
                .panBy(CGSize(width: location.x - start.x, height: location.y - start.y)))
            return effects

        case let .panning(panID, last) where panID == id:
            state = .panning(id: id, last: location)
            return [.panBy(CGSize(width: location.x - last.x, height: location.y - last.y))]

        case let .previewDrag(previewID) where previewID == id:
            return [.previewDragMoved(location)]

        default:
            return []
        }
    }

    private mutating func handleUp(id: Int, location: CGPoint, velocity: CGSize) -> [Effect] {
        switch state {
        case let .tileDrag(dragID, start, source) where dragID == id:
            state = .idle
            // A tap picks a tile out rather than moving it: in the pile it
            // claims the letter, on the board it selects it. A real drag
            // drops — and is *only* a drop, never also a tap.
            if passesSlop(from: start, to: location) {
                return [.endDrag(drop: location)]
            }
            switch source {
            case let .rack(index, _):
                return [.endDrag(drop: nil), .tapRackTile(index: index)]
            case let .board(cell, _):
                return [.endDrag(drop: nil), .tapBoardTile(cell)]
            }

        case let .emptyPress(pressID, _, cell, holdArmed) where pressID == id:
            state = .idle
            var effects: [Effect] = holdArmed ? [.cancelHold] : []
            if let cell { effects.append(.tapBoardCell(cell)) }
            return effects

        case let .panning(panID, _) where panID == id:
            state = .idle
            return [.endPan(velocity: velocity)]

        case let .previewDrag(previewID) where previewID == id:
            state = .idle
            return [.endPreviewDrag(at: location)]

        case let .spent(spentID) where spentID == id:
            state = .idle
            return []

        default:
            return []
        }
    }

    private mutating func handleCancel(id: Int) -> [Effect] {
        switch state {
        case let .tileDrag(dragID, _, _) where dragID == id:
            state = .idle
            return [.endDrag(drop: nil)]
        case let .emptyPress(pressID, _, _, holdArmed) where pressID == id:
            state = .idle
            return holdArmed ? [.cancelHold] : []
        case let .panning(panID, _) where panID == id:
            state = .idle
            return [.endPan(velocity: .zero)]
        case let .previewDrag(previewID) where previewID == id:
            state = .idle
            return [.cancelPreviewDrag]
        case let .spent(spentID) where spentID == id:
            state = .idle
            return []
        default:
            return []
        }
    }

    private mutating func handleHoldFired(id: Int) -> [Effect] {
        // Only an armed press that hasn't moved or resolved can become the
        // preview drag; anything else means the timer raced a state change
        // and is stale.
        guard case let .emptyPress(pressID, start, _, holdArmed) = state,
            pressID == id, holdArmed
        else { return [] }
        state = .previewDrag(id: id)
        return [.beginPreviewDrag(at: start)]
    }

    private mutating func handlePinchBegan() -> [Effect] {
        // Two fingers own the board now. Presses and pans yield; a tile drag
        // yields too (its pointer is one of the pinch's fingers as far as
        // the player is concerned — the web's separate channels made this
        // ambiguous; here it's resolved deliberately).
        switch state {
        case .idle:
            return []
        case .tileDrag:
            state = .idle
            return [.endDrag(drop: nil)]
        case let .emptyPress(_, _, _, holdArmed):
            state = .idle
            return holdArmed ? [.cancelHold] : []
        case .panning:
            state = .idle
            return [.endPan(velocity: .zero)]
        case .previewDrag:
            state = .idle
            return [.cancelPreviewDrag]
        case .spent:
            state = .idle
            return []
        }
    }

    /// The web's tap test, inverted: `abs(dx) < slop && abs(dy) < slop` is a
    /// tap (App.tsx:2443), so travel at or past the slop on either axis makes
    /// the gesture real.
    private func passesSlop(from start: CGPoint, to point: CGPoint) -> Bool {
        abs(point.x - start.x) >= TAP_SLOP || abs(point.y - start.y) >= TAP_SLOP
    }
}
