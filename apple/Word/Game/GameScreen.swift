import SwiftUI
import WordBoard
import WordCore

/// The game screen, top to bottom: header and pile gauge, the board, the
/// word being built, the pile with shuffle beside it, and the row of word
/// actions — one column with the same margin all round and the same gap
/// between every section.
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
    /// The tile-lettered menu, in place of the platform's.
    @State private var menuOpen = false
    /// The column's inner width, which sizes the tiles: eight of them and
    /// the shuffle button across, always.
    @State private var columnWidth: CGFloat = 358
    /// Where the pile is, in the game's coordinate space: a tile dropped
    /// back here goes home.
    @State private var pileFrame: CGRect = .zero
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
                    if model.isOccupy {
                        // The pile can't bury anyone here; the bar says who
                        // holds how much of the board instead.
                        OccupyBarView(segments: occupySegments)
                    } else {
                        PileGaugeView(count: model.pileCount, tone: model.pileTone)
                        if !rivals.isEmpty {
                            RivalGaugesView(rivals: rivals)
                        }
                    }
                }
                boardArea
                WordRowView(
                    picks: model.pickList, verdict: model.wordVerdict, tileSize: tileSize,
                    width: columnWidth
                ) { position in
                    model.removePick(at: position)
                    focusGame()
                }
                .allowsHitTesting(model.canAcceptInput)
                pile
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

            // The tile in the hand rides above everything.
            if let drag = model.drag {
                GhostTileView(letter: drag.letter, size: tileSize)
                    .position(drag.location)
            }

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

            if menuOpen {
                GameMenuView(items: menuItems, onClose: closeMenu)
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
        // A word that doesn't read stays up in red long enough to be read,
        // and is then taken back with the reason.
        .task(id: model.aim?.serial) {
            guard model.aimRejected, let serial = model.aim?.serial else { return }
            do {
                try await Task.sleep(for: .seconds(REJECTED_AIM_SECONDS))
            } catch {
                return
            }
            model.finishRejectedAim(serial: serial)
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
            // A shared board opens centred on its middle ground, every seat's
            // corner in view; a solo one on its start square, with room for
            // a long opener.
            if model.isOccupy {
                camera.newGame(bounds: model.bounds, anchor: model.boardCentre, opening: .centred)
            } else {
                camera.newGame(bounds: model.bounds, anchor: model.startCell, opening: .opener)
            }
        }
        #if os(iOS)
        .onChange(of: sizeClass, initial: true) { _, sizeClass in
            camera.cellBase = sizeClass == .compact ? CELL_BASE_COMPACT : CELL_BASE_REGULAR
        }
        #endif
    }

    // MARK: Header

    private var header: some View {
        let pause: (() -> Void)? = model.canPause ? { pauseGame() } : nil
        return GameHeaderView(
            headline: headline,
            headlineLabel: headlineLabel,
            secondsToTiles: model.secondsToNextTiles(at: clockNow),
            tilesComing: model.nextTileCount,
            clock: headerClock,
            onPause: pause,
            onMenu: openMenu)
    }

    /// Occupy's clock: the match clock, or the stall countdown once it's close.
    private var headerClock: HeaderClock? {
        guard let left = model.occupySecondsLeft(at: clockNow) else { return nil }
        return HeaderClock(secondsLeft: left, stallSeconds: model.occupyStallSecondsLeft(at: clockNow))
    }

    /// Everyone's share of the board, yours first, for the balanced bar.
    private var occupySegments: [OccupyBarView.Segment] {
        guard let battle, let occupy = battle.state?.occupy else { return [] }
        let scores = model.occupyScores.isEmpty ? occupy.scores : model.occupyScores
        let viewer = model.occupySeat
        var segments = occupy.seats.enumerated().map { seat, id in
            OccupyBarView.Segment(
                id: seat,
                name: battle.contestants.first { $0.id == id }?.name ?? "Player",
                value: scores.indices.contains(seat) ? scores[seat] : 0,
                colors: SeatColors.of(seat: seat, viewer: viewer))
        }
        if let viewer, let mine = segments.firstIndex(where: { $0.id == viewer }) {
            segments.insert(segments.remove(at: mine), at: 0)
        }
        return segments
    }

    /// Everyone else in the battle, in roster order, for the row of small
    /// gauges under your own.
    private var rivals: [RivalGaugesView.Rival] {
        guard let battle else { return [] }
        return battle.contestants
            .filter { $0.id != battle.selfID }
            .map { player in
                RivalGaugesView.Rival(
                    id: player.id, name: player.name, tiles: player.tiles,
                    isOut: player.buried || player.left)
            }
    }

    /// The score — or, in a battle, where this player stands. Occupy shows
    /// the value held: the bar under it already says who's ahead.
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
        if model.isOccupy {
            return model.isComplete ? "Final value \(model.score)" : "Board value \(model.score)"
        }
        return model.isComplete ? "Final score \(model.score)" : "Score \(model.score)"
    }

    private var menuItems: [GameMenuView.Item] {
        var items: [GameMenuView.Item] = []
        if model.isComplete {
            items.append(
                GameMenuView.Item(title: "RESULTS", accent: true) {
                    closeMenu()
                    model.setSummaryPresented(true)
                })
        }
        if model.isBattle || model.isOccupy {
            if let battle, battle.isHost {
                if battle.canRestart {
                    items.append(
                        GameMenuView.Item(title: "RESTART") {
                            closeMenu()
                            battle.restart()
                        })
                }
                items.append(
                    GameMenuView.Item(title: "LOBBY") {
                        closeMenu()
                        battle.toLobby()
                    })
            }
            items.append(
                GameMenuView.Item(title: "LEAVE") {
                    closeMenu()
                    onLeave()
                })
        } else {
            items.append(
                GameMenuView.Item(title: "NEW GAME") {
                    closeMenu()
                    startNewGame(pace: model.pace)
                })
            items.append(
                GameMenuView.Item(title: "HOME") {
                    closeMenu()
                    onLeave()
                })
        }
        return items
    }

    private func openMenu() {
        // The board must not be mid-gesture behind a modal.
        settleGestures()
        menuOpen = true
    }

    /// Nothing mid-gesture survives a modal or a new deal: the hold timer,
    /// the machine, an aimed word and a tile in the hand all let go.
    private func settleGestures() {
        holdTask?.cancel()
        holdTask = nil
        machine = GestureMachine()
        model.clearAim()
        model.endDrag()
    }

    private func closeMenu() {
        menuOpen = false
        focusGame()
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
            previewIsGood: model.wordVerdict != .bad,
            staged: model.stagedLetters,
            stagedIsGood: model.stagedVerdict != .bad,
            aim: model.aim?.cells,
            aimIsGood: model.aim?.isGood ?? true,
            wordsAt: model.wordsByCell.mapValues { $0.map(\.word) },
            owners: model.owners,
            viewerSeat: model.occupySeat,
            zones: model.occupyZones)
    }

    /// Placed words are permanent in every mode, and nothing placed is ever
    /// picked up off the board: the machine needs taps, pans, and — with a
    /// gapped word in hand — the press-and-hold that aims it through a
    /// letter. Staged tiles are their own target, and lift regardless.
    private var machineContext: GestureMachine.Context {
        GestureMachine.Context(
            boardLocked: true,
            hasStagedPicks: !model.picks.isEmpty,
            externalDragActive: false,
            hasGapPick: model.hasGap)
    }

    /// The press-time hit-test, as coordinate math.
    private func boardTarget(at point: CGPoint) -> GestureMachine.DownTarget? {
        guard let cell = camera.cell(atGame: point) else { return .boardEmpty(cell: nil) }
        let key = keyOf(cell.row, cell.col)
        if let letter = model.stagedLetters[key] {
            return .stagedTile(cell: cell, letter: letter)
        }
        if let letter = model.board[key] {
            return .boardTile(cell: cell, letter: letter)
        }
        return .boardEmpty(cell: cell)
    }

    /// Where a dragged tile was let go — the port of the web's
    /// `elementFromPoint` + `[data-rack]` contract: anywhere on the pile
    /// returns the tile; a board square stages it there.
    private func dropRegion(at point: CGPoint) -> GameModel.DropRegion {
        if pileFrame.contains(point) { return .pile }
        if let cell = camera.cell(atGame: point) { return .cell(cell) }
        return .none
    }

    /// The board letter under a point, if there is one.
    private func letterKey(at point: CGPoint) -> CellKey? {
        guard let cell = camera.cell(atGame: point) else { return nil }
        let key = keyOf(cell.row, cell.col)
        return model.board[key] == nil ? nil : key
    }

    /// Aim the staged word through whatever letter is under the finger. Off
    /// the letters there is nothing to aim through, so the preview goes away
    /// rather than sticking to the last one — the board says what a release
    /// here would do, which is nothing.
    private func aim(at point: CGPoint) {
        guard let key = letterKey(at: point) else {
            model.clearAim()
            return
        }
        model.aimThroughLetter(key)
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
            case let .tapRackTile(index):
                model.togglePick(index)
                focusGame()
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
            case let .beginPreviewDrag(point), let .previewDragMoved(point):
                // Holding a gapped word over the board: show where it would
                // go, and let the finger carry it from letter to letter.
                aim(at: point)
            case let .endPreviewDrag(point):
                model.releaseAim(over: letterKey(at: point))
                focusGame()
            case .cancelPreviewDrag:
                model.clearAim()
            case .tapBoardCell, .doubleTapBoardTile:
                // Nothing lands by tapping empty board, and a placed tile
                // never comes back off: neither can happen with the context
                // above, and neither means anything now.
                break
            }
        }
    }

    // MARK: The pile and the actions

    /// The pile, with shuffle beside it: the one button that acts on the
    /// tiles rather than on the word stands with the tiles.
    private var pile: some View {
        HStack(alignment: .top, spacing: Spacing.gap) {
            PileView(
                letters: model.rack, picked: Set(model.picks), staged: model.stagedIndices,
                hidden: model.hiddenRackIndex, tileSize: tileSize,
                onTap: { index in
                    model.togglePick(index)
                    focusGame()
                },
                dispatch: dispatch, context: { machineContext }
            )
            .frame(width: Spacing.pileWidth(tileSize: tileSize))
            PileShuffleButton(height: pileHeight, disabled: !model.canShuffle) {
                model.shufflePile()
                focusGame()
            }
        }
        .onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .named(Self.space))
        } action: { frame in
            pileFrame = frame
        }
    }

    /// Three rows of tiles and the gaps between them.
    private var pileHeight: CGFloat {
        CGFloat(Spacing.pileRows) * tileSize + CGFloat(Spacing.pileRows - 1) * Spacing.tileGap
    }

    private var actions: some View {
        HStack(spacing: Spacing.tileGap) {
            ActionButton(
                systemImage: "trash", label: "Clear the word",
                disabled: !model.canClearWord
            ) {
                model.clearWord()
                focusGame()
            }
            if model.isFirstWord || model.hasStaged {
                // The opener is the one word placed by fiat, and tiles dropped
                // on the board wait for the same ✓: it takes the gap button's
                // place whenever there is something for it to land.
                ActionButton(
                    systemImage: "checkmark",
                    label: model.hasStaged ? "Place the tiles on the board" : "Place your first word",
                    accent: true, disabled: !model.canConfirm
                ) {
                    model.confirm()
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
            placing: model.isBattle || model.isOccupy ? battle?.position.map(ordinal) : nil,
            standings: model.isOccupy ? occupyStandings : battleStandings,
            note: endNote,
            restart: endRestart,
            onSeeGame: { model.setSummaryPresented(false) },
            onLobby: battle?.isHost == true ? { battle?.toLobby() } : nil,
            leaveLabel: model.isBattle || model.isOccupy ? "LEAVE" : "HOME",
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
            let how: String? = {
                guard model.isOccupy, let end = battle.state?.occupy?.end else { return nil }
                switch end {
                case .clock: return "Time."
                case .stall: return "The board was stuck."
                case .field: return "Everyone else left."
                }
            }()
            let wait = battle.isHost ? nil : "Waiting for the host to restart or reopen the lobby."
            return [how, wait].compactMap { $0 }.joined(separator: " ").nilIfEmpty
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

    /// Occupy's field by value, each row worth what its seat holds.
    private var occupyStandings: [GameEndView.Standing] {
        guard let battle else { return [] }
        return battle.occupyStandings.map { row in
            GameEndView.Standing(
                id: row.player.id, rank: row.rank, name: row.player.name,
                isSelf: row.player.id == battle.selfID,
                note: row.player.left ? "left" : "\(row.value)")
        }
    }

    // MARK: Hardware keyboard (iPad)

    private func handleKeyPress(_ press: KeyPress) -> KeyPress.Result {
        if menuOpen {
            // The menu owns the screen while it's up: escape closes it, and
            // nothing else reaches the word behind it.
            guard press.key == .escape else { return .ignored }
            closeMenu()
            return .handled
        }
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
        settleGestures()
        model.pause(at: .now)
    }

    private func startNewGame(pace: SoloPace) {
        let now = Date.now
        clockNow = now
        settleGestures()
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

extension String {
    fileprivate var nilIfEmpty: String? { isEmpty ? nil : self }
}
