import SwiftUI
import WordBoard
import WordCore

/// The solo game screen: phase 2a's pan/zoom board and unified pointer layer,
/// plus phase 2b's editing, scoring and session lifecycle.
struct GameScreen: View {
    /// The shared coordinate space every pointer event and frame reads —
    /// the port's stand-in for the web's client coordinates.
    nonisolated static let space = "game"

    /// Owned by the router, which decides what was dealt (a solo run, a
    /// restored save, the tutorial) before this screen appears.
    var model: GameModel
    /// Back out to the home screen — also where a finished tutorial leads.
    var onLeave: () -> Void = {}
    /// Raise the settings page over the game (the router owns it, so one page
    /// serves both home and game).
    var onShowSettings: () -> Void = {}
    /// The streak this game landed on, read back after it was recorded.
    var dailyStreak = 0

    @State private var camera = BoardCamera()
    @State private var machine = GestureMachine()
    @State private var holdTask: Task<Void, Never>?
    /// The fingers' current midpoint, sensed outside SwiftUI's gesture
    /// vocabulary (`BoardInputBridge`); nil when nothing is pinching.
    @State private var pinchMidpoint: CGPoint?
    @State private var rackFrame: CGRect = .zero
    @State private var clockNow = Date.now
    @FocusState private var gameFocused: Bool
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif

    /// A lifted tile keeps the size it had in the pile, which a phone shrinks.
    private var ghostTileSize: Double {
        #if os(iOS)
        RackView.tileSize(for: sizeClass)
        #else
        RackView.tileSize(for: .regular)
        #endif
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                header
                if let progress = model.tutorialProgress, !model.tutorialFinished {
                    TutorialBanner(step: progress.step)
                }
                boardArea
                // A finished lesson hands its whole working area to the way
                // out: there is nothing left to type or place.
                if model.tutorialFinished {
                    TutorialFinishBand(onFinish: onLeave)
                } else {
                    wordBar
                    RackView(
                        letters: model.rack,
                        hiddenIndex: model.hiddenRackIndex,
                        picks: model.picks,
                        pointerEvent: dispatch,
                        downTarget: { index, letter in .rackTile(index: index, letter: letter) },
                        onShuffle: {
                            model.shufflePile()
                            focusGame()
                        }
                    )
                    .onGeometryChange(for: CGRect.self) { proxy in
                        proxy.frame(in: .named(Self.space))
                    } action: { frame in
                        rackFrame = frame
                    }
                    .allowsHitTesting(model.canAcceptInput)
                }
            }

            // The drag ghost rides above everything (web z=1000).
            if let drag = model.drag {
                GhostTileView(letter: drag.letter, size: ghostTileSize)
                    .position(drag.location)
            }
            if let wordDrag = model.wordDrag {
                WordGhostView(drag: wordDrag, cellSize: camera.metrics.cellSize)
            }

            if let splash = model.splash {
                SoloSplashView(splash: splash, pace: model.pace) {
                    model.dismissSplash(at: .now)
                    focusGame()
                }
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }

            if model.showSummary {
                SoloSummaryView(
                    words: model.finalWords,
                    score: model.score,
                    onPlayAgain: startNewGame,
                    onSeeBoard: { model.setSummaryPresented(false) },
                    onReturnHome: onLeave,
                    daily: dailySummary)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }

            if model.isPaused {
                SoloPauseView(pace: model.pace) {
                    model.resume(at: .now)
                    focusGame()
                }
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .coordinateSpace(name: Self.space)
        .background(Ink.bg)
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
        .onChange(of: model.gameSerial) {
            camera.newGame(bounds: model.bounds)
        }
        #if os(iOS)
        .onChange(of: sizeClass, initial: true) { _, sizeClass in
            camera.cellBase = sizeClass == .compact ? CELL_BASE_COMPACT : CELL_BASE_REGULAR
        }
        #endif
    }

    // MARK: Solo scoreboard

    @ViewBuilder
    private var header: some View {
        if let progress = model.tutorialProgress {
            TutorialHeaderView(
                step: progress.step,
                of: progress.of,
                showsSkip: !model.tutorialFinished,
                onSkip: {
                    model.skipTutorialStep()
                    focusGame()
                },
                onLeave: onLeave)
        } else {
            soloHeader
        }
    }

    private var soloHeader: some View {
        SoloHeaderView(
            score: model.score,
            complete: model.isComplete,
            seconds: model.remainingSeconds(at: clockNow),
            timerLabel: model.phase == .drip ? "Next tiles" : "Time",
            looseTiles: model.showsLooseGauge ? model.looseTiles : nil,
            tilesLeft: model.showsTilesLeft ? model.rack.count : nil,
            gaugeTone: model.gaugeTone,
            bonusEarned: model.boardScore.bonusEarned,
            canPause: model.canPause,
            onPause: pauseGame,
            onNewDeal: startNewGame,
            onShowSummary: { model.setSummaryPresented(true) },
            pace: model.pace,
            onChoosePace: startNewGame(pace:),
            onShowSettings: onShowSettings,
            onReturnHome: onLeave,
            onFinish: model.canFinishDaily ? { model.finishDaily() } : nil,
            allowsReplay: !model.isDaily)
    }

    // MARK: The board viewport

    private var boardArea: some View {
        // The board's rendered content is the size of the whole lattice —
        // 1,400pt-plus square at default zoom — so it must never be a direct
        // child of the layout: SwiftUI would take that as the area's ideal
        // size, push it up as the window's minimum, and shove the pile off the
        // bottom of the screen. An overlay is laid out *inside* the size its
        // parent already chose, so a flexible transparent base decides how big
        // the viewport is and the board is drawn into it (and clipped).
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
            // One transparent input plane sits above every board cell and
            // below popovers. Keeping the word controls outside this plane is
            // what lets their external drag own its pointer from press time.
            .overlay {
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .pointerSurface(
                        target: boardTarget(at:), context: { machineContext }, dispatch: dispatch)
                    .simultaneousGesture(pinchGesture)
                    .onContinuousHover(coordinateSpace: .named(Self.space)) { phase in
                        // Mouse/trackpad aims the preview by hovering (ui.md §8.10);
                        // the model gates it to letters-staged-and-nothing-dragged.
                        switch phase {
                        case let .active(point):
                            model.setHover(
                                camera.cell(atGame: point).map { keyOf($0.row, $0.col) })
                        case .ended:
                            model.setHover(nil)
                        }
                    }
                    .allowsHitTesting(model.canAcceptInput)
            }
            // Laid out over the same rectangle as the input plane, so the
            // points it reports are already viewport coordinates.
            .overlay {
                BoardInputBridge(
                    onMidpoint: { pinchMidpoint = $0 },
                    onScroll: { camera.pan(by: $0) },
                    isEnabled: model.canAcceptInput)
            }
            .overlay(alignment: .topLeading) { wordControls }
            .background(Ink.boardBg)
            .clipped()
        .onGeometryChange(for: BoardGeometryValues.self) { proxy in
            BoardGeometryValues(frame: proxy.frame(in: .named(Self.space)), size: proxy.size)
        } action: { values in
            camera.frame = values.frame
            camera.viewportChanged(to: values.size, tileBox: model.tileBounds)
        }
        .overlay(alignment: .top) { toastView }
        .overlay { boardAlarm }
    }

    @ViewBuilder
    private var boardAlarm: some View {
        if model.showsLooseGauge, model.gaugeTone != .ok {
            let urgent = model.gaugeTone == .over
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(urgent ? Ink.badInk : Ink.warnInk, lineWidth: 4)
                .padding(2)
                .alarmPulse(active: true, urgent: urgent)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
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
            feedback: model.cellFeedback,
            hiddenKey: model.hiddenBoardKey,
            preview: model.preview,
            previewGaps: model.previewGaps,
            cursorKey: model.cursorKey,
            selectedKey: model.selectedKey,
            highlightedKeys: model.highlightedKeys,
            wordsAt: model.wordsByCell.mapValues { $0.map(\.word) },
            rotate: rotateControl,
            locked: model.boardLocked)
    }

    private var rotateControl: (key: CellKey, dir: Direction)? {
        guard model.showRotate, case let .place(anchor, dir, _) = model.interaction else {
            return nil
        }
        return (anchor, dir)
    }

    /// The daily's extra summary lines, or nil for any other mode.
    private var dailySummary: SoloSummaryView.DailySummary? {
        guard let daily = model.daily else { return nil }
        return SoloSummaryView.DailySummary(
            date: daily.shortLabel,
            tilesLeft: model.finalTilesLeft,
            bonusEarned: model.finalBonusEarned,
            streak: dailyStreak)
    }

    private var machineContext: GestureMachine.Context {
        GestureMachine.Context(
            boardLocked: model.boardLocked,
            hasStagedPicks: !model.picks.isEmpty,
            externalDragActive: model.wordDrag != nil)
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

    // MARK: Selected-word controls

    @ViewBuilder
    private var wordControls: some View {
        if model.canAcceptInput,
            let selectedKey = model.selectedKey, !model.selectedWords.isEmpty
        {
            let words = model.selectedWords
            let cellRect = camera.gameRect(
                ofContent: camera.metrics.rect(of: parseKey(selectedKey)))
            let height = Double(words.count * 37 + 10)
            let localX = min(
                max(cellRect.midX - camera.frame.minX, 168),
                max(168, camera.viewport.width - 168))
            let localY = max(
                height / 2,
                cellRect.minY - camera.frame.minY - height / 2 + 6)

            WordControlsView(
                words: words,
                canRotate: model.canRotate,
                onGrabBegan: { word, point in model.beginWordDrag(word, at: point) },
                onGrabMoved: model.wordDragMoved,
                onGrabEnded: { point in
                    model.endWordDrag(at: camera.cell(atGame: point))
                    focusGame()
                },
                onGrabCancelled: model.cancelWordDrag,
                onRotate: { word in
                    model.rotateWord(word)
                    focusGame()
                },
                onRemove: { word in
                    model.removeWord(word)
                    focusGame()
                },
                onHighlight: model.setHighlightedWord)
                // Keep the gesture's source mounted until the external drag
                // ends; hiding it must not cancel its pointer stream.
                .opacity(model.wordDrag == nil ? 1 : 0)
                .allowsHitTesting(model.wordDrag == nil)
                .position(x: localX, y: localY)
        }
    }

    // MARK: Word bar (WordBar.tsx + PileTools.tsx)

    private var wordBar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                stagedLetters
                Spacer(minLength: 8)
                wordActions
            }

            // Phone: the word gets the first row and every action stays in a
            // single thumb row below it, with confirm/cancel at the far edge.
            VStack(spacing: 4) {
                ScrollView(.horizontal) {
                    stagedLetters
                }
                .scrollIndicators(.hidden)
                .frame(maxWidth: .infinity, alignment: .leading)

                wordActions
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(Ink.surface)
        .overlay(alignment: .top) {
            if let tone = wordBarTone {
                Rectangle().fill(tone).frame(height: 3)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Word builder")
        .accessibilityValue(wordBarAccessibilityValue)
        .allowsHitTesting(model.canAcceptInput)
    }

    private var stagedLetters: some View {
        HStack(spacing: 4) {
            if model.pickList.isEmpty {
                Text(model.interaction == .idle ? "No letters selected" : "Type your word…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(model.pickList.enumerated()), id: \.offset) { position, pick in
                Button {
                    model.removePick(at: position)
                    focusGame()
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
                .accessibilityLabel(
                    pick.letter.map { "Remove \($0.uppercased())" } ?? "Remove gap")
            }
        }
        .frame(minHeight: 34)
    }

    private var wordActions: some View {
        HStack(spacing: 6) {
            if model.canRedo {
                barButton("↷", label: "Redo the move") {
                    model.redo()
                }
            }
            barButton("↶", label: "Undo the last move", disabled: !model.canUndo) {
                model.undo()
            }

            barButton("□", label: "Add a gap tile") {
                model.addGap()
            }

            barButton("⌫", label: "Remove the last letter", disabled: !model.canBackspace) {
                _ = model.handle(.backspace)
            }

            if model.canRotateAnchor {
                barButton(
                    model.interactionDir == .across ? "⬇" : "➜",
                    label: "Change direction"
                ) {
                    model.rotateDirection()
                }
            }

            // Cancel then confirm, so confirm keeps the far-right corner where
            // a thumb expects it (styles.css:1786, WordBar.tsx).
            barButton("✗", label: "Clear word", tone: .cancel, disabled: !model.canCancel) {
                model.clearFocus()
            }
            barButton("✓", label: "Confirm word", tone: .confirm, disabled: !model.canConfirm) {
                if let target = model.target {
                    model.commit(target.key, target.dir)
                }
            }
        }
    }

    /// The bar's live verdict tint; VoiceOver receives the same state as text.
    private var verdictInk: Color {
        if model.plan != nil, model.plan?.complete == false { return Ink.badInk }
        switch model.verdictOK {
        case true: return Ink.okInk
        case false: return Ink.badInk
        default: return Ink.ink
        }
    }

    private var wordBarTone: Color? {
        if model.plan != nil, model.plan?.complete == false { return Ink.badInk }
        return switch model.verdictOK {
        case true: Ink.okInk
        case false: Ink.badInk
        default: nil
        }
    }

    private var wordBarAccessibilityValue: String {
        if model.plan != nil, model.plan?.complete == false { return "Word does not fit" }
        return switch model.verdictOK {
        case true: "Valid word"
        case false: "Not a valid word"
        default: model.pickList.isEmpty ? "Empty" : "Not yet judged"
        }
    }

    /// The word bar's yes/no pair wears colour; every other tool is ink on
    /// white. "Cancel wears red the way confirm wears green: the pair reads as
    /// no / yes" (styles.css:926–937).
    enum BarTone {
        case plain, confirm, cancel

        var fill: Color {
            switch self {
            case .plain: Ink.surface
            case .confirm: Ink.okBg
            case .cancel: Ink.badBg
            }
        }

        var edge: Color {
            switch self {
            case .plain: Ink.ink
            case .confirm: Ink.okEdge
            case .cancel: Ink.badEdge
            }
        }
    }

    private func barButton(
        _ glyph: String, label: String, tone: BarTone = .plain, disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            action()
            focusGame()
        } label: {
            Text(glyph)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Ink.ink)
                .frame(width: 40, height: 34)
                .background(RoundedRectangle(cornerRadius: 8).fill(tone.fill))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(tone.edge, lineWidth: 2))
                .opacity(disabled ? 0.35 : 1)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .accessibilityLabel(label)
    }

    // MARK: Hardware keyboard (Mac + iPad)

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
        case .deleteForward: command = .deleteForward
        case .escape: command = .escape
        case .return: command = .confirm
        case .rightArrow: command = .direction(.across)
        case .downArrow: command = .direction(.down)
        default:
            command = press.characters.count == 1 ? .letter(press.characters) : nil
        }

        guard let command else { return .ignored }
        return model.handle(command) ? .handled : .ignored
    }

    private func focusGame() {
        gameFocused = true
    }

    private func startNewGame() {
        startNewGame(pace: model.pace)
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
        model.newGame(pace: pace, now: now)
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
                    // Tiles landing, a refusal, a step completed: things the
                    // board can't show. The web's toast is an aria-live region;
                    // this is its announcement (plan §6.6).
                    AccessibilityNotification.Announcement(toast.text).post()
                    try? await Task.sleep(for: .seconds(2.5))
                    model.clearToast(serial: toast.serial)
                }
                .accessibilityHidden(true)
                .allowsHitTesting(false)
        }
    }
}

#Preview {
    GameScreen(model: {
        let model = GameModel()
        model.newGame(seed: "preview")
        return model
    }())
}
