import SwiftUI
import WordCore

/// The anchored controls for every run through a selected tile
/// (`WordControls.tsx`). A crossing offers two rows. The grab affordance owns
/// its own pointer stream, like the web's external whole-word drag, while the
/// board's unified gesture machine stays inert underneath it.
struct WordControlsView: View {
    var words: [WordRun]
    var canRotate: (WordRun) -> Bool
    var onGrabBegan: (WordRun, CGPoint) -> Void
    var onGrabMoved: (CGPoint) -> Void
    var onGrabEnded: (CGPoint) -> Void
    var onGrabCancelled: () -> Void
    var onRotate: (WordRun) -> Void
    var onRemove: (WordRun) -> Void
    var onHighlight: (WordRun?) -> Void

    var body: some View {
        VStack(spacing: 3) {
            ForEach(Array(words.enumerated()), id: \.offset) { _, word in
                HStack(spacing: 3) {
                    Text("\(word.direction == .across ? "➜" : "⬇")  \(word.word.uppercased())")
                        .font(.caption2.bold())
                        .lineLimit(1)
                        .padding(.horizontal, 4)

                    WordGrabControl(
                        word: word,
                        onBegan: onGrabBegan,
                        onMoved: onGrabMoved,
                        onEnded: onGrabEnded,
                        onCancelled: onGrabCancelled)

                    controlButton(
                        systemName: word.direction == .across ? "arrow.turn.down.right" : "arrow.turn.up.left",
                        label: "Turn \(word.word.uppercased()) \(word.direction == .across ? "down" : "across")",
                        disabled: !canRotate(word)
                    ) {
                        onRotate(word)
                    }

                    controlButton(
                        systemName: "trash",
                        label: "Return \(word.word.uppercased()) to the pile",
                        role: .destructive
                    ) {
                        onRemove(word)
                    }
                }
                .padding(2)
                .background(RoundedRectangle(cornerRadius: 5).fill(Ink.surfaceAlt.opacity(0.001)))
                .onHover { hovering in onHighlight(hovering ? word : nil) }
            }
        }
        .padding(4)
        .background(RoundedRectangle(cornerRadius: 9).fill(Ink.surface))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Ink.line, lineWidth: 2))
        .shadow(color: .black.opacity(0.2), radius: 5, x: 0, y: 3)
    }

    private func controlButton(
        systemName: String,
        label: String,
        role: ButtonRole? = nil,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: role, action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .bold))
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 7).fill(Ink.surfaceAlt))
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Ink.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.35 : 1)
        .accessibilityLabel(label)
    }
}

/// Starts at distance zero so the word lifts on press, matching the tile drag
/// pipeline. The view remains mounted (but hidden) for the life of the drag.
private struct WordGrabControl: View {
    var word: WordRun
    var onBegan: (WordRun, CGPoint) -> Void
    var onMoved: (CGPoint) -> Void
    var onEnded: (CGPoint) -> Void
    var onCancelled: () -> Void

    @State private var active = false
    @GestureState private var pressed = false

    var body: some View {
        Image(systemName: "move.3d")
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(Ink.ink)
            .frame(width: 30, height: 30)
            .background(RoundedRectangle(cornerRadius: 7).fill(Ink.surfaceAlt))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Ink.line, lineWidth: 1))
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named(GameScreen.space))
                    .updating($pressed) { _, state, _ in state = true }
                    .onChanged { value in
                        if !active {
                            active = true
                            onBegan(word, value.startLocation)
                        }
                        onMoved(value.location)
                    }
                    .onEnded { value in
                        active = false
                        onEnded(value.location)
                    }
            )
            .onChange(of: pressed) { _, isPressed in
                if !isPressed, active {
                    active = false
                    onCancelled()
                }
            }
            .accessibilityElement()
            .accessibilityLabel("Drag \(word.word.uppercased())")
            .accessibilityHint("Move this word to another board square")
            .accessibilityAddTraits(.isButton)
    }
}

struct WordGhostView: View {
    var drag: WordDrag
    var cellSize: Double

    var body: some View {
        let layout = drag.word.direction == .across
            ? AnyLayout(HStackLayout(spacing: 2))
            : AnyLayout(VStackLayout(spacing: 2))
        layout {
            ForEach(Array(drag.letters.enumerated()), id: \.offset) { _, letter in
                let size = max(28, cellSize - 4)
                RoundedRectangle(cornerRadius: max(5, size * 0.18))
                    .fill(Ink.tileFace)
                    .overlay(
                        RoundedRectangle(cornerRadius: max(5, size * 0.18))
                            .strokeBorder(Ink.tileEdge, lineWidth: 2))
                    .overlay(
                        Text(letter.uppercased())
                            .font(.system(size: size * 0.5, weight: .bold))
                            .foregroundStyle(Ink.ink))
                    .frame(width: size, height: size)
            }
        }
        .opacity(0.9)
        .position(drag.location)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
