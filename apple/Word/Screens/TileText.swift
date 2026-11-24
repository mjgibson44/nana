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

/// A screen's own name, spelled a size up from the rows under it — TIMETILES
/// over the doors, SOLO over the questions, MENU over the items. A long title
/// on a narrow phone drops back to the ordinary tile size rather than running
/// off the edge.
struct TileTitle: View {
    var text: String
    var style: TileStyle = .accent

    var body: some View {
        ViewThatFits(in: .horizontal) {
            TileWord(text: text, style: style, size: Spacing.titleTile)
            TileWord(text: text, style: style, size: Spacing.tile)
        }
    }
}

/// The name at the top of a menu screen — TIMETILES, SOLO, DUEL, BATTLE —
/// set well above the rows under it, one tile word per line, with a wide
/// gap beneath so the name reads as the screen's and not as its first row.
/// Each line drops back a size, then to the ordinary tile, on a screen too
/// narrow to hold it.
struct ScreenHeader: View {
    var lines: [String]
    var style: TileStyle = .accent

    init(_ lines: String..., style: TileStyle = .accent) {
        self.lines = lines
        self.style = style
    }

    var body: some View {
        VStack(spacing: Spacing.tileGap) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                ViewThatFits(in: .horizontal) {
                    TileWord(text: line, style: style, size: Spacing.headerTile)
                    TileWord(text: line, style: style, size: Spacing.titleTile)
                    TileWord(text: line, style: style, size: Spacing.tile)
                }
            }
        }
        .padding(.bottom, Spacing.headerGap)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(lines.joined().capitalized)
        .accessibilityAddTraits(.isHeader)
    }
}

/// How a menu button is dressed.
enum MenuButtonStyle {
    /// The one thing the screen is for: PLAY, HOST, JOIN, START.
    case primary
    /// Everything else you can press.
    case secondary
    /// One of a set of choices, picked.
    case selected
    /// One of a set of choices, not picked.
    case unselected

    var fill: Color {
        switch self {
        case .primary: Palette.accentRaised
        case .selected: Palette.accentBg
        case .secondary: Palette.surface
        case .unselected: Palette.slot
        }
    }

    var ink: Color {
        switch self {
        case .primary, .selected: Palette.accent
        case .secondary: Palette.ink
        case .unselected: Palette.inkSoft
        }
    }

    var edge: Color {
        switch self {
        case .selected: Palette.accent.opacity(0.5)
        case .unselected: Palette.surface
        default: .clear
        }
    }
}

/// What a menu button looks like: a word, maybe a symbol in front of it, on
/// a plain rounded bar. Tiles are kept for the screen's name; the things you
/// press are these.
struct MenuButtonLabel: View {
    var title: String
    var systemImage: String? = nil
    var style: MenuButtonStyle = .secondary
    var width: CGFloat? = Spacing.menuButtonWidth

    var body: some View {
        HStack(spacing: 8) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .bold))
            }
            Text(title.uppercased())
                .font(.system(size: 16, weight: .bold))
                .tracking(1.5)
                .lineLimit(1)
        }
        .foregroundStyle(style.ink)
        .frame(maxWidth: width == nil ? .infinity : nil)
        .frame(width: width, height: Spacing.menuButtonHeight)
        .background(
            RoundedRectangle(cornerRadius: Spacing.menuButtonRadius, style: .continuous)
                .fill(style.fill))
        .overlay(
            RoundedRectangle(cornerRadius: Spacing.menuButtonRadius, style: .continuous)
                .strokeBorder(style.edge, lineWidth: 1))
        .contentShape(Rectangle())
    }
}

struct MenuButton: View {
    var title: String
    var systemImage: String? = nil
    var style: MenuButtonStyle = .secondary
    var width: CGFloat? = Spacing.menuButtonWidth
    var disabled = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            MenuButtonLabel(title: title, systemImage: systemImage, style: style, width: width)
        }
        .buttonStyle(PressedTileStyle())
        .disabled(disabled)
        .opacity(disabled ? 0.35 : 1)
        .accessibilityLabel(title.capitalized)
    }
}

/// A two-or-more-way choice as one control: a track with the options in it
/// and the picked one lit, sliding across as the pick changes.
struct MenuToggle<Value: Hashable>: View {
    var options: [(value: Value, title: String)]
    @Binding var selection: Value
    var width: CGFloat = Spacing.menuButtonWidth

    @Namespace private var thumb

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.value) { option in
                let isSelected = option.value == selection
                Button {
                    withAnimation(.snappy(duration: 0.2)) { selection = option.value }
                } label: {
                    Text(option.title.uppercased())
                        .font(.system(size: 15, weight: .bold))
                        .tracking(1.5)
                        .foregroundStyle(isSelected ? Palette.accent : Palette.inkSoft)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background {
                            if isSelected {
                                RoundedRectangle(
                                    cornerRadius: Spacing.menuButtonRadius - 4, style: .continuous
                                )
                                .fill(Palette.accentRaised)
                                .matchedGeometryEffect(id: "thumb", in: thumb)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option.title)
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(4)
        .frame(width: width, height: Spacing.menuButtonHeight)
        .background(
            RoundedRectangle(cornerRadius: Spacing.menuButtonRadius, style: .continuous)
                .fill(Palette.surface))
    }
}

/// BACK, pinned to the bottom of every menu screen so the way out is always
/// in the same place.
struct BackBar: View {
    var text: String = "BACK"
    var action: () -> Void

    var body: some View {
        MenuButton(title: text, systemImage: "chevron.left", action: action)
    }
}

/// The foot of a menu screen: the screen's main action, when it has one,
/// right above BACK — both where a thumb already is.
struct MenuFooter<Primary: View>: View {
    var onBack: () -> Void
    @ViewBuilder var primary: Primary

    var body: some View {
        VStack(spacing: Spacing.menuButtonGap) {
            primary
            BackBar(action: onBack)
        }
    }
}

extension MenuFooter where Primary == EmptyView {
    init(onBack: @escaping () -> Void) {
        self.init(onBack: onBack) { EmptyView() }
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

/// A block of tile rows on the results, menu and overlay screens: every row
/// centred on the same middle line, and the block as a whole centred on the
/// screen. Rows are different lengths — GAME END over a two-digit score over
/// SEE GAME — and a shared left edge left the short ones looking dropped to
/// one side of a screen with nothing else on it.
struct TileBlock<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: Spacing.tileGap) {
            content
        }
        .fixedSize(horizontal: true, vertical: false)
    }
}
