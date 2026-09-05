import SwiftUI
import WordBoard
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
    /// Occupy: the match clock, and the stall countdown when one is running,
    /// in place of the deal. Nothing lands from a clock there.
    var clock: HeaderClock?
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

            if let clock {
                Text(clock.text)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(clock.stallSeconds == nil ? Palette.inkSoft : Palette.gaugeWarn)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .accessibilityLabel(clock.spoken)
            } else if let secondsToTiles {
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

/// Occupy's header clock: the match clock, or — once the board has been
/// quiet long enough for the stall rule to be close — how long until that
/// ends it, so the ending is never a surprise.
struct HeaderClock: Equatable {
    var secondsLeft: Int
    var stallSeconds: Int?

    var text: String {
        if let stallSeconds { return "Stuck? Ends in \(stallSeconds)s" }
        return formatSeconds(Double(secondsLeft))
    }

    var spoken: String {
        if let stallSeconds { return "Nobody has placed a word; the game ends in \(stallSeconds) seconds" }
        return "\(secondsLeft) seconds left"
    }
}

/// Occupy's balanced bar, in place of the pile gauge: everyone's share of
/// the value on the board, in one strip — yours first, in green, then each
/// rival in their colour — with everyone's points spelled out under it in
/// the same colours. The divider says who's ahead; the numbers say by how
/// much.
struct OccupyBarView: View {
    struct Segment: Identifiable, Equatable {
        var id: Int
        var name: String
        var value: Int
        var colors: SeatColors
    }

    var segments: [Segment]

    var body: some View {
        VStack(spacing: 5) {
            bar
            points
        }
        .animation(.easeOut(duration: 0.25), value: segments)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Board held")
        .accessibilityValue(
            segments.map { "\($0.name) \($0.value)" }.joined(separator: ", "))
    }

    private var bar: some View {
        let total = max(1, segments.reduce(0) { $0 + $1.value })
        return GeometryReader { proxy in
            HStack(spacing: 0) {
                ForEach(segments) { segment in
                    Rectangle()
                        .fill(segment.colors.ink)
                        .frame(width: proxy.size.width * Double(segment.value) / Double(total))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.surface)
            .overlay {
                // The half-way mark, so a two-player game reads as ahead or
                // behind at a glance.
                if segments.count == 2 {
                    Rectangle()
                        .fill(Palette.bg)
                        .frame(width: 2)
                }
            }
        }
        .frame(height: 10)
        .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
    }

    /// Each player's name and value, spread across the width in the order
    /// of the bar above, so the same colour reads as the same person twice.
    private var points: some View {
        HStack(spacing: Spacing.gap) {
            ForEach(segments) { segment in
                HStack(spacing: 4) {
                    Text(segment.name.uppercased())
                        .font(.system(size: 11, weight: .bold))
                        .tracking(0.8)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .foregroundStyle(segment.colors.ink.opacity(0.8))
                    Text("\(segment.value)")
                        .font(.system(size: 13, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(segment.colors.ink)
                        .layoutPriority(1)
                }
                if segment.id != segments.last?.id {
                    Spacer(minLength: 0)
                }
            }
        }
        .frame(maxWidth: .infinity)
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

/// The word being built, on one line, in a colour that answers the only
/// question about it: is this a word?
///
/// It never wraps. Up to eight letters the tiles are the pile's own size;
/// past that every tile narrows so the whole word stays on one line — a word
/// broken across two rows stops looking like a word. The row keeps a tile's
/// height whatever it holds, so the board above it doesn't resize as letters
/// are picked.
///
/// Tapping a tile takes that letter back out.
struct WordRowView: View {
    var picks: [Pick]
    /// Green when it reads, red when it doesn't, and the plain word colour
    /// while there is still too little of it to judge.
    var verdict: WordVerdict
    /// The tile size the row would like — the pile's, so a short word looks
    /// like the tiles it was built from.
    var tileSize: CGFloat
    /// The full width the row has to lay a word out across.
    var width: CGFloat
    var onRemove: (Int) -> Void

    var body: some View {
        let layout = Spacing.wordRow(count: picks.count, fitting: width, cap: tileSize)
        HStack(spacing: layout.gap) {
            ForEach(Array(picks.enumerated()), id: \.offset) { position, pick in
                Button {
                    onRemove(position)
                } label: {
                    if let letter = pick.letter {
                        LetterTile(text: letter, style: style, size: layout.size)
                    } else {
                        GapTile(size: layout.size, isBad: verdict == .bad)
                    }
                }
                .buttonStyle(PressedTileStyle())
                .accessibilityLabel(
                    pick.letter.map { "Remove \($0.uppercased())" } ?? "Remove gap")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: tileSize)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Your word")
        .accessibilityValue(spoken)
    }

    private var style: TileStyle { verdict == .bad ? .bad : .accent }

    private var spoken: String {
        guard !picks.isEmpty else { return "Empty" }
        let letters = picks.map { $0.letter?.uppercased() ?? "gap" }.joined(separator: " ")
        switch verdict {
        case .good: return "\(letters), a word"
        case .bad: return "\(letters), not a word"
        case .unjudged: return letters
        }
    }
}

/// A gap in the word: the square that will sit on a board letter.
struct GapTile: View {
    var size: CGFloat
    /// Red with the rest of the word when no letter on the board would make
    /// one of it.
    var isBad = false

    var body: some View {
        let style: TileStyle = isBad ? .bad : .accent
        RoundedRectangle(cornerRadius: Spacing.tileRadius, style: .continuous)
            .fill(style.fill)
            .overlay(
                Image(systemName: "square.dashed")
                    .font(.system(size: size * 0.5, weight: .bold))
                    .foregroundStyle(style.ink))
            .frame(width: size, height: size)
    }
}

/// The pile: three rows of eight, always drawn in full — twenty-four slots,
/// which is the limit, so the field you see is the danger you're in. Letters
/// fill the slots from the top left; a picked letter lifts to the lighter
/// grey, and a letter dragged onto the board leaves its slot empty until it
/// comes back or lands.
///
/// A tap claims a letter for the word; a drag carries it to the board. Both
/// come through the one pointer pipeline (`dispatch`) so the slop that tells
/// them apart is the board's own — and, like the board, through one
/// transparent input plane over the whole grid rather than a surface per
/// tile: the tile under the finger empties the moment it lifts, and a
/// gesture that lived on that tile would die with it and never report its
/// release. Without a pipeline — previews, layout tests — the tiles are
/// plain buttons.
struct PileView: View {
    var letters: [String]
    var picked: Set<Int>
    /// Tiles sitting on the board, not yet confirmed: their slots are empty.
    var staged: Set<Int> = []
    /// The tile riding under the finger right now, hidden in its slot.
    var hidden: Int? = nil
    var tileSize: CGFloat
    var onTap: (Int) -> Void
    /// The unified pointer pipeline, when there is one to feed.
    var dispatch: ((GestureMachine.Event) -> Void)? = nil
    var context: () -> GestureMachine.Context = { .init() }

    /// The grid's frame in the game's coordinate space — the space the
    /// pipeline reports presses in — so a press can be turned back into a
    /// slot.
    @State private var gridFrame: CGRect = .zero

    var body: some View {
        let columns = Spacing.columns
        VStack(spacing: Spacing.tileGap) {
            ForEach(0..<Spacing.pileRows, id: \.self) { row in
                HStack(spacing: Spacing.tileGap) {
                    ForEach(0..<columns, id: \.self) { column in
                        let index = row * columns + column
                        if index < letters.count, index != hidden, !staged.contains(index) {
                            tile(at: index)
                        } else {
                            LetterTile(text: nil, style: .slot, size: tileSize)
                                .accessibilityHidden(true)
                        }
                    }
                }
            }
        }
        .overlay {
            // One input plane above every slot, as the board has above every
            // cell. It never goes away, so the gesture it starts always ends.
            if let dispatch {
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .pointerSurface(target: target(at:), context: context, dispatch: dispatch)
                    .accessibilityHidden(true)
            }
        }
        .onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .named(GameScreen.space))
        } action: { frame in
            gridFrame = frame
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Pile, \(letters.count) of \(PILE_LIMIT) tiles")
    }

    /// The press-time hit-test: the letter under the point, or nothing — an
    /// empty slot, a slot whose tile is out on the board, or the gap between
    /// tiles is inert.
    private func target(at point: CGPoint) -> GestureMachine.DownTarget? {
        guard let index = Self.slot(at: point, in: gridFrame, tileSize: tileSize),
            index < letters.count, index != hidden, !staged.contains(index)
        else { return nil }
        return .rackTile(index: index, letter: letters[index])
    }

    /// Which of the twenty-four slots a point falls in, given the grid's
    /// frame: the tile itself, not the gap after it. Pure, so it tests
    /// without a view.
    static func slot(at point: CGPoint, in frame: CGRect, tileSize: CGFloat) -> Int? {
        let pitch = tileSize + Spacing.tileGap
        let x = point.x - frame.minX
        let y = point.y - frame.minY
        guard x >= 0, y >= 0 else { return nil }
        let column = Int(x / pitch)
        let row = Int(y / pitch)
        guard column < Spacing.columns, row < Spacing.pileRows,
            x - CGFloat(column) * pitch < tileSize, y - CGFloat(row) * pitch < tileSize
        else { return nil }
        return row * Spacing.columns + column
    }

    @ViewBuilder
    private func tile(at index: Int) -> some View {
        let letter = letters[index]
        let isPicked = picked.contains(index)
        let face = LetterTile(text: letter, style: isPicked ? .raised : .dim, size: tileSize)
        Group {
            if dispatch != nil {
                // The input plane above takes the pointer; the tile is left
                // to draw, and to speak for itself to assistive tech.
                face
                    .accessibilityElement()
                    .accessibilityAction { onTap(index) }
            } else {
                Button {
                    onTap(index)
                } label: {
                    face
                }
                .buttonStyle(PressedTileStyle())
            }
        }
        .accessibilityLabel("\(letter.uppercased()), tile \(index + 1) of \(letters.count)")
        .accessibilityHint(
            isPicked
                ? "Takes this letter back out of your word"
                : "Adds this letter to your word, or drag it onto the board")
        .accessibilityAddTraits(isPicked ? [.isButton, .isSelected] : .isButton)
    }
}

/// A tile riding under the finger, above everything else on the screen: the
/// pile's own tile a touch bigger, with a shadow, so it reads as lifted.
struct GhostTileView: View {
    var letter: String
    /// The pile's tile size, so the tile doesn't change size in the hand.
    var size: CGFloat

    var body: some View {
        LetterTile(text: letter, style: .raised, size: size)
            .scaleEffect(1.1)
            .shadow(color: .black.opacity(0.45), radius: 8, x: 0, y: 4)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// Shuffle, standing on its own to the right of the pile and as tall as it.
///
/// Every other button acts on the word being built; this one only rearranges
/// the letters it is built from, so it sits with the pile rather than in the
/// row of word actions — where it was one indistinguishable icon in four, and
/// where a mis-tap cost a word instead of nothing.
struct PileShuffleButton: View {
    /// The pile's height, so the two read as one block.
    var height: CGFloat
    var disabled = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "repeat")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Palette.inkSoft)
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .background(
                    RoundedRectangle(cornerRadius: Spacing.tileRadius, style: .continuous)
                        .fill(Palette.surface))
                .contentShape(Rectangle())
        }
        .buttonStyle(PressedTileStyle())
        .disabled(disabled)
        .opacity(disabled ? 0.35 : 1)
        .accessibilityLabel("Shuffle the pile")
    }
}

/// One of the actions under the pile: an icon on a wide, short tile. The
/// accented one is solid green with a dark mark on it — the screen's one
/// "go", and the only place the bright green is a fill.
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
                .foregroundStyle(accent ? Palette.accentButtonInk : Palette.inkSoft)
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
