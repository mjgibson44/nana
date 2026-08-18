import SwiftUI
import WordBoard
import WordCore

/// Everything the board draws, as plain values — keeps the view testable (and
/// benchmarkable) without a game model behind it.
struct BoardScene {
    var metrics: BoardMetrics
    var tiles: [(key: CellKey, letter: String)]
    var feedback: [CellKey: CellFeedback] = [:]
    /// The tile being dragged, hidden in place while its ghost follows.
    var hiddenKey: CellKey?
    /// Letters that would land if the current word were committed.
    var preview: [CellKey: String] = [:]
    /// Squares a gap tile is holding open, still waiting for a letter.
    var previewGaps: Set<CellKey> = []
    /// The square the next letter lands on.
    var cursorKey: CellKey?
    /// The placed tile picked out for deletion.
    var selectedKey: CellKey?
    /// The anchored cell and its direction — where the rotate control sits.
    var rotate: (key: CellKey, dir: Direction)?
    var locked = false
}

/// The board itself: a single Canvas draws the cell lattice (1,100+ cells at
/// max zoom-out stay one draw pass — the §11 perf gate is designed in, not
/// profiled out), and only occupied/preview cells become real views on top.
/// No gestures live here; the unified layer above owns every pointer.
struct BoardContentView: View {
    var scene: BoardScene
    var onRotate: () -> Void = {}

    var body: some View {
        let metrics = scene.metrics
        ZStack(alignment: .topLeading) {
            // The empty lattice: cell fills over the board background, the
            // 1pt gaps between them reading as hairlines (styles.css:437–446).
            Canvas { context, _ in
                let cell = metrics.cellSize
                let step = metrics.step
                for row in 0..<metrics.rows {
                    for col in 0..<metrics.cols {
                        let rect = CGRect(
                            x: Double(col) * step, y: Double(row) * step,
                            width: cell, height: cell)
                        context.fill(Path(rect), with: .color(Ink.cellBg))
                    }
                }
            }

            // Placed tiles: frameless solid fills, status color as the fill
            // (styles.css:529–542, 616–635).
            ForEach(scene.tiles, id: \.key) { tile in
                let rect = metrics.rect(of: parseKey(tile.key))
                BoardTileView(
                    letter: tile.letter,
                    feedback: scene.feedback[tile.key],
                    selected: tile.key == scene.selectedKey,
                    cellSize: metrics.cellSize
                )
                .opacity(tile.key == scene.hiddenKey ? 0 : 1)
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)
            }

            // Ghost letters of the staged word, and the holes its gaps hold
            // open (Grid.tsx:116–124).
            ForEach(Array(scene.preview.keys), id: \.self) { key in
                if scene.tiles.first(where: { $0.key == key }) == nil {
                    let rect = metrics.rect(of: parseKey(key))
                    PreviewTileView(letter: scene.preview[key], cellSize: metrics.cellSize)
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                }
            }
            ForEach(Array(scene.previewGaps), id: \.self) { key in
                let rect = metrics.rect(of: parseKey(key))
                PreviewTileView(letter: nil, cellSize: metrics.cellSize)
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
            }

            // The cursor cell's heavy inset ring (styles.css:469–473).
            if let cursorKey = scene.cursorKey {
                let rect = metrics.rect(of: parseKey(cursorKey))
                Rectangle()
                    .strokeBorder(Ink.focus, lineWidth: max(2, metrics.cellSize * 0.07))
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
            }

            // The rotate control on the anchored cell: the only sign of the
            // assumed direction; tapping it turns the cell (Grid.tsx:139–157).
            // Hit-testing happens in the unified gesture layer (rotateHitRect),
            // not here — a clipped SwiftUI view would still catch stray taps.
            if let rotate = scene.rotate {
                let rect = Self.rotateRect(for: rotate.key, metrics: metrics)
                Text(rotate.dir == .across ? "➜" : "⬇")
                    .font(.system(size: rect.width * 0.55, weight: .bold))
                    .foregroundStyle(Ink.ink)
                    .frame(width: rect.width, height: rect.height)
                    .background(Circle().fill(Ink.surface))
                    .overlay(Circle().strokeBorder(Ink.ink, lineWidth: 2))
                    .position(x: rect.midX, y: rect.midY)
            }
        }
        .frame(width: metrics.contentSize.width, height: metrics.contentSize.height)
        .background(Ink.boardBg)
    }

    /// Where the rotate control draws, in content coordinates: riding the
    /// anchored cell's bottom-right corner.
    static func rotateRect(for key: CellKey, metrics: BoardMetrics) -> CGRect {
        let cell = metrics.rect(of: parseKey(key))
        let size = max(18, metrics.cellSize * 0.5)
        return CGRect(
            x: cell.maxX - size * 0.65, y: cell.maxY - size * 0.65,
            width: size, height: size)
    }
}

/// A placed tile: solid fill, feedback color as the whole face.
struct BoardTileView: View {
    var letter: String
    var feedback: CellFeedback?
    var selected: Bool
    var cellSize: Double

    var body: some View {
        Rectangle()
            .fill(fillColor)
            .overlay(
                Text(letter.uppercased())
                    .font(.system(size: cellSize * 0.52, weight: .bold))
                    .foregroundStyle(inkColor)
            )
            .overlay {
                if selected {
                    Rectangle().strokeBorder(Ink.focus, lineWidth: max(2, cellSize * 0.07))
                }
            }
    }

    private var fillColor: Color {
        switch feedback {
        case .valid: return Ink.okBg
        case .invalid: return Ink.badBg
        case .disconnected: return Ink.warnBg
        case .isolated: return Ink.isoBg
        case nil: return Ink.tileFace
        }
    }

    private var inkColor: Color {
        switch feedback {
        case .valid: return Ink.okInk
        case .invalid: return Ink.badInk
        case .disconnected: return Ink.warnInk
        case .isolated: return Ink.isoInk
        case nil: return Ink.ink
        }
    }
}

/// A ghost of a letter that would land — dashed and translucent; with no
/// letter it's a gap square, drawn as the hole it is (styles.css:555–570).
struct PreviewTileView: View {
    var letter: String?
    var cellSize: Double

    var body: some View {
        Rectangle()
            .fill(Ink.cellBg.opacity(letter == nil ? 0.4 : 0.8))
            .overlay(
                Rectangle().strokeBorder(
                    Ink.line, style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
            )
            .overlay {
                if let letter {
                    Text(letter.uppercased())
                        .font(.system(size: cellSize * 0.52, weight: .bold))
                        .foregroundStyle(Ink.ink.opacity(0.55))
                }
            }
    }
}
