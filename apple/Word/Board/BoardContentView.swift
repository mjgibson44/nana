import SwiftUI
import WordBoard
import WordCore

/// Everything the board draws, as plain values — keeps the view testable (and
/// benchmarkable) without a game model behind it.
struct BoardScene {
    var metrics: BoardMetrics
    var tiles: [(key: CellKey, letter: String)]
    /// Letters that would land if the opener were confirmed.
    var preview: [CellKey: String] = [:]
    /// The words each placed tile reads in, for its spoken label (plan §6.6).
    var wordsAt: [CellKey: [String]] = [:]
}

/// The board itself: a single Canvas draws the cell lattice (1,100+ cells at
/// max zoom-out stay one draw pass — the §11 perf gate is designed in, not
/// profiled out), and only placed and previewed cells become real views on
/// top. No gestures live here; the unified layer above owns every pointer.
struct BoardContentView: View {
    var scene: BoardScene

    var body: some View {
        let metrics = scene.metrics
        ZStack(alignment: .topLeading) {
            // The empty lattice: rounded cell fills over the board background,
            // the gaps between them reading as hairlines.
            Canvas { context, _ in
                let cell = metrics.cellSize
                let step = metrics.step
                let radius = Self.cornerRadius(for: cell)
                for row in 0..<metrics.rows {
                    for col in 0..<metrics.cols {
                        let rect = CGRect(
                            x: Double(col) * step, y: Double(row) * step,
                            width: cell, height: cell)
                        context.fill(
                            Path(roundedRect: rect, cornerRadius: radius, style: .continuous),
                            with: .color(Palette.surface))
                    }
                }
            }

            // Placed tiles: every one is part of a real word, and wears the
            // word colour.
            ForEach(scene.tiles, id: \.key) { tile in
                let rect = metrics.rect(of: parseKey(tile.key))
                BoardTileView(letter: tile.letter, cellSize: metrics.cellSize)
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
                    .accessibilityElement()
                    .accessibilityLabel(
                        Self.tileLabel(for: tile.key, in: scene, letter: tile.letter))
                    .accessibilityAddTraits(.isButton)
            }

            // Ghost letters of the opener while it's being typed.
            ForEach(Array(scene.preview.keys.sorted()), id: \.self) { key in
                if scene.tiles.first(where: { $0.key == key }) == nil {
                    let rect = metrics.rect(of: parseKey(key))
                    PreviewTileView(letter: scene.preview[key], cellSize: metrics.cellSize)
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                }
            }
        }
        .frame(width: metrics.contentSize.width, height: metrics.contentSize.height)
        .background(Palette.bg)
    }

    static func cornerRadius(for cellSize: Double) -> Double {
        max(2, cellSize * 0.1)
    }

    /// What a placed tile says out loud: its letter, where it sits, and the
    /// words it reads in.
    static func tileLabel(for key: CellKey, in scene: BoardScene, letter: String) -> String {
        let cell = parseKey(key)
        var parts = [
            "\(letter.uppercased()), row \(cell.row + 1) column \(cell.col + 1)"
        ]
        if let words = scene.wordsAt[key], !words.isEmpty {
            parts.append("part of \(words.map { $0.uppercased() }.joined(separator: " and "))")
        }
        parts.append("tap to place your word through it")
        return parts.joined(separator: ", ")
    }
}

/// A placed tile: the word colour, letter in amber.
struct BoardTileView: View {
    var letter: String
    var cellSize: Double

    var body: some View {
        RoundedRectangle(
            cornerRadius: BoardContentView.cornerRadius(for: cellSize), style: .continuous
        )
        .fill(Palette.accentBg)
        .overlay(
            Text(letter.uppercased())
                .font(.system(size: cellSize * 0.56, weight: .bold))
                .foregroundStyle(Palette.accent)
        )
    }
}

/// A ghost of a letter that would land — dashed and translucent.
struct PreviewTileView: View {
    var letter: String?
    var cellSize: Double

    var body: some View {
        let radius = BoardContentView.cornerRadius(for: cellSize)
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(Palette.accentBg.opacity(0.45))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(
                        Palette.accent.opacity(0.7),
                        style: StrokeStyle(lineWidth: max(1, cellSize * 0.06), dash: [4, 3]))
            )
            .overlay {
                if let letter {
                    Text(letter.uppercased())
                        .font(.system(size: cellSize * 0.56, weight: .bold))
                        .foregroundStyle(Palette.accent.opacity(0.7))
                }
            }
    }
}
