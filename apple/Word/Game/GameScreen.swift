import SwiftUI
import WordBoard
import WordCore

/// The game screen, top to bottom: header and pile gauge, the board, the
/// word being built, the pile, and the four actions — one column with the
/// same margin all round and the same gap between every section.
struct GameScreen: View {
    /// The shared coordinate space every pointer event and frame reads —
    /// the port's stand-in for the web's client coordinates.
    nonisolated static let space = "game"

    /// Owned by the router, which decides what was dealt (a solo run, a
    /// restored save, a battle) before this screen appears.
    var model: GameModel
    /// The battle this board is in, if any: the placing, the standings, and
    /// the host's controls come from here.
    var battle: BattleSession?
    /// Out: home from a solo game, out of the battle from a battle.
    var onLeave: () -> Void = {}
    /// Deal a fresh solo game. The router owns it so the pace gets remembered.
    var onNewGame: ((SoloPace) -> Void)?

    @State private var camera = BoardCamera()
    @State private var machine = GestureMachine()
    @State private var holdTask: Task<Void, Never>?
    /// The fingers' current midpoint, sensed outside SwiftUI's gesture
    /// vocabulary (`BoardInputBridge`); nil when nothing is pinching.
    @State private var pinchMidpoint: CGPoint?
    @State private var clockNow = Date.now
    /// The column's inner width, which sizes the tiles: ten across, always.
    @State private var columnWidth: CGFloat = 358
    @FocusState private var gameFocused: Bool
    @Environment(\.snapshotRendering) private var snapshotRendering
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif

    private var tileSize: CGFloat { Spacing.tileSize(fitting: columnWidth) }

    var body: some View {
        ZStack {
            VStack(spacing: Spacing.gap) {
                VStack(spacing: Spacing.gap / 2) {
                    header
                    PileGaugeView(count: model.pileCount, tone: model.pileTone)
                }
                boardArea
                WordRowView(picks: model.pickList, tileSize: tileSize) { position in
                    model.removePick(at: position)
                    focusGame()
                }
                .allowsHitTesting(model.canAcceptInput)
                PileView(
                    letters: model.rack, picked: Set(model.picks), tileSize: tileSize
                ) { index in
                    model.togglePick(index)
                    focusGame()
                }
                .allowsHitTesting(model.canAcceptInput)
                actions
                    .allowsHitTesting(model.canAcceptInput)
            }
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.width
            } action: { width in
                columnWidth = width
            }
            .frame(maxWidth: Spacing.maxWidth)
            .padding(Spacing.margin)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if let splash = model.splash {
                SplashView(splash: splash, pace: model.pace) {
                    model.dismissSplash(at: .now)
                    focusGame()
                }
                .transition(.opacity)
            }

            if model.showSummary {
                endScreen
                    .transition(.opacity)
            }

            if model.isPaused {
                PauseView {
                    model.resume(at: .now)
                    focusGame()
                }
                .transition(.opacity)
            }
        }
        .coordinateSpace(name: Self.space)
        .background(Palette.bg.ignoresSafeArea())
        .focusable()
        .focused($gameFocused)
        .onKeyPress(phases: [.down, .repeat], action: handleKeyPress)
        .task {
            clockNow = .now
            await model.loadDictionary()
            focusGame()
        }
        .task(id: model.gameSerial) {
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .milliseconds(250))
                } catch {
                    return
                }
                let now = Date.now
                clockNow = now
                model.advanceClock(at: now)
            }
        }
        .task(id: model.splash) {
            // The resume card waits for the player: a restored game whose
            // clock started itself would charge them for being away.
            guard let splash = model.splash, splash != .resumed else { return }
            do {
                try await Task.sleep(for: .milliseconds(1_700))
            } catch {
                return
            }
            model.dismissSplash(at: .now)
            focusGame()
        }
        .task(id: model.boardClearReady) {
            guard model.boardClearReady else { return }
            do {
                try await Task.sleep(for: .milliseconds(900))
            } catch {
                return
            }
            model.claimBoardClear()
        }
        // Growth compensation must run before auto-fit sizes to the new
        // tiles: onChange order is declaration order.
        .onChange(of: model.bounds) { _, new in
            camera.boundsChanged(to: new)
        }
        .onChange(of: model.tileBounds) { _, box in
            camera.autoFit(box: box)
        }
        .onChange(of: model.gameSerial, initial: true) {
            camera.newGame(bounds: model.bounds, anchor: GameModel.startCell)
        }
        #if os(iOS)
        .onChange(of: sizeClass, initial: true) { _, sizeClass in
            camera.cellBase = sizeClass == .compact ? CELL_BASE_COMPACT : CELL_BASE_REGULAR
        }
        #endif
    }

    // MARK: Header

    private var header: some View {
        GameHeaderView(
            headline: headline,
            headlineLabel: headlineLabel,
            secondsToTiles: model.secondsToNextTiles(at: clockNow)
        ) {
            if model.isBattle {
                battleMenu
            } else {
                soloMenu
            }
        }
    }

    /// The score — or, in a battle, where this player stands.
    private var headline: String {
        if model.isBattle {
            return battle?.position.map(ordinal) ?? "—"
        }
        return "\(model.score)"
    }

    private var headlineLabel: String {
        if model.isBattle, let position = battle?.position {
            return "Standing \(ordinal(position))"
        }
        return model.isComplete ? "Final score \(model.score)" : "Score \(model.score)"
    }

    @ViewBuilder
    private var soloMenu: some View {
        if model.canPause {
            Button("Pause", action: pauseGame)
        }
        if model.isComplete {
            Button("Results") { model.setSummaryPresented(true) }
        }
        Button("New game") { startNewGame(pace: model.pace) }
        Section("Speed") {
            ForEach(PACE_OPTIONS, id: \.pace) { option in
                Button {
                    startNewGame(pace: option.pace)
                } label: {
                    if model.pace == option.pace {
                        Label(option.name, systemImage: "checkmark")
                    } else {
                        Text(option.name)
                    }
                }
            }
        }
        Divider()
        Button("Home", action: onLeave)
    }

    @ViewBuilder
    private var battleMenu: some View {
        if model.isComplete {
            Button("Results") { model.setSummaryPresented(true) }
        }
        if let battle, battle.isHost {
            if battle.canRestart {
                Button("Restart", action: battle.restart)
            }
            Button("Everyone to the lobby", action: battle.toLobby)
        }
        Divider()
        Button("Leave battle", action: onLeave)
    }

    // MARK: The board viewport

    private var boardArea: some View {
        // The board's rendered content is the size of the whole lattice —
        // far bigger than the screen — so it must never be a direct child of
        // the layout: SwiftUI would take that as the area's ideal size. An
        // overlay is laid out *inside* the size its parent already chose, so
        // a flexible transparent base decides how big the viewport is and
        // the board is drawn into it (and clipped).
        Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .topLeading) {
                let metrics = camera.metrics
                let origin = contentOrigin(
                    contentSize: metrics.contentSize, viewport: camera.viewport)
                BoardContentView(scene: scene)
                    .allowsHitTesting(false)
                    .offset(x: origin.x - camera.offset.x, y: origin.y - camera.offset.y)
            }
            // One transparent input plane sits above every board cell.
            .overlay {
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .pointerSurface(
                        target: boardTarget(at:), context: { machineContext }, dispatch: dispatch)
                    .simultaneousGesture(pinchGesture)
                    .allowsHitTesting(model.canAcceptInput)
            }
            // Laid out over the same rectangle as the input plane, so the
            // points it reports are already viewport coordinates.
            .overlay {
                if !snapshotRendering {
                    BoardInputBridge(
                        onMidpoint: { pinchMidpoint = $0 },
                        onScroll: { camera.pan(by: $0) },
                        isEnabled: model.canAcceptInput)
                }
            }
            .background(Palette.bg)
            .clipped()
            .onGeometryChange(for: BoardGeometryValues.self) { proxy in
                BoardGeometryValues(frame: proxy.frame(in: .named(Self.space)), size: proxy.size)
            } action: { values in
                camera.frame = values.frame
                camera.viewportChanged(to: values.size, tileBox: model.tileBounds)
            }
            .overlay(alignment: .top) {
                if let toast = model.toast {
                    ToastView(toast: toast) { serial in model.clearToast(serial: serial) }
                }
            }
    }

    private struct BoardGeometryValues: Equatable {
        var frame: CGRect
        var size: CGSize
    }

    private var scene: BoardScene {
        BoardScene(
            metrics: camera.metrics,
            tiles: model.board.entries.map { (key: $0.key, letter: $0.value) },
            preview: model.preview,
            wordsAt: model.wordsByCell.mapValues { $0.map(\.word) })
    }

    /// Placed words are permanent in every mode, and nothing is ever picked
    /// up off the board: the machine only needs taps and pans.
    private var machineContext: GestureMachine.Context {
        GestureMachine.Context(boardLocked: true, hasStagedPicks: false, externalDragActive: false)
    }

    /// The press-time hit-test, as coordinate math.
    private func boardTarget(at point: CGPoint) -> GestureMachine.DownTarget? {
        guard let cell = camera.cell(atGame: point) else { return .boardEmpty(cell: nil) }
        if let letter = model.board[keyOf(cell.row, cell.col)] {
            return .boardTile(cell: cell, letter: letter)
        }
        return .boardEmpty(cell: cell)
    }

    /// SwiftUI recognizes the pinch and reports its scale; the live midpoint
    /// comes from `BoardInputBridge`, because `MagnifyGesture` only ever
    /// offers the anchor it started at.
    private var pinchGesture: some Gesture {
        MagnifyGesture(minimumScaleDelta: 0.02)
            .onChanged { value in
                if !camera.pinchActive {
                    dispatch(.pinchBegan)
                    camera.beginPinch(startAnchor: value.startAnchor, midpoint: pinchMidpoint)
                }
                camera.updatePinch(scale: value.magnification, midpoint: pinchMidpoint)
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
            case let .tapBoardTile(cell):
                model.selectTile(keyOf(cell.row, cell.col))
                focusGame()
            case .beginPan:
                break
            case let .panBy(delta):
                camera.pan(by: delta)
            case let .endPan(velocity):
                camera.endPan(velocity: velocity)
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
            case .tapBoardCell, .doubleTapBoardTile, .tapRackTile,
                .beginDrag, .dragMoved, .endDrag,
                .beginPreviewDrag, .previewDragMoved, .endPreviewDrag, .cancelPreviewDrag:
                // Nothing lands by tapping empty board, nothing is dragged,
                // and the pile has no pointer surface: none of these can
                // happen with the context above, and none mean anything now.
                break
            }
        }
    }

    // MARK: The actions

    private var actions: some View {
        HStack(spacing: Spacing.tileGap) {
            ActionButton(
                systemImage: "trash", label: "Clear the word",
                disabled: !model.canClearWord
            ) {
                model.clearWord()
                focusGame()
            }
            ActionButton(
                systemImage: "repeat", label: "Shuffle the pile",
                disabled: !model.canShuffle
            ) {
                model.shufflePile()
                focusGame()
            }
            if model.isFirstWord {
                // The opener is the one word placed by fiat: confirm takes the
                // gap button's place until it's down.
                ActionButton(
                    systemImage: "checkmark", label: "Place your first word",
                    accent: true, disabled: !model.canConfirm
                ) {
                    model.confirmFirstWord()
                    focusGame()
                }
            } else {
                ActionButton(systemImage: "square.dashed", label: "Add a gap") {
                    model.addGap()
                    focusGame()
                }
            }
            ActionButton(
                systemImage: "delete.left", label: "Remove the last letter",
                disabled: !model.canBackspace
            ) {
                _ = model.handle(.backspace)
                focusGame()
            }
        }
    }

    // MARK: The end

    private var endScreen: some View {
        GameEndView(
            score: model.score,
            words: model.finalWords,
            placing: model.isBattle ? battle?.position.map(ordinal) : nil,
            standings: battleStandings,
            note: endNote,
            restart: endRestart,
            onSeeGame: { model.setSummaryPresented(false) },
            onLobby: battle?.isHost == true ? { battle?.toLobby() } : nil,
            leaveLabel: model.isBattle ? "LEAVE" : "HOME",
            onLeave: onLeave)
    }

    private var endRestart: (() -> Void)? {
        if let battle {
            return battle.canRestart ? { battle.restart() } : nil
        }
        return { startNewGame(pace: model.pace) }
    }

    private var endNote: String? {
        guard let battle else { return nil }
        if battle.isFinished {
            return battle.isHost ? nil : "Waiting for the host to restart or reopen the lobby."
        }
        let standing = battle.contestants.filter { $0.outOrder == nil && $0.id != battle.selfID }
        return "You’re out — \(standing.count) still standing."
    }

    /// The field, in the order the results read: whoever is still standing
    /// first, then everyone else in reverse order of falling.
    private var battleStandings: [GameEndView.Standing] {
        guard let battle, let state = battle.state else { return [] }
        let finished = state.phase == .finished
        return battle.standings.map { row in
            let player = row.player
            let note: String
            if finished {
                note = player.id == state.winnerId ? "won" : (player.left ? "left" : "buried")
            } else if player.buried || player.left {
                note = player.left ? "left" : "out"
            } else {
                note = "\(player.tiles) tiles"
            }
            return GameEndView.Standing(
                id: player.id, rank: finished ? row.rank : nil, name: player.name,
                isSelf: player.id == battle.selfID, note: note)
        }
    }

    // MARK: Hardware keyboard (iPad)

    private func handleKeyPress(_ press: KeyPress) -> KeyPress.Result {
        if model.isPaused, press.key == .escape {
            model.resume(at: .now)
            focusGame()
            return .handled
        }
        guard model.canAcceptInput else { return .ignored }
        if !press.modifiers.isDisjoint(with: [.command, .control, .option]) {
            return .ignored
        }

        let command: GameCommand?
        switch press.key {
        case .space: command = .gap
        case .delete: command = .backspace
        case .escape: command = .escape
        case .return: command = .confirm
        default:
            command = press.characters.count == 1 ? .letter(press.characters) : nil
        }

        guard let command else { return .ignored }
        return model.handle(command) ? .handled : .ignored
    }

    private func focusGame() {
        gameFocused = true
    }

    private func pauseGame() {
        holdTask?.cancel()
        holdTask = nil
        machine = GestureMachine()
        model.pause(at: .now)
    }

    private func startNewGame(pace: SoloPace) {
        let now = Date.now
        clockNow = now
        holdTask?.cancel()
        holdTask = nil
        machine = GestureMachine()
        if let onNewGame {
            onNewGame(pace)
        } else {
            model.newGame(pace: pace, now: now)
        }
    }
}

#Preview {
    GameScreen(model: {
        let model = GameModel()
        model.newGame(seed: "preview")
        return model
    }())
    .preferredColorScheme(.dark)
}
