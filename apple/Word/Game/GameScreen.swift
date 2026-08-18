import SwiftUI
import WordBoard
import WordCore

/// The phase-2a game screen: the board in its pan/zoom viewport, the pile,
/// and a lean word bar — all pointer input funneled through ONE gesture
/// machine, the way the web funnels everything through its window-level
/// pointer pipeline (ui.md §8.1). Header chrome, clocks, scoring UI, undo and
/// the rest of solo arrive in phase 2b.
struct GameScreen: View {
    /// The shared coordinate space every pointer event and frame reads —
    /// the port's stand-in for the web's client coordinates.
    nonisolated static let space = "game"

    @State private var model = GameModel()
    @State private var camera = BoardCamera()
    @State private var machine = GestureMachine()
    @State private var holdTask: Task<Void, Never>?
    @State private var rackFrame: CGRect = .zero
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                header
                boardArea
                wordBar
                RackView(
                    letters: model.rack,
                    hiddenIndex: model.hiddenRackIndex,
                    picks: model.picks,
                    pointerEvent: dispatch,
                    downTarget: { index, letter in .rackTile(index: index, letter: letter) },
                    onShuffle: { model.shufflePile() }
                )
                .onGeometryChange(for: CGRect.self) { proxy in
                    proxy.frame(in: .named(Self.space))
                } action: { frame in
                    rackFrame = frame
                }
            }

            // The drag ghost rides above everything (web z=1000).
            if let drag = model.drag {
                GhostTileView(letter: drag.letter)
                    .position(drag.location)
            }
        }
        .coordinateSpace(name: Self.space)
        .background(Ink.bg)
        .task {
            model.newGame()
            await model.loadDictionary()
        }
        // Growth compensation must run before auto-fit sizes to the new
        // tiles: onChange order is declaration order.
        .onChange(of: model.bounds) { _, new in
            camera.boundsChanged(to: new)
        }
        .onChange(of: model.tileBounds) { _, box in
            camera.autoFit(box: box)
        }
        .onChange(of: model.gameSerial) {
            camera.newGame(bounds: model.bounds)
        }
        #if os(iOS)
        .onChange(of: sizeClass, initial: true) { _, sizeClass in
            camera.cellBase = sizeClass == .compact ? CELL_BASE_COMPACT : CELL_BASE_REGULAR
        }
        #endif
    }

    // MARK: Chrome (placeholder until phase 2b's real header)

    private var header: some View {
        HStack {
            Text("Word")
                .font(.title3.bold())
                .foregroundStyle(Ink.ink)
            Spacer()
            Text("Score \(scoreBoard(model.validation, tilesLeft: model.rack.count).total)")
                .font(.headline.monospacedDigit())
                .foregroundStyle(Ink.ink)
            Spacer()
            Button("New deal") { model.newGame() }
                .buttonStyle(.bordered)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Ink.surface)
    }

    // MARK: The board viewport

    private var boardArea: some View {
        ZStack(alignment: .topLeading) {
            let metrics = camera.metrics
            let origin = contentOrigin(contentSize: metrics.contentSize, viewport: camera.viewport)
            BoardContentView(scene: scene)
                .allowsHitTesting(false)
                .offset(x: origin.x - camera.offset.x, y: origin.y - camera.offset.y)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Ink.boardBg)
        .clipped()
        .contentShape(Rectangle())
        .pointerSurface(target: boardTarget(at:), context: { machineContext }, dispatch: dispatch)
        .simultaneousGesture(pinchGesture)
        .onContinuousHover(coordinateSpace: .named(Self.space)) { phase in
            // Mouse/trackpad aims the preview by hovering (ui.md §8.10);
            // the model gates it to letters-staged-and-nothing-dragged.
            switch phase {
            case let .active(point):
                model.setHover(camera.cell(atGame: point).map { keyOf($0.row, $0.col) })
            case .ended:
                model.setHover(nil)
            }
        }
        .onGeometryChange(for: BoardGeometryValues.self) { proxy in
            BoardGeometryValues(frame: proxy.frame(in: .named(Self.space)), size: proxy.size)
        } action: { values in
            camera.frame = values.frame
            camera.viewportChanged(to: values.size, tileBox: model.tileBounds)
        }
        .overlay(alignment: .top) { toastView }
    }

    private struct BoardGeometryValues: Equatable {
        var frame: CGRect
        var size: CGSize
    }

    private var scene: BoardScene {
        BoardScene(
            metrics: camera.metrics,
            tiles: model.board.entries.map { (key: $0.key, letter: $0.value) },
            feedback: model.cellFeedback,
            hiddenKey: model.hiddenBoardKey,
            preview: model.preview,
            previewGaps: model.previewGaps,
            cursorKey: model.cursorKey,
            selectedKey: model.selectedKey,
            rotate: rotateControl,
            locked: model.boardLocked)
    }

    private var rotateControl: (key: CellKey, dir: Direction)? {
        guard model.showRotate, case let .place(anchor, dir, _) = model.interaction else {
            return nil
        }
        return (anchor, dir)
    }

    private var machineContext: GestureMachine.Context {
        GestureMachine.Context(
            boardLocked: model.boardLocked,
            hasStagedPicks: !model.picks.isEmpty,
            externalDragActive: false)
    }

    /// The press-time hit-test — the port of `elementFromPoint` against
    /// `[data-cell]`, as coordinate math.
    private func boardTarget(at point: CGPoint) -> GestureMachine.DownTarget? {
        // The rotate control claims its press before the machine sees it
        // (the web's stopPropagation, Grid.tsx:149–153).
        if let rotate = rotateControl {
            let rect = camera.gameRect(
                ofContent: BoardContentView.rotateRect(for: rotate.key, metrics: camera.metrics))
            if rect.contains(point) {
                model.rotateDirection()
                return nil
            }
        }
        guard let cell = camera.cell(atGame: point) else { return .boardEmpty(cell: nil) }
        if let letter = model.board[keyOf(cell.row, cell.col)] {
            return .boardTile(cell: cell, letter: letter)
        }
        return .boardEmpty(cell: cell)
    }

    private var pinchGesture: some Gesture {
        MagnifyGesture(minimumScaleDelta: 0.02)
            .onChanged { value in
                if !camera.pinchActive {
                    dispatch(.pinchBegan)
                    camera.beginPinch(startAnchor: value.startAnchor)
                }
                camera.updatePinch(scale: value.magnification)
            }
            .onEnded { _ in
                camera.endPinch()
            }
    }

    // MARK: The unified pipeline

    private func dispatch(_ event: GestureMachine.Event) {
        apply(machine.handle(event))
    }

    private func apply(_ effects: [GestureMachine.Effect]) {
        for effect in effects {
            switch effect {
            case let .beginDrag(source, at):
                model.beginDrag(source, at: at)
            case let .dragMoved(point):
                model.dragMoved(to: point)
            case let .endDrag(drop):
                if let drop {
                    model.applyDrop(dropRegion(at: drop))
                } else {
                    model.endDrag()
                }
            case let .tapRackTile(index):
                model.togglePick(index)
            case let .tapBoardTile(cell):
                model.selectTile(keyOf(cell.row, cell.col))
            case let .doubleTapBoardTile(cell):
                model.doubleTapBoardTile(keyOf(cell.row, cell.col))
            case let .tapBoardCell(cell):
                model.cellClick(keyOf(cell.row, cell.col))
            case let .scheduleHold(id):
                holdTask?.cancel()
                holdTask = Task {
                    try? await Task.sleep(for: .seconds(HOLD_DRAG_SECONDS))
                    guard !Task.isCancelled else { return }
                    apply(machine.handle(.holdFired(id: id)))
                }
            case .cancelHold:
                holdTask?.cancel()
                holdTask = nil
            case .beginPan:
                break
            case let .panBy(delta):
                camera.pan(by: delta)
            case let .endPan(velocity):
                camera.endPan(velocity: velocity)
            case let .beginPreviewDrag(at):
                model.beginPreviewDrag()
                hover(at: at)
            case let .previewDragMoved(point):
                hover(at: point)
            case let .endPreviewDrag(point):
                // Anchor the word under the lifted finger — ready to
                // confirm, not committed (ui.md §3.9).
                if let cell = camera.cell(atGame: point) {
                    model.cellClick(keyOf(cell.row, cell.col))
                }
            case .cancelPreviewDrag:
                break
            }
        }
    }

    /// Where a ghost landed — the web's `elementFromPoint` + `[data-rack]`
    /// contract: anywhere on the pile (shuffle button included) returns the
    /// tile (Rack.tsx:29).
    private func dropRegion(at point: CGPoint) -> GameModel.DropRegion {
        if rackFrame.contains(point) { return .rack }
        if let cell = camera.cell(atGame: point) { return .cell(cell) }
        return .none
    }

    /// The preview-drag hover: only a real cell updates it, so the ghost
    /// letters hold their last spot at the board's edge (App.tsx:2621–2627).
    private func hover(at point: CGPoint) {
        if let cell = camera.cell(atGame: point) {
            model.setHover(keyOf(cell.row, cell.col))
        }
    }

    // MARK: Word bar (lean 2a version of WordBar.tsx + PileTools.tsx)

    private var wordBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 4) {
                ForEach(Array(model.pickList.enumerated()), id: \.offset) { position, pick in
                    Button {
                        model.removePick(at: position)
                    } label: {
                        Text(pick.letter?.uppercased() ?? "␣")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(verdictInk)
                            .frame(width: 26, height: 26)
                            .background(RoundedRectangle(cornerRadius: 5).fill(Ink.surface))
                            .overlay(
                                RoundedRectangle(cornerRadius: 5)
                                    .strokeBorder(verdictInk, lineWidth: 1.5))
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(minHeight: 34)

            Spacer()

            if model.canRotateAnchor {
                barButton(
                    model.interactionDir == .across ? "⬇" : "➜",
                    label: "Change direction"
                ) {
                    model.rotateDirection()
                }
            }

            barButton("✓", label: "Confirm word", disabled: !model.canConfirm) {
                if let target = model.target {
                    model.commit(target.key, target.dir)
                }
            }
            barButton("✗", label: "Clear word", disabled: !model.canCancel) {
                model.clearFocus()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(Ink.surface)
    }

    /// The bar's live verdict tint: color-only, like the web (WordBar.tsx:16).
    private var verdictInk: Color {
        switch model.verdictOK {
        case true: return Ink.okInk
        case false: return Ink.badInk
        default: return Ink.ink
        }
    }

    private func barButton(
        _ glyph: String, label: String, disabled: Bool = false, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(glyph)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Ink.ink)
                .frame(width: 40, height: 34)
                .background(RoundedRectangle(cornerRadius: 8).fill(Ink.surface))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Ink.ink, lineWidth: 2))
                .opacity(disabled ? 0.35 : 1)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .accessibilityLabel(label)
    }

    // MARK: Toast (single slot, keyed by serial — App.tsx:415, 1746–1750)

    @ViewBuilder
    private var toastView: some View {
        if let toast = model.toast {
            Text(toast.text)
                .font(.callout.bold())
                .foregroundStyle(Ink.ink)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Capsule().fill(Ink.surface))
                .overlay(Capsule().strokeBorder(Ink.ink, lineWidth: 2))
                .padding(.top, 10)
                .transition(.opacity)
                .task(id: toast.serial) {
                    try? await Task.sleep(for: .seconds(2.5))
                    model.clearToast(serial: toast.serial)
                }
                .allowsHitTesting(false)
        }
    }
}

#Preview {
    GameScreen()
}
