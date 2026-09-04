import SwiftUI

/// How a tile is dressed. The game has exactly these looks, and every screen
/// — home, board, pile, results — is built from them.
enum TileStyle {
    /// A word: green on dark green.
    case accent
    /// A word that isn't one: red on dark red.
    case bad
    /// A tile-word button: the same green, a step brighter behind it.
    case accentButton
    /// A neutral tile: light letter on dark grey.
    case plain
    /// A neutral tile that's been picked out.
    case raised
    /// A dim neutral tile: an idle pile letter.
    case dim
    /// An empty slot.
    case slot

    var fill: Color {
        switch self {
        case .accent: Palette.accentBg
        case .bad: Palette.badBg
        case .accentButton: Palette.accentRaised
        case .plain, .dim: Palette.surface
        case .raised: Palette.surfaceRaised
        case .slot: Palette.slot
        }
    }

    var ink: Color {
        switch self {
        case .accent, .accentButton: Palette.accent
        case .bad: Palette.badInk
        case .plain, .raised: Palette.ink
        case .dim: Palette.inkSoft
        case .slot: .clear
        }
    }
}

/// One square tile with a letter (or digit, or nothing) on it.
struct LetterTile: View {
    var text: String?
    var style: TileStyle
    var size: CGFloat = Spacing.tile
    /// Letters are set a little smaller than digits or short words look
    /// right at; the caller says which.
    var fontScale: CGFloat = 0.56

    var body: some View {
        RoundedRectangle(cornerRadius: Spacing.tileRadius, style: .continuous)
            .fill(style.fill)
            .overlay {
                if let text, !text.isEmpty {
                    // Every letter in the game is set in capitals, whatever
                    // case the model keeps it in.
                    Text(text.uppercased())
                        .font(.system(size: size * fontScale, weight: .bold))
                        .foregroundStyle(style.ink)
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                }
            }
            .frame(width: size, height: size)
    }
}

/// A word spelled out in tiles. A space is a blank slot — nothing drawn, one
/// tile's width kept — which is how "GAME END" and "SEE GAME" keep their
/// spacing on the grid.
struct TileWord: View {
    var text: String
    var style: TileStyle = .plain
    var size: CGFloat = Spacing.tile

    var body: some View {
        HStack(spacing: Spacing.tileGap) {
            ForEach(Array(text.uppercased().enumerated()), id: \.offset) { _, character in
                if character == " " {
                    Color.clear.frame(width: size, height: size)
                } else {
                    LetterTile(text: String(character), style: style, size: size)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }
}

/// A word in tiles that does something when pressed. The whole row is the
/// target, blanks included.
struct TileWordButton: View {
    var text: String
    var style: TileStyle = .plain
    var size: CGFloat = Spacing.tile
    var disabled = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            TileWord(text: text, style: style, size: size)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressedTileStyle())
        .disabled(disabled)
        .opacity(disabled ? 0.35 : 1)
        .accessibilityLabel(text.capitalized)
        .accessibilityAddTraits(.isButton)
    }
}

/// A tile two rows tall and two wide: the results screen's score digits and
/// the battle placing.
struct BigTile: View {
    var text: String
    var style: TileStyle = .accent
    var unit: CGFloat = Spacing.tile

    static func size(unit: CGFloat) -> CGFloat { unit * 2 + Spacing.tileGap }

    var body: some View {
        LetterTile(text: text, style: style, size: Self.size(unit: unit), fontScale: 0.5)
    }
}

/// Buttons here don't change colour on press: they sink a little and dim.
struct PressedTileStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .offset(y: configuration.isPressed ? 1 : 0)
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

/// True while a screen is being drawn by `ImageRenderer` (snapshot tests),
/// which can't draw platform views: the board's input bridge and the system
/// menu step aside so the rest of the screen can be looked at.
private struct SnapshotRenderingKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var snapshotRendering: Bool {
        get { self[SnapshotRenderingKey.self] }
        set { self[SnapshotRenderingKey.self] = newValue }
    }
}

/// A section heading on a results or lobby screen: small, spaced, quiet.
struct SectionLabel: View {
    var text: String

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 12, weight: .bold))
            .tracking(1.4)
            .foregroundStyle(Palette.inkSoft)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A full-height column with the game's margins, centred and capped on wide
/// screens. Every screen sits in one.
struct ScreenColumn<Content: View>: View {
    var alignment: HorizontalAlignment = .center
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: alignment, spacing: Spacing.gap) {
            content
        }
        .frame(maxWidth: Spacing.maxWidth)
        .padding(Spacing.margin)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.bg)
    }
}

/// A block of tile rows on the results and lobby screens: each row starts at
/// the same left edge, and the block as a whole is centred on the screen —
/// the layout every mockup shares.
struct TileBlock<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.tileGap) {
            content
        }
        .fixedSize(horizontal: true, vertical: false)
    }
}
