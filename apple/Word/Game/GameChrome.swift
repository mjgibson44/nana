import SwiftUI
import WordCore

/// The top of the game screen: the score (or, in a battle, the placing), what
/// the clock is about to hand you, and the two controls — pause and the menu.
struct GameHeaderView: View {
    /// "4444" in Solo, "1st" in Battle.
    var headline: String
    var headlineLabel: String
    /// Seconds until the next batch lands; nil when no clock is running.
    var secondsToTiles: Int?
    /// How many tiles that batch brings. The count and the clock are one
    /// sentence — "5 tiles in 24s" — because they only mean anything together:
    /// twenty seconds is nothing to fear or everything, depending.
    var tilesComing: Int?
    /// Nil hides the pause button — a battle can't be paused, and neither can
    /// a game that's already over.
    var onPause: (() -> Void)?
    var onMenu: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 5) {
                Image(systemName: "rosette")
                    .font(.system(size: 22, weight: .semibold))
                Text(headline)
                    .font(.system(size: 26, weight: .bold))
                    .monospacedDigit()
            }
            .foregroundStyle(Palette.ink)
            .fixedSize()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(headlineLabel)

            if let secondsToTiles {
                Text(Self.dealText(tiles: tilesComing, seconds: secondsToTiles))
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Palette.inkSoft)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .accessibilityLabel(
                        Self.dealSpoken(tiles: tilesComing, seconds: secondsToTiles))
            }

            Spacer(minLength: 4)

            if let onPause {
                headerButton(
                    systemImage: "pause.fill", label: "Pause the game", action: onPause)
            }
            headerButton(systemImage: "line.3.horizontal", label: "Game menu", action: onMenu)
        }
        .frame(height: 30)
    }

    /// The two controls in the corner, sized and dressed like the actions
    /// under the pile so the whole screen reads as one set of buttons.
    private func headerButton(
        systemImage: String, label: String, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Palette.inkSoft)
                .frame(width: 30, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: Spacing.tileRadius, style: .continuous)
                        .fill(Palette.surface))
                .contentShape(Rectangle())
        }
        .buttonStyle(PressedTileStyle())
        .accessibilityLabel(label)
    }

    /// "5 tiles in 24s" — and just the clock when the batch size isn't known.
    static func dealText(tiles: Int?, seconds: Int) -> String {
        guard let tiles else { return "Tiles in \(clockText(seconds))" }
        return "\(tiles) tile\(tiles == 1 ? "" : "s") in \(clockText(seconds))"
    }

    static func dealSpoken(tiles: Int?, seconds: Int) -> String {
        guard let tiles else { return "Next tiles in \(seconds) seconds" }
        return "\(tiles) more tile\(tiles == 1 ? "" : "s") in \(seconds) seconds"
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

    private var fill: Color { RivalGaugesView.fill(tone) }
    private var track: Color { RivalGaugesView.track(tone) }
}

/// Everyone else's pile, in one row of small bars under your own.
///
/// A battle is a race to *not* fill up, so a rival's pile is the only thing
/// worth watching about them — and it's the same measure as the gauge above,
/// drawn small enough that eight of them fit the width of one. A player who's
/// out reads as a full red bar: buried is what a full pile means.
struct RivalGaugesView: View {
    struct Rival: Identifiable, Equatable {
        var id: String
        var name: String
        var tiles: Int
        /// Buried, or gone. Either way they're not in the race any more.
        var isOut: Bool
    }

    var rivals: [Rival]
    var limit: Int = PILE_LIMIT

    var body: some View {
        HStack(spacing: Spacing.tileGap) {
            ForEach(rivals) { rival in
                bar(for: rival)
            }
        }
        .frame(height: 5)
        .animation(.easeOut(duration: 0.25), value: rivals)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Rivals’ piles")
    }

    private func bar(for rival: Rival) -> some View {
        let tone = rival.isOut ? PileTone.urgent : pileTone(rival.tiles)
        let fraction =
            rival.isOut ? 1 : min(1, max(0, Double(rival.tiles) / Double(max(1, limit))))
        return GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Rectangle().fill(Self.track(tone))
                Rectangle().fill(Self.fill(tone))
                    .frame(width: proxy.size.width * fraction)
            }
        }
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
        .opacity(rival.isOut ? 0.5 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(rival.name)
        .accessibilityValue(rival.isOut ? "out" : "\(rival.tiles) of \(limit) tiles")
    }

    /// The same thresholds the model applies to your own pile, so a rival's
    /// bar and yours never mean different things at the same colour.
    private func pileTone(_ tiles: Int) -> PileTone {
        if tiles >= PILE_URGENT { return .urgent }
        if tiles >= PILE_WARN { return .warn }
        return .ok
    }

    static func fill(_ tone: PileTone) -> Color {
        switch tone {
        case .ok: Palette.gaugeOk
        case .warn: Palette.gaugeWarn
        case .urgent: Palette.gaugeBad
        }
    }

    static func track(_ tone: PileTone) -> Color {
        switch tone {
        case .ok: Palette.gaugeOkTrack
        case .warn: Palette.gaugeWarnTrack
        case .urgent: Palette.gaugeBadTrack
        }
    }
}

/// The word being built, in amber tiles, `Spacing.columns` to a row. Tapping
/// a tile takes that letter back out.
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

/// The pile: three rows of eight, always drawn in full — twenty-four slots,
/// which is the limit, so the field you see is the danger you're in. Letters
/// fill the slots from the top left; a picked letter lifts to the lighter grey.
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
