import SwiftUI
import WordCore

/// The top of the game screen: the score (or, in a battle, the placing), the
/// clock to the next tiles, and the menu.
struct GameHeaderView<MenuItems: View>: View {
    /// "4444" in Solo, "1st" in Battle.
    var headline: String
    var headlineLabel: String
    /// Seconds until the next batch lands; nil when no clock is running.
    var secondsToTiles: Int?
    @ViewBuilder var menuItems: MenuItems

    @Environment(\.snapshotRendering) private var snapshotRendering

    var body: some View {
        HStack(spacing: 16) {
            HStack(spacing: 5) {
                Image(systemName: "rosette")
                    .font(.system(size: 22, weight: .semibold))
                Text(headline)
                    .font(.system(size: 26, weight: .bold))
                    .monospacedDigit()
            }
            .foregroundStyle(Palette.ink)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(headlineLabel)

            if let secondsToTiles {
                (Text("Tiles in ").foregroundStyle(Palette.inkSoft)
                    + Text(Self.clockText(secondsToTiles)).foregroundStyle(Palette.ink).bold())
                    .font(.system(size: 20, weight: .medium))
                    .monospacedDigit()
                    .lineLimit(1)
                    .accessibilityLabel("Next tiles in \(secondsToTiles) seconds")
            }

            Spacer(minLength: 8)

            if snapshotRendering {
                menuLabel
            } else {
                Menu {
                    menuItems
                } label: {
                    menuLabel
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .accessibilityLabel("Game menu")
            }
        }
        .frame(height: 30)
    }

    private var menuLabel: some View {
        Image(systemName: "line.3.horizontal")
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(Palette.inkSoft)
            .frame(width: 30, height: 30)
            .background(
                RoundedRectangle(cornerRadius: Spacing.tileRadius, style: .continuous)
                    .fill(Palette.surface))
            .contentShape(Rectangle())
    }

    /// Under a minute reads as "14s"; past it, "1:45".
    static func clockText(_ seconds: Int) -> String {
        seconds < 60 ? "\(seconds)s" : formatSeconds(Double(seconds))
    }
}

/// The pile gauge: how full the pile is against the limit, in a colour that
/// says how worried to be. Replaces the web's pulsing board frame.
struct PileGaugeView: View {
    var count: Int
    var limit: Int = PILE_LIMIT
    var tone: PileTone

    var body: some View {
        let fraction = min(1, max(0, Double(count) / Double(max(1, limit))))
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Rectangle().fill(track)
                Rectangle().fill(fill)
                    .frame(width: proxy.size.width * fraction)
            }
        }
        .frame(height: 10)
        .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
        .animation(.easeOut(duration: 0.25), value: count)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Pile")
        .accessibilityValue("\(count) of \(limit) tiles")
    }

    private var fill: Color {
        switch tone {
        case .ok: Palette.gaugeOk
        case .warn: Palette.gaugeWarn
        case .urgent: Palette.gaugeBad
        }
    }

    private var track: Color {
        switch tone {
        case .ok: Palette.gaugeOkTrack
        case .warn: Palette.gaugeWarnTrack
        case .urgent: Palette.gaugeBadTrack
        }
    }
}

/// The word being built, in amber tiles, ten to a row. Tapping a tile takes
/// that letter back out.
struct WordRowView: View {
    var picks: [Pick]
    var tileSize: CGFloat
    var onRemove: (Int) -> Void

    var body: some View {
        let columns = Spacing.columns
        let rows = max(1, (picks.count + columns - 1) / columns)
        VStack(spacing: Spacing.tileGap) {
            ForEach(0..<rows, id: \.self) { row in
                HStack(spacing: Spacing.tileGap) {
                    ForEach(0..<columns, id: \.self) { column in
                        let position = row * columns + column
                        if position < picks.count {
                            let pick = picks[position]
                            Button {
                                onRemove(position)
                            } label: {
                                if let letter = pick.letter {
                                    LetterTile(text: letter, style: .accent, size: tileSize)
                                } else {
                                    GapTile(size: tileSize)
                                }
                            }
                            .buttonStyle(PressedTileStyle())
                            .accessibilityLabel(
                                pick.letter.map { "Remove \($0.uppercased())" } ?? "Remove gap")
                        } else {
                            Color.clear.frame(width: tileSize, height: tileSize)
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Your word")
        .accessibilityValue(
            picks.isEmpty
                ? "Empty"
                : picks.map { $0.letter?.uppercased() ?? "gap" }.joined(separator: " "))
    }
}

/// A gap in the word: the square that will sit on a board letter.
struct GapTile: View {
    var size: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: Spacing.tileRadius, style: .continuous)
            .fill(Palette.accentBg)
            .overlay(
                Image(systemName: "square.dashed")
                    .font(.system(size: size * 0.5, weight: .bold))
                    .foregroundStyle(Palette.accent))
            .frame(width: size, height: size)
    }
}

/// The pile: three rows of ten, always drawn in full. Letters fill the slots
/// from the top left; a picked letter lifts to the lighter grey.
struct PileView: View {
    var letters: [String]
    var picked: Set<Int>
    var tileSize: CGFloat
    var onTap: (Int) -> Void

    var body: some View {
        let columns = Spacing.columns
        VStack(spacing: Spacing.tileGap) {
            ForEach(0..<Spacing.pileRows, id: \.self) { row in
                HStack(spacing: Spacing.tileGap) {
                    ForEach(0..<columns, id: \.self) { column in
                        let index = row * columns + column
                        if index < letters.count {
                            let isPicked = picked.contains(index)
                            Button {
                                onTap(index)
                            } label: {
                                LetterTile(
                                    text: letters[index], style: isPicked ? .raised : .dim,
                                    size: tileSize)
                            }
                            .buttonStyle(PressedTileStyle())
                            .accessibilityLabel(
                                "\(letters[index].uppercased()), tile \(index + 1) of \(letters.count)")
                            .accessibilityHint(
                                isPicked
                                    ? "Takes this letter back out of your word"
                                    : "Adds this letter to your word")
                            .accessibilityAddTraits(isPicked ? [.isButton, .isSelected] : .isButton)
                        } else {
                            LetterTile(text: nil, style: .slot, size: tileSize)
                                .accessibilityHidden(true)
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Pile, \(letters.count) of \(PILE_LIMIT) tiles")
    }
}

/// One of the four actions under the pile: an icon on a wide, short tile.
struct ActionButton: View {
    var systemImage: String
    var label: String
    var accent = false
    var disabled = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(accent ? Palette.accent : Palette.inkSoft)
                .frame(maxWidth: .infinity)
                .frame(height: Spacing.buttonHeight)
                .background(
                    RoundedRectangle(cornerRadius: Spacing.tileRadius, style: .continuous)
                        .fill(accent ? Palette.accentButton : Palette.surface))
                .contentShape(Rectangle())
        }
        .buttonStyle(PressedTileStyle())
        .disabled(disabled)
        .opacity(disabled ? 0.35 : 1)
        .accessibilityLabel(label)
    }
}
