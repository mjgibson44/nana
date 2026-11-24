import SwiftUI
import WordCore

/// The tutorial's instructions, where the pile gauge sits in a real game: a
/// short title for the step and the one thing to do next. It changes as the
/// word row fills, so the next move is always the one on screen — spell it,
/// then place it.
struct TutorialBannerView: View {
    var step: Int
    var total: Int
    var title: String
    var instruction: Text

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(title.uppercased())
                    .font(.system(size: 13, weight: .bold))
                    .tracking(1.4)
                    .foregroundStyle(Palette.accent)
                Spacer(minLength: 8)
                Text("\(step + 1) of \(total)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.inkSoft)
                    .monospacedDigit()
            }
            instruction
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Spacing.menuButtonRadius, style: .continuous)
                .fill(Palette.accentBg))
        .accessibilityElement(children: .combine)
    }

    /// What the banner says for `step`, given whether the word row already
    /// holds the step's word.
    static func content(
        for step: TutorialStep, at index: Int, rowReady: Bool
    ) -> (title: String, instruction: Text) {
        let word = step.word.uppercased()
        let gap = Text(Image(systemName: "square.dashed"))
        let check = Text(Image(systemName: "checkmark"))

        if !step.needsGap {
            return rowReady
                ? ("Your first word", Text("Now tap ") + check + Text(" to put \(word) on the board."))
                : ("Your first word", Text("Tap ") + spelled(step.pattern, gap: gap)
                    + Text(" in the pile to spell \(word)."))
        }

        let borrowed = step.borrowed.first?.uppercased() ?? ""
        if rowReady {
            let which = index == 1 ? "the" : "an"
            return (
                index == 1 ? "Borrow a letter" : "Once more",
                Text("Now tap \(which) \(borrowed) on the board — \(word) goes through it."))
        }
        if index == 1 {
            return (
                "Borrow a letter",
                Text("Every word after the first goes through a letter already on the board. ")
                    + Text("Spell \(word) with a gap where the \(borrowed) goes: ")
                    + spelled(step.pattern, gap: gap) + Text("."))
        }
        return (
            "Once more",
            Text("Same move: spell \(word) with a gap for the \(borrowed) — ")
                + spelled(step.pattern, gap: gap) + Text("."))
    }

    /// The word as it's built in the row — "O ▢ B I T" — with the gap drawn
    /// as the button that adds it.
    private static func spelled(_ pattern: [String?], gap: Text) -> Text {
        pattern.enumerated().reduce(Text("")) { text, entry in
            let piece = entry.element.map { Text($0.uppercased()).bold() } ?? gap
            return entry.offset == 0 ? piece : text + Text(" ") + piece
        }
    }
}

/// The card that closes the tutorial: what the player just learned in one
/// line, what changes in a real game, and the way into one.
struct TutorialFinishView: View {
    var playLabel: String
    var onPlay: () -> Void

    var body: some View {
        ZStack {
            Palette.bg.ignoresSafeArea()
            VStack(spacing: Spacing.section) {
                ScreenHeader("READY")
                VStack(spacing: 12) {
                    Text("That’s the whole game: one word down, then every word after it through a gap.")
                    Text("In a real game new tiles keep arriving, and a full pile ends it.")
                }
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Palette.inkSoft)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
                MenuButton(title: playLabel, style: .primary, action: onPlay)
                    .padding(.top, Spacing.gap)
            }
            .padding(Spacing.margin)
        }
    }
}
