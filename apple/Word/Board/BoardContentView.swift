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
    /// Whether those letters spell a word. False ghosts them in red, so the
    /// opener answers on the board as well as in the word row.
    var previewIsGood = true
    /// Tiles dragged onto the board and not yet confirmed: the player's own,
    /// sitting where they were dropped, waiting on the ✓.
    var staged: [CellKey: String] = [:]
    /// Whether the staged tiles would land as they stand. False draws them
    /// red — the same answer the word row gives.
    var stagedIsGood = true
    /// The word being held over a board letter by press-and-hold, drawn
    /// solid over everything: every cell it would occupy, borrowed letter
    /// included. Nil when nothing is being aimed.
    var aim: [CellKey: String]? = nil
    /// Whether that word reads. False draws it red — the "this isn't a word"
    /// answer, given before anything is committed rather than after.
    var aimIsGood = true
    /// The words each placed tile reads in, for its spoken label (plan §6.6).
    var wordsAt: [CellKey: [String]] = [:]
    /// Occupy: which seat holds each tile, and which seat is looking. A tile
    /// with no owner wears the word green.
    var owners: [CellKey: Int] = [:]
    var viewerSeat: Int? = nil
    /// Occupy's zones, in this seat's frame: the patches where a tile is
    /// worth double.
    var zones: [OccupyZone] = []
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
            // the gaps between them reading as hairlines — and, in Occupy,
            // the zones: their squares a shade lighter, an edge round each
            // patch, and "2×" on the middle square, all under the tiles.
            Canvas { context, _ in
                let cell = metrics.cellSize
                let step = metrics.step
                let radius = Self.cornerRadius(for: cell)
                let bounds = metrics.bounds
                let zoneCells: Set<Cell> =
                    scene.zones.isEmpty ? [] : Set(scene.zones.flatMap(\.cells))
                for row in 0..<metrics.rows {
                    for col in 0..<metrics.cols {
                        let rect = CGRect(
                            x: Double(col) * step, y: Double(row) * step,
                            width: cell, height: cell)
                        let inZone =
                            !zoneCells.isEmpty
                            && zoneCells.contains(
                                Cell(row: bounds.minRow + row, col: bounds.minCol + col))
                        context.fill(
                            Path(roundedRect: rect, cornerRadius: radius, style: .continuous),
                            with: .color(inZone ? Palette.zoneCell : Palette.surface))
                    }
                }
                for zone in scene.zones {
                    let first = metrics.rect(of: zone.origin)
                    let side = Double(OCCUPY_ZONE_SIZE) * step - CELL_HAIRLINE
                    let edge = CGRect(x: first.minX, y: first.minY, width: side, height: side)
                        .insetBy(dx: -CELL_HAIRLINE / 2, dy: -CELL_HAIRLINE / 2)
                    context.stroke(
                        Path(
                            roundedRect: edge, cornerRadius: radius + CELL_HAIRLINE / 2,
                            style: .continuous),
                        with: .color(Palette.zoneEdge),
                        lineWidth: Self.zoneEdgeWidth(for: cell))
                    let middle = metrics.rect(of: zone.centre)
                    context.draw(
                        Text("2×")
                            .font(.system(size: cell * 0.5, weight: .bold))
                            .foregroundStyle(Palette.zoneEdge),
                        at: CGPoint(x: middle.midX, y: middle.midY))
                }
            }

            // Placed tiles: every one is part of a real word, and wears the
            // word colour — or, in Occupy, its owner's.
            ForEach(scene.tiles, id: \.key) { tile in
                let rect = metrics.rect(of: parseKey(tile.key))
                BoardTileView(
                    letter: tile.letter, cellSize: metrics.cellSize,
                    colors: scene.owners[tile.key].map {
                        SeatColors.of(seat: $0, viewer: scene.viewerSeat)
                    })
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
                    PreviewTileView(
                        letter: scene.preview[key], isGood: scene.previewIsGood,
                        cellSize: metrics.cellSize)
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                }
            }

            // Tiles dropped on the board and not yet confirmed: drawn like
            // the opener's ghost, because that is what they are — letters
            // the ✓ will land — and green or red by the same rule.
            ForEach(Array(scene.staged.keys.sorted()), id: \.self) { key in
                let rect = metrics.rect(of: parseKey(key))
                PreviewTileView(
                    letter: scene.staged[key], isGood: scene.stagedIsGood,
                    cellSize: metrics.cellSize)
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
                    .accessibilityElement()
                    .accessibilityLabel(
                        "\(scene.staged[key]?.uppercased() ?? ""), not yet placed, tap to take back")
                    .accessibilityAddTraits(.isButton)
            }

            // The aimed word, drawn solid and over the placed tiles: the
            // borrowed letter is part of the word being aimed, so it has to
            // change colour with the rest of it.
            if let aim = scene.aim {
                ForEach(Array(aim.keys.sorted()), id: \.self) { key in
                    let rect = metrics.rect(of: parseKey(key))
                    AimTileView(
                        letter: aim[key] ?? "", isGood: scene.aimIsGood,
                        cellSize: metrics.cellSize)
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                }
                .accessibilityHidden(true)
            }
        }
        .frame(width: metrics.contentSize.width, height: metrics.contentSize.height)
        .background(Palette.bg)
    }

    static func cornerRadius(for cellSize: Double) -> Double {
        max(2, cellSize * 0.1)
    }

    /// A zone's edge: thin, but never so thin it vanishes zoomed out.
    static func zoneEdgeWidth(for cellSize: Double) -> Double {
        max(1.5, cellSize * 0.06)
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
        if let owner = scene.owners[key] {
            parts.append(owner == scene.viewerSeat ? "yours" : "a rival’s")
        }
        if scene.zones.contains(where: { $0.contains(cell) }) {
            parts.append("worth double")
        }
        parts.append("tap to place your word through it")
        return parts.joined(separator: ", ")
    }
}

/// A placed tile. Every word on the board got there by reading, so a placed
/// tile is always a correct one — and wears the green that says so, unless
/// it's a rival's on an Occupy board.
struct BoardTileView: View {
    var letter: String
    var cellSize: Double
    var colors: SeatColors? = nil

    var body: some View {
        RoundedRectangle(
            cornerRadius: BoardContentView.cornerRadius(for: cellSize), style: .continuous
        )
        .fill(colors?.fill ?? Palette.accentBg)
        .overlay(
            Text(letter.uppercased())
                .font(.system(size: cellSize * 0.56, weight: .bold))
                .foregroundStyle(colors?.ink ?? Palette.accent)
        )
    }
}

/// A letter of the word being aimed by press-and-hold: solid, so it reads as
/// a word sitting on the board rather than a hint about one. Green when it's
/// good to land, red when it isn't.
struct AimTileView: View {
    var letter: String
    var isGood: Bool
    var cellSize: Double

    var body: some View {
        RoundedRectangle(
            cornerRadius: BoardContentView.cornerRadius(for: cellSize), style: .continuous
        )
        .fill(isGood ? Palette.accentRaised : Palette.badBg)
        .overlay(
            Text(letter.uppercased())
                .font(.system(size: cellSize * 0.56, weight: .bold))
                .foregroundStyle(isGood ? Palette.accent : Palette.badInk)
        )
    }
}

/// A ghost of a letter that would land — dashed and translucent, and in the
/// same green or red the word row is wearing.
struct PreviewTileView: View {
    var letter: String?
    var isGood = true
    var cellSize: Double

    var body: some View {
        let radius = BoardContentView.cornerRadius(for: cellSize)
        let fill = isGood ? Palette.accentBg : Palette.badBg
        let ink = isGood ? Palette.accent : Palette.badInk
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(fill.opacity(0.45))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(
                        ink.opacity(0.7),
                        style: StrokeStyle(lineWidth: max(1, cellSize * 0.06), dash: [4, 3]))
            )
            .overlay {
                if let letter {
                    Text(letter.uppercased())
                        .font(.system(size: cellSize * 0.56, weight: .bold))
                        .foregroundStyle(ink.opacity(0.7))
                }
            }
    }
}
