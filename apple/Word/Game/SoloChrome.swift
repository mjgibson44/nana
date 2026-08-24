import SwiftUI
import WordCore

struct SoloHeaderView: View {
    var score: Int
    var complete: Bool
    var seconds: Int?
    var timerLabel: String
    var looseTiles: Int?
    /// The Daily Deal's counterpart to the loose gauge: a fixed deal, so what
    /// matters is how many letters are still unplaced.
    var tilesLeft: Int?
    var gaugeTone: SoloGaugeTone
    var bonusEarned: Bool
    var canPause: Bool
    var onPause: () -> Void
    var onNewDeal: () -> Void
    var onShowSummary: () -> Void
    var pace: SoloPace
    var onChoosePace: (SoloPace) -> Void
    var onShowSettings: () -> Void = {}
    var onReturnHome: () -> Void = {}
    /// Hand today's board in. Non-nil only for the Daily Deal.
    var onFinish: (() -> Void)?
    /// One attempt a day means a finished daily offers no way to start over.
    var allowsReplay = true

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        HStack(spacing: 14) {
            scoreBlock(
                label: complete ? "Final score" : "Score",
                value: "\(score)", tone: Ink.ink)

            if let seconds {
                scoreBlock(
                    label: timerLabel,
                    value: formatSeconds(Double(seconds)),
                    tone: gaugeTone == .over ? Ink.badInk : Ink.ink,
                    pulses: gaugeTone == .over,
                    urgent: true)
                    .accessibilityLabel("\(timerLabel), \(seconds) seconds")
            }

            if let looseTiles {
                let over = looseTiles - ENDLESS_LOOSE_LIMIT
                scoreBlock(
                    label: over > 0 ? "Limit exceeded" : "Loose tiles",
                    value: over > 0 ? "+\(over)" : "\(looseTiles)/\(ENDLESS_LOOSE_LIMIT)",
                    tone: gaugeColor,
                    // Endless's near-limit count is steady orange; the board
                    // frame carries the pulse until the count goes over.
                    pulses: gaugeTone == .over,
                    urgent: gaugeTone == .over)
                    .accessibilityLabel(
                        over > 0
                            ? "\(looseTiles) loose tiles, \(over) over the limit"
                            : "\(looseTiles) of \(ENDLESS_LOOSE_LIMIT) loose tiles")
            }

            if let tilesLeft {
                scoreBlock(
                    label: tilesLeft == 0 ? "All placed" : "Tiles left",
                    value: "\(tilesLeft)",
                    tone: tilesLeft == 0 ? Ink.okInk : Ink.ink)
                    .accessibilityLabel(
                        tilesLeft == 0
                            ? "Every tile placed"
                            : "\(tilesLeft) tile\(tilesLeft == 1 ? "" : "s") left")
            }

            if bonusEarned && !complete && horizontalSizeClass != .compact {
                Text("+\(ENDLESS_CONNECT_BONUS) all tiles")
                    .font(.caption.bold())
                    .foregroundStyle(Ink.okInk)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Ink.okBg))
                    .accessibilityLabel("All tiles bonus, \(ENDLESS_CONNECT_BONUS) points")
            }

            Spacer(minLength: 4)

            if complete {
                if allowsReplay {
                    Button("Play again", action: onNewDeal)
                        .buttonStyle(InkActionButtonStyle(primary: true))
                } else {
                    Button("Results", action: onShowSummary)
                        .buttonStyle(InkActionButtonStyle(primary: true))
                }
            } else if let onFinish {
                Button("Finish", action: onFinish)
                    .buttonStyle(InkActionButtonStyle(primary: true))
            } else if canPause {
                Button(action: onPause) {
                    Image(systemName: "pause.fill")
                        .frame(width: 34, height: 30)
                }
                .buttonStyle(InkActionButtonStyle())
                .accessibilityLabel("Pause game")
            }

            Menu {
                if complete {
                    Button("Game summary", action: onShowSummary)
                }
                Button("New deal", action: onNewDeal)
                Section("Speed") {
                    Button {
                        onChoosePace(.regular)
                    } label: {
                        if pace == .regular {
                            Label("Regular", systemImage: "checkmark")
                        } else {
                            Text("Regular")
                        }
                    }
                    Button {
                        onChoosePace(.fast)
                    } label: {
                        if pace == .fast {
                            Label("Fast", systemImage: "checkmark")
                        } else {
                            Text("Fast")
                        }
                    }
                }
                Divider()
                Button("Settings", action: onShowSettings)
                Button("Return home", action: onReturnHome)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 17, weight: .bold))
                    .frame(width: 34, height: 30)
            }
            .menuStyle(.borderlessButton)
            .accessibilityLabel("Game menu")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Ink.surface)
    }

    private var gaugeColor: Color {
        switch gaugeTone {
        case .ok: Ink.okInk
        case .warn: Ink.warnInk
        case .over: Ink.badInk
        }
    }

    private func scoreBlock(
        label: String,
        value: String,
        tone: Color,
        pulses: Bool = false,
        urgent: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .bold))
                .tracking(0.7)
                .foregroundStyle(Ink.ink.opacity(0.6))
            Text(value)
                .font(.system(size: 20, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(tone)
                .alarmPulse(active: pulses, urgent: urgent)
        }
        .fixedSize()
    }
}

struct SoloSplashView: View {
    var splash: SoloSplash
    var pace: SoloPace
    var onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.42)
                .ignoresSafeArea()
            VStack(spacing: 5) {
                Text(paceName.uppercased())
                    .font(.caption.bold())
                    .tracking(1.1)
                    .foregroundStyle(Ink.ink.opacity(0.65))
                Text(title)
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .foregroundStyle(Ink.ink)
                Text(note)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(Ink.ink.opacity(0.72))
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 38)
            .padding(.vertical, 26)
            .background(RoundedRectangle(cornerRadius: 18).fill(Ink.surface))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Ink.ink, lineWidth: 3))
            .shadow(color: .black.opacity(0.28), radius: 20, y: 8)
            .padding(24)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onDismiss)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(named: "Dismiss", onDismiss)
    }

    private var paceName: String { PACE_NAMES[pace] ?? "Solo" }

    private var title: String {
        switch splash {
        case .start: "Game on!"
        case .speedUp: "Speeding up!"
        case .resumed: "Welcome back"
        }
    }

    private var note: String {
        switch splash {
        case .start:
            "\(ENDLESS_START_TILES) tiles · "
                + "\(formatSeconds(Double(endlessInitialSeconds(pace)))) to place them"
        case let .speedUp(seconds, tiles):
            "+\(tiles) tiles every \(formatSeconds(Double(seconds))) from here"
        case .resumed:
            "Your game is where you left it — the clock starts when you tap."
        }
    }
}

struct SoloPauseView: View {
    var pace: SoloPace
    var onResume: () -> Void

    @FocusState private var resumeFocused: Bool

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "pause.fill")
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(Ink.ink)
                .frame(width: 72, height: 72)
                .background(Circle().fill(Ink.surfaceAlt))
                .overlay(Circle().strokeBorder(Ink.ink, lineWidth: 3))
                .padding(.bottom, 8)
                .accessibilityHidden(true)
            Text((PACE_NAMES[pace] ?? "Solo").uppercased())
                .font(.caption.bold())
                .tracking(1.1)
                .foregroundStyle(Ink.ink.opacity(0.65))
            Text("Paused")
                .font(.system(size: 34, weight: .heavy, design: .rounded))
                .foregroundStyle(Ink.ink)
            Text("Every clock is stopped and the board is put away until you’re back.")
                .font(.callout.weight(.semibold))
                .foregroundStyle(Ink.ink.opacity(0.72))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            Button("Resume", action: onResume)
                .buttonStyle(InkActionButtonStyle(primary: true))
                .frame(minWidth: 180)
                .padding(.top, 16)
                .focused($resumeFocused)
                .keyboardShortcut(.cancelAction)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Ink.bg.ignoresSafeArea())
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .task { resumeFocused = true }
    }
}

struct SoloSummaryView: View {
    var words: [ScoredWord]
    var score: Int
    var onPlayAgain: () -> Void
    var onSeeBoard: () -> Void
    var scrollable = true
    /// Set for the Daily Deal, which ends by being handed in rather than lost
    /// — and can't be played again today.
    var daily: DailySummary?

    struct DailySummary: Equatable {
        var date: String
        var tilesLeft: Int
        var bonusEarned: Bool
        var streak: Int
    }

    @ViewBuilder
    var body: some View {
        if scrollable {
            ScrollView { report }
                .background(Ink.bg.ignoresSafeArea())
                .accessibilityAddTraits(.isModal)
        } else {
            report
                .background(Ink.bg)
        }
    }

    private var headline: String {
        guard let daily else { return "Buried in tiles!" }
        if daily.bonusEarned { return "Perfect — every tile placed!" }
        return daily.tilesLeft == 0 ? "All tiles down!" : "Handed in."
    }

    private var report: some View {
        VStack(spacing: 24) {
            VStack(spacing: 4) {
                Text(daily == nil ? "GAME OVER" : DAILY_DEAL_INFO.name.uppercased())
                    .font(.caption.bold())
                    .tracking(1.1)
                    .foregroundStyle(Ink.ink.opacity(0.65))
                Text(headline)
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                    .foregroundStyle(Ink.ink)
                if let daily {
                    Text(daily.date)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(Ink.ink.opacity(0.7))
                }
            }

            HStack(spacing: 10) {
                // One attempt a day: a finished daily has nothing to replay.
                if daily == nil {
                    Button("Play again", action: onPlayAgain)
                        .buttonStyle(InkActionButtonStyle(primary: true))
                }
                Button("See the board", action: onSeeBoard)
                    .buttonStyle(InkActionButtonStyle(primary: daily != nil))
            }

            HStack(spacing: 12) {
                summaryStat(value: "\(score)", label: "Final score")
                summaryStat(value: "\(words.count)", label: words.count == 1 ? "Word" : "Words")
                if let daily {
                    summaryStat(
                        value: "\(daily.tilesLeft)",
                        label: daily.tilesLeft == 1 ? "Tile left" : "Tiles left")
                    if daily.streak > 1 {
                        summaryStat(value: "\(daily.streak)", label: "Day streak")
                    }
                }
            }

            if !lengthCounts.isEmpty {
                summarySection("By length") {
                    FlowLayout(spacing: 8) {
                        ForEach(lengthCounts, id: \.length) { item in
                            Text("\(item.count)×  \(item.length)-letter")
                                .font(.callout.bold())
                                .padding(.horizontal, 13)
                                .padding(.vertical, 6)
                                .background(Capsule().fill(Ink.surfaceAlt))
                                .overlay(Capsule().strokeBorder(Ink.line, lineWidth: 2))
                        }
                    }
                }
            }

            summarySection("Your words") {
                if sortedWords.isEmpty {
                    Text("No words made it onto the board.")
                        .font(.callout)
                        .foregroundStyle(Ink.ink.opacity(0.7))
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    VStack(spacing: 5) {
                        ForEach(Array(sortedWords.enumerated()), id: \.offset) { _, word in
                            HStack {
                                Text(word.word.uppercased())
                                    .font(.body.bold())
                                    .tracking(0.8)
                                Spacer()
                                Text("+\(word.points)")
                                    .font(.caption.bold().monospacedDigit())
                                    .foregroundStyle(Ink.okInk)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 3)
                                    .background(Capsule().fill(Ink.okBg))
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(RoundedRectangle(cornerRadius: 10).fill(Ink.surface))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .strokeBorder(Ink.lineSoft, lineWidth: 2))
                        }
                    }
                }
            }
        }
        .frame(maxWidth: 560)
        .padding(.horizontal, 22)
        .padding(.vertical, 36)
        .frame(maxWidth: .infinity)
    }

    private var sortedWords: [ScoredWord] {
        words.sorted {
            $0.points == $1.points
                ? $0.word.localizedStandardCompare($1.word) == .orderedAscending
                : $0.points > $1.points
        }
    }

    private var lengthCounts: [(length: Int, count: Int)] {
        Dictionary(grouping: words, by: { $0.word.count })
            .map { (length: $0.key, count: $0.value.count) }
            .sorted { $0.length > $1.length }
    }

    private func summaryStat(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 34, weight: .heavy, design: .rounded))
                .monospacedDigit()
            Text(label.uppercased())
                .font(.system(size: 10, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(Ink.ink.opacity(0.65))
        }
        .frame(maxWidth: 190)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: 16).fill(Ink.surface))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Ink.ink, lineWidth: 3))
    }

    private func summarySection<Content: View>(
        _ title: String, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .bold))
                .tracking(0.9)
                .foregroundStyle(Ink.ink.opacity(0.6))
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A small wrapping layout for the summary's length chips.
private struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()
    ) -> CGSize {
        layout(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(
        in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()
    ) {
        let result = layout(proposal: proposal, subviews: subviews)
        for (index, point) in result.points.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y),
                proposal: .unspecified)
        }
    }

    private func layout(
        proposal: ProposedViewSize, subviews: Subviews
    ) -> (size: CGSize, points: [CGPoint]) {
        let width = proposal.width ?? .infinity
        var points: [CGPoint] = []
        var cursor = CGPoint.zero
        var rowHeight: CGFloat = 0
        var usedWidth: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if cursor.x > 0, cursor.x + size.width > width {
                cursor.x = 0
                cursor.y += rowHeight + spacing
                rowHeight = 0
            }
            points.append(cursor)
            cursor.x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            usedWidth = max(usedWidth, cursor.x - spacing)
        }
        return (CGSize(width: min(width, usedWidth), height: cursor.y + rowHeight), points)
    }
}

struct InkActionButtonStyle: ButtonStyle {
    var primary = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.bold())
            .foregroundStyle(primary ? Ink.inkInvert : Ink.ink)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 9)
                    .fill(primary ? Ink.ink : Ink.surface))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Ink.ink, lineWidth: 2))
            .offset(y: configuration.isPressed ? 2 : 0)
            .opacity(configuration.isPressed ? 0.82 : 1)
    }
}

private struct AlarmPulseModifier: ViewModifier {
    var active: Bool
    var urgent: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var faded = false

    func body(content: Content) -> some View {
        content
            .opacity(active && !reduceMotion && faded ? 0.4 : 1)
            .animation(
                active && !reduceMotion
                    ? .easeInOut(duration: urgent ? 0.275 : 0.55).repeatForever(autoreverses: true)
                    : .default,
                value: faded)
            .onAppear { faded = active && !reduceMotion }
            .onChange(of: active) { _, active in faded = active && !reduceMotion }
            .onChange(of: reduceMotion) { _, reduced in faded = active && !reduced }
    }
}

extension View {
    func alarmPulse(active: Bool, urgent: Bool) -> some View {
        modifier(AlarmPulseModifier(active: active, urgent: urgent))
    }
}
