import SwiftUI
import WordCore

/// The lesson's running instructions, step by step (App.tsx:3188–3219). Which
/// step it is rides the header, where the score would be.
struct TutorialBanner: View {
    var step: Int

    var body: some View {
        Text(.init(text))
            .font(.callout)
            .foregroundStyle(Ink.ink)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 640)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(Ink.surfaceAlt)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Ink.lineSoft).frame(height: 1)
            }
            .accessibilityAddTraits(.updatesFrequently)
    }

    /// Markdown, so the emphasis the web puts on the letters that matter
    /// survives the port.
    private var text: String {
        switch step {
        case 1:
            "Your pile spells **SOLAR**. Type it out — the middle square is already "
                + "chosen — then press **return**, or the **✓** button, to place it."
        case 2:
            "Words cross on shared letters. Tap the square **directly above the R** "
                + "and type **OBIT** — that R is the one **ORBIT** needs."
        default:
            "**PLE** spells **POLE** by overlapping **SOLAR**. Type **P**, then "
                + "**space** — or the gap button — for the gap, then **L** and **E**. "
                + "Now tap **SOLAR’s O** and the gap drops onto it."
        }
    }
}

/// The finished lesson has an empty pile and nothing left to type, so the whole
/// working area below the board goes to the way onward (App.tsx:3286–3297).
struct TutorialFinishBand: View {
    var onFinish: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            Text("Every word is down — that's the whole game.")
                .font(.callout.weight(.semibold))
                .foregroundStyle(Ink.ink.opacity(0.75))
            Button("Finish Tutorial", action: onFinish)
                .buttonStyle(InkActionButtonStyle(primary: true))
                .frame(minWidth: 200)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity)
        .background(Ink.surfaceAlt)
    }
}

/// The tutorial's header: the step counter takes the score's corner, and the
/// two things worth reaching for mid-lesson — past this step, and out
/// altogether — take the menu's (App.tsx:3122–3152).
struct TutorialHeaderView: View {
    var step: Int
    var of: Int
    var showsSkip: Bool
    var onSkip: () -> Void
    var onLeave: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 0) {
                Text("STEP")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.7)
                    .foregroundStyle(Ink.ink.opacity(0.6))
                Text("\(step) of \(of)")
                    .font(.system(size: 20, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Ink.ink)
            }
            .fixedSize()
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Step \(step) of \(of)")

            Spacer(minLength: 4)

            if showsSkip {
                Button("Skip", action: onSkip)
                    .buttonStyle(InkActionButtonStyle())
                    .accessibilityHint("Places this step's word and moves on")
            }

            Button(action: onLeave) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .frame(width: 34, height: 30)
            }
            .buttonStyle(InkActionButtonStyle())
            .accessibilityLabel("Leave the tutorial")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Ink.surface)
    }
}
