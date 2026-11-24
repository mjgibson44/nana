import SwiftUI
import WordCore

/// The door into a Solo game: pick a speed, then play.
///
/// Speed is a choice about the game you're *about* to play, so it is made
/// before there is a game, and the screen opens on whatever was played last
/// so playing the same thing again stays one tap.
struct SoloSetupScreen: View {
    /// The pace the last Solo game was played at.
    var pace: SoloPace
    var onPlay: (SoloPace) -> Void
    var onClose: () -> Void

    @State private var chosen: SoloPace?

    private var selected: Binding<SoloPace> {
        Binding(get: { chosen ?? pace }, set: { chosen = $0 })
    }

    var body: some View {
        ScreenColumn {
            Spacer()
            VStack(spacing: 0) {
                ScreenHeader("SOLO")
                MenuToggle(
                    options: PACE_OPTIONS.map { ($0.pace, $0.name) },
                    selection: selected)
            }
            Spacer()
            MenuFooter(onBack: onClose) {
                MenuButton(title: "Play", style: .primary) {
                    onPlay(selected.wrappedValue)
                }
            }
        }
    }
}

#Preview {
    SoloSetupScreen(pace: .regular, onPlay: { _ in }, onClose: {})
        .preferredColorScheme(.dark)
}
