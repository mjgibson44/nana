import Foundation
import Observation
import WordBoard
import WordCore

/// A tile's live feedback color, worst problem first (App.tsx:196, 1140–1152).
enum CellFeedback {
    case valid
    case invalid
    case isolated
    case disconnected
}

/// Word-building state, shared by every input flow (App.tsx:243–271):
///
///  - `spell`: letters were chosen first (typed or tapped from the pile) and
///    are waiting for a cell to land on;
///  - `place`: a board cell was chosen first — it always comes with a
///    direction, so letters preview from it as soon as they arrive.
///
/// `picks` holds pile indices in typed order in both cases, so a player can
/// start either way round and switch freely.
enum Interaction: Equatable {
    case idle
    case spell(picks: [Int])
    case place(anchor: CellKey, dir: Direction, picks: [Int])

    var picks: [Int] {
        switch self {
        case .idle: return []
        case let .spell(picks): return picks
        case let .place(_, _, picks): return picks
        }
    }

    func withPicks(_ picks: [Int]) -> Interaction {
        if case let .place(anchor, dir, _) = self {
            return .place(anchor: anchor, dir: dir, picks: picks)
        }
        return picks.isEmpty ? .idle : .spell(picks: picks)
    }
}

struct Selection: Equatable {
    var key: CellKey
    var dir: Direction
}

/// A tile riding under the pointer (App.tsx `DragState`, 200–206). The source
/// tile hides in place while the ghost follows.
struct TileDrag: Equatable {
    var letter: String
    var source: GestureMachine.DragSource
    var location: CGPoint
}

/// The single toast slot, keyed by serial so repeats replay (App.tsx:415).
struct GameToast: Equatable {
    var text: String
    var serial: Int
}

/// The solo board's interaction model, ported from the word-building half of
/// `App.tsx` — the parts phase 2a needs to exercise the board and the unified
/// gesture layer. Scoring, clocks, undo history, tutorial and battle wiring
/// arrive with phases 2b/4.
@Observable @MainActor
final class GameModel {
    private(set) var board = TileMap()
    private(set) var rack: [String] = []
    private(set) var interaction: Interaction = .idle
    private(set) var selection: Selection?
    private(set) var hoverCell: CellKey?
    private(set) var lastDir: Direction = .across
    private(set) var drag: TileDrag?
    private(set) var toast: GameToast?
    private(set) var dictionary: Set<String>?
    private(set) var seed = ""
    /// Bumped per deal so the viewport knows to re-center.
    private(set) var gameSerial = 0
    var boardLocked = false

    // Recomputed once per board change rather than per render.
    private(set) var bounds = boardBounds(TileMap())
    private(set) var validation: BoardValidation?
    private(set) var wordsByCell: [CellKey: [WordRun]] = [:]
    private(set) var tileBounds: Bounds?
    private(set) var cellFeedback: [CellKey: CellFeedback] = [:]

    private var toastSerial = 0

    // MARK: Derived word-building state

    var picks: [Int] { interaction.picks }

    var pickList: [Pick] {
        picks
            .filter { $0 == GAP || rack.indices.contains($0) }
            .map { $0 == GAP ? Pick(letter: nil, rackIndex: GAP) : Pick(letter: rack[$0], rackIndex: $0) }
    }

    /// The direction to use for a cell without asking; nil means the cell
    /// can't start a word at all (App.tsx:1175–1186).
    func assumeDir(_ key: CellKey) -> Direction? {
        let cell = parseKey(key)
        let startable = startableDirections(board: board, bounds: bounds, cell: cell)
        if startable.isEmpty { return nil }
        let implied = impliedDirections(board: board, cell: cell).filter { startable.contains($0) }
        let choices = implied.isEmpty ? startable : implied
        return choices.contains(lastDir) ? lastDir : choices[0]
    }

    /// Where the word would go right now: a chosen cell owns the preview;
    /// until then staged letters follow the pointer (App.tsx:1197–1206).
    var target: (key: CellKey, dir: Direction)? {
        if case let .place(anchor, dir, _) = interaction { return (anchor, dir) }
        if let hoverCell, !picks.isEmpty, let dir = assumeDir(hoverCell) {
            return (hoverCell, dir)
        }
        return nil
    }

    var plan: PlacementPlan? {
        guard let target, !pickList.isEmpty else { return nil }
        return planPlacement(
            board: board, bounds: bounds, anchor: parseKey(target.key), dir: target.dir,
            picks: pickList)
    }

    var preview: [CellKey: String] {
        guard let plan else { return [:] }
        return Dictionary(uniqueKeysWithValues: plan.steps.map { ($0.key, $0.letter) })
    }

    var previewGaps: Set<CellKey> {
        Set(plan?.unfilledGaps ?? [])
    }

    /// The square the next letter lands on (App.tsx:1248–1254).
    var cursorKey: CellKey? {
        guard case let .place(anchor, dir, _) = interaction else { return nil }
        let cursor = cursorCell(
            board: board, bounds: bounds, anchor: parseKey(anchor), dir: dir, picks: pickList)
        return cursor.map { keyOf($0.row, $0.col) }
    }

    /// Only offer to rotate when the cell genuinely could go either way.
    var canRotateAnchor: Bool {
        guard case let .place(anchor, _, _) = interaction else { return false }
        return startableDirections(board: board, bounds: bounds, cell: parseKey(anchor)).count > 1
    }

    /// Controls get out of the way while something is being dragged.
    var showRotate: Bool { canRotateAnchor && drag == nil }

    /// The dragged board tile, hidden in place while its ghost follows.
    var hiddenBoardKey: CellKey? {
        if case let .board(cell, _) = drag?.source { return keyOf(cell.row, cell.col) }
        return nil
    }

    /// The dragged rack tile, likewise.
    var hiddenRackIndex: Int? {
        if case let .rack(index, _) = drag?.source { return index }
        return nil
    }

    /// Only show the ring while there is still a tile there to delete.
    var selectedKey: CellKey? {
        guard let selection, board[selection.key] != nil else { return nil }
        return selection.key
    }

    /// Live dictionary check on the word being built (App.tsx:1265–1293).
    var verdictOK: Bool? {
        guard let dictionary, let plan, plan.complete else { return nil }
        var next = board
        for step in plan.steps { next[step.key] = step.letter }
        let placed = Set(plan.steps.map(\.key))
        let runs = extractRuns(next).filter { $0.cells.contains { placed.contains($0) } }
        if runs.isEmpty { return nil }
        return runs.allSatisfy { $0.word.count >= MIN_WORD_LENGTH && dictionary.contains($0.word) }
    }

    var canConfirm: Bool {
        guard case .place = interaction, let plan else { return false }
        return plan.complete && !plan.steps.isEmpty && (!boardLocked || (verdictOK ?? false))
    }

    var canCancel: Bool { interaction != .idle || selectedKey != nil }

    /// The anchored direction, when a cell is chosen.
    var interactionDir: Direction? {
        if case let .place(_, dir, _) = interaction { return dir }
        return nil
    }

    // MARK: Game lifecycle

    func newGame(seed: String = randomSeed()) {
        self.seed = seed
        gameSerial += 1
        setBoard(TileMap())
        let puzzle = try? generatePuzzle(
            wordPool: commonWords, tileCount: ENDLESS_START_TILES, rng: seededRng(seed))
        rack = puzzle?.letters ?? []
        selection = nil
        drag = nil
        hoverCell = nil
        toast = nil
        lastDir = .across
        // Pre-anchor the middle cell so typing previews immediately
        // (App.tsx:536–539).
        let middle = keyOf(BOARD_SIZE / 2, BOARD_SIZE / 2)
        interaction = .place(anchor: middle, dir: assumeDir(middle) ?? .across, picks: [])
    }

    func loadDictionary() async {
        guard dictionary == nil,
            let url = Bundle.main.url(forResource: "dictionary", withExtension: "txt")
        else { return }
        let parsed = await Task.detached(priority: .utility) { () -> Set<String>? in
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
            return parseDictionary(text)
        }.value
        guard let parsed else { return }
        dictionary = parsed
        refreshBoardCaches()
    }

    // MARK: Word building

    func setPicks(_ next: [Int]) {
        interaction = interaction.withPicks(next)
    }

    /// Claim a pile tile for the current word, or release it (App.tsx:1941–1953).
    func togglePick(_ index: Int) {
        let current = picks
        if let at = current.firstIndex(of: index) {
            setPicks(current.enumerated().filter { $0.offset != at }.map(\.element))
        } else {
            setPicks(current + [index])
        }
    }

    /// Claim the first unclaimed matching pile tile (App.tsx:1955–1965).
    func typeLetter(_ letter: String) {
        let index = findAvailable(rack: rack, letter: letter, taken: Set(picks))
        guard index != -1 else { return }
        setPicks(picks + [index])
    }

    /// Stage a hole that must land on a letter already on the board.
    func addGap() {
        setPicks(picks + [GAP])
    }

    /// Remove one staged letter/gap by its position in the word
    /// (WordBar.tsx:102–119).
    func removePick(at position: Int) {
        setPicks(picks.enumerated().filter { $0.offset != position }.map(\.element))
    }

    /// Put the board back to nothing chosen (App.tsx:1296–1300).
    func clearFocus() {
        selection = nil
        interaction = .idle
    }

    /// Flip the chosen cell between across and down (App.tsx:2257–2264).
    func rotateDirection() {
        guard case let .place(anchor, dir, picks) = interaction else { return }
        let next: Direction = dir == .across ? .down : .across
        lastDir = next
        interaction = .place(anchor: anchor, dir: next, picks: picks)
    }

    /// Follow the pointer, but only while a word is waiting and nothing is
    /// being dragged (App.tsx:1213–1219).
    func setHover(_ key: CellKey?) {
        let wanted = !picks.isEmpty && drag == nil ? key : nil
        if hoverCell != wanted { hoverCell = wanted }
    }

    // MARK: Taps (routed from the gesture machine)

    /// Tap an empty cell: staged letters ride along to the new anchor
    /// (App.tsx onCellClick, 2279–2306).
    func cellClick(_ key: CellKey) {
        selection = nil
        // A single letter reads the same across as down — clicking the cell
        // is the whole gesture.
        if pickList.count == 1, board[key] == nil {
            commit(key, .across)
            return
        }
        guard let dir = assumeDir(key) else {
            interaction = .idle
            return
        }
        interaction = .place(anchor: key, dir: dir, picks: picks)
    }

    /// Tap a placed tile (App.tsx selectTile, 2229–2254).
    func selectTile(_ key: CellKey) {
        if !picks.isEmpty {
            _ = commitThroughLetter(key)
            return
        }
        if !boardLocked {
            let runs = wordsByCell[key]
            let dir: Direction = runs?.contains { $0.direction == .across } == true ? .across : .down
            selection = Selection(key: key, dir: dir)
        }
        let startDir = assumeDir(key)
        interaction = startDir.map { .place(anchor: key, dir: $0, picks: []) } ?? .idle
    }

    /// Double-press on a board tile: turn the word about its first letter, or
    /// return the letter to the pile (App.tsx:2567–2584).
    func doubleTapBoardTile(_ key: CellKey) {
        let leads = (wordsByCell[key] ?? []).filter { $0.cells.first == key }
        if !leads.isEmpty {
            let word =
                leads.first { $0.direction == .across && canRotate($0) }
                ?? leads.first { canRotate($0) }
            if let word {
                rotateWord(word)
            } else {
                rejectToast("No room to turn \(leads[0].word.uppercased())")
            }
            return
        }
        returnToRack(key)
    }

    /// Place the staged word so its first gap sits on the letter at `key`
    /// (App.tsx commitThroughLetter, 2168–2217).
    @discardableResult
    func commitThroughLetter(_ key: CellKey) -> Bool {
        guard board[key] != nil else { return false }
        guard pickList.contains(where: { $0.letter == nil }) else { return false }

        let cell = parseKey(key)
        // Crossing the word the clicked letter already reads in is the
        // likelier intent, so that direction goes first.
        let runDirs = Set((wordsByCell[key] ?? []).map(\.direction))
        let ordered: [Direction] =
            runDirs.contains(.across) == runDirs.contains(.down)
            ? (lastDir == .across ? [.across, .down] : [.down, .across])
            : (runDirs.contains(.across) ? [.down, .across] : [.across, .down])

        let fits: [(anchor: Cell, dir: Direction, plan: PlacementPlan)] = ordered.compactMap { dir in
            guard
                let anchor = anchorForGapTarget(
                    board: board, bounds: bounds, target: cell, dir: dir, picks: pickList)
            else { return nil }
            let plan = planPlacement(
                board: board, bounds: bounds, anchor: anchor, dir: dir, picks: pickList)
            return plan.complete && !plan.steps.isEmpty ? (anchor, dir, plan) : nil
        }
        guard !fits.isEmpty else {
            rejectToast("That word doesn’t fit over this letter.")
            return false
        }

        // When the word fits both ways, prefer the way that spells real words.
        let best =
            fits.first { fit in
                guard let dictionary else { return false }
                var next = board
                for step in fit.plan.steps { next[step.key] = step.letter }
                var placed = Set(fit.plan.steps.map(\.key))
                placed.insert(key)
                return extractRuns(next)
                    .filter { $0.cells.contains { placed.contains($0) } }
                    .allSatisfy { $0.word.count >= MIN_WORD_LENGTH && dictionary.contains($0.word) }
            } ?? fits[0]

        commit(keyOf(best.anchor.row, best.anchor.col), best.dir)
        return true
    }

    // MARK: Commit — every landing goes through it (App.tsx:2024–2145)

    func commit(_ anchor: CellKey, _ dir: Direction, picksToPlace: [Pick]? = nil) {
        let picksToPlace = picksToPlace ?? pickList
        guard !picksToPlace.isEmpty else { return }
        let result = planPlacement(
            board: board, bounds: bounds, anchor: parseKey(anchor), dir: dir, picks: picksToPlace)
        guard !result.steps.isEmpty, result.complete else { return }

        var next = board
        for step in result.steps { next[step.key] = step.letter }
        let placed = Set(result.steps.map(\.key))
        let newRuns = extractRuns(next).filter { $0.cells.contains { placed.contains($0) } }

        // On a locked board a placement is forever, so only real words are
        // allowed down.
        if boardLocked {
            guard let dictionary else {
                rejectToast("Hold on — the dictionary is still loading.")
                return
            }
            if newRuns.isEmpty {
                rejectToast("A lone letter has to join a word.")
                return
            }
            let bad = newRuns.filter {
                $0.word.count < MIN_WORD_LENGTH || !dictionary.contains($0.word)
            }
            if !bad.isEmpty {
                let words = bad.map { $0.word.uppercased() }
                rejectToast(
                    words.count == 1
                        ? "\(words[0]) isn’t a word"
                        : "\(words.joined(separator: ", ")) aren’t words")
                return
            }
        }

        // Phase 2b/4: undo snapshot, commit sound, tutorial gap-step
        // enforcement and battle attacks join here — this is the one funnel.
        setBoard(next)
        let spent = Set(result.steps.map(\.rackIndex))
        rack = rack.enumerated().filter { !spent.contains($0.offset) }.map(\.element)
        lastDir = dir
        clearFocus()
    }

    // MARK: Dragging (App.tsx:2418–2533)

    func beginDrag(_ source: GestureMachine.DragSource, at location: CGPoint) {
        let letter: String
        switch source {
        case let .rack(_, l), let .board(_, l): letter = l
        }
        hoverCell = nil
        drag = TileDrag(letter: letter, source: source, location: location)
    }

    func dragMoved(to location: CGPoint) {
        drag?.location = location
    }

    func endDrag() {
        drag = nil
    }

    enum DropRegion: Equatable {
        case cell(Cell)
        case rack
        case none
    }

    /// Apply a real drop (the machine already ruled out taps).
    func applyDrop(_ region: DropRegion) {
        guard let drag else { return }
        self.drag = nil
        let source = drag.source

        switch region {
        case let .cell(cell):
            let key = keyOf(cell.row, cell.col)
            // A drop onto a locked board goes through the same commit flow as
            // a typed word, so dictionary judging still applies.
            if boardLocked {
                if case let .rack(index, letter) = source, board[key] == nil {
                    commit(key, .across, picksToPlace: [Pick(letter: letter, rackIndex: index)])
                }
                return
            }
            let sourceKey: CellKey? = {
                if case let .board(cell, _) = source { return keyOf(cell.row, cell.col) }
                return nil
            }()
            let sameCell = sourceKey == key
            guard sameCell || board[key] == nil else { return }
            var next = board
            if let sourceKey { next[sourceKey] = nil }
            next[key] = drag.letter
            setBoard(next)
            switch source {
            case let .rack(index, _):
                rack.remove(at: index)
                interaction = .idle
            case .board:
                // The tile moved, so the old cell is no longer what's selected.
                if selection?.key == sourceKey { selection = nil }
            }

        case .rack:
            if case let .board(cell, letter) = source {
                var next = board
                next[keyOf(cell.row, cell.col)] = nil
                setBoard(next)
                rack.append(letter)
                if selection?.key == keyOf(cell.row, cell.col) { selection = nil }
            }

        case .none:
            break
        }
    }

    /// The hold fired: a held anchor lets the preview follow the finger again
    /// (App.tsx:2645–2652).
    func beginPreviewDrag() {
        if case let .place(_, _, picks) = interaction {
            interaction = picks.isEmpty ? .idle : .spell(picks: picks)
        }
    }

    // MARK: Board words (App.tsx:1766–1852)

    func canRotate(_ word: WordRun) -> Bool {
        planWordCells(
            board: board, bounds: bounds, length: word.cells.count, own: word.cells,
            dir: word.direction == .across ? .down : .across, start: parseKey(word.cells[0]))
            != nil
    }

    /// Move a word's tiles so its first letter lands on `start`.
    @discardableResult
    func moveWord(_ word: WordRun, to start: CellKey, dir: Direction) -> Bool {
        guard
            let targets = planWordCells(
                board: board, bounds: bounds, length: word.cells.count, own: word.cells,
                dir: dir, start: parseKey(start))
        else { return false }
        let letters = word.cells.compactMap { board[$0] }
        selection = nil
        var next = board
        for key in word.cells { next[key] = nil }
        for (i, key) in targets.enumerated() { next[key] = letters[i] }
        setBoard(next)
        return true
    }

    /// Turn a word about its first letter, which stays put.
    func rotateWord(_ word: WordRun) {
        let pivot = word.cells[0]
        let dir: Direction = word.direction == .across ? .down : .across
        guard moveWord(word, to: pivot, dir: dir) else { return }
        selection = Selection(key: pivot, dir: dir)
    }

    /// Send the tile back to the pile (App.tsx returnToRack, 2535–2549).
    func returnToRack(_ key: CellKey) {
        guard let letter = board[key] else { return }
        var next = board
        next[key] = nil
        setBoard(next)
        rack.append(letter)
        if selection?.key == key { selection = nil }
    }

    /// Reshuffle the pile and drop the staged word (App.tsx:2602–2605).
    func shufflePile() {
        rack.shuffle()
        interaction = .idle
    }

    /// A refusal that changes nothing on screen reads as a bug, so it always
    /// gets a banner (App.tsx rejectToast, 1979–1981).
    func rejectToast(_ text: String) {
        toastSerial += 1
        toast = GameToast(text: text, serial: toastSerial)
    }

    func clearToast(serial: Int) {
        if toast?.serial == serial { toast = nil }
    }

    // MARK: Board mutation

    private func setBoard(_ next: TileMap) {
        board = next
        refreshBoardCaches()
    }

    private func refreshBoardCaches() {
        bounds = boardBounds(board)
        tileBounds = tileBox(of: board)
        validation = dictionary.map { validateBoard(board, dictionary: $0) }

        var byCell: [CellKey: [WordRun]] = [:]
        for run in extractRuns(board) where run.cells.count > 1 {
            for cell in run.cells { byCell[cell, default: []].append(run) }
        }
        wordsByCell = byCell

        // Worst problem wins: invalid > isolated > disconnected > valid
        // (App.tsx:1140–1152).
        var feedback: [CellKey: CellFeedback] = [:]
        if let validation {
            for key in validation.disconnectedTiles { feedback[key] = .disconnected }
            for run in validation.runs {
                for cell in run.cells {
                    if !run.valid {
                        feedback[cell] = .invalid
                    } else if feedback[cell] == nil {
                        feedback[cell] = .valid
                    }
                }
            }
            for key in validation.isolatedTiles { feedback[key] = .isolated }
        }
        cellFeedback = feedback
    }
}
