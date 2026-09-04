import SwiftUI
import WordCore

/// The screen the app opens on: the game's name, and the two ways to play,
/// each spelled out in tiles. A game the OS took away mid-run comes back
/// first — it's the one thing here the player didn't choose to leave.
struct HomeScreen: View {
    /// The name, as the home screen spells it. One place to change.
    static let title = "TIMETILES"

    var hasSavedGame: Bool
    var onResume: () -> Void
    var onSolo: () -> Void
    var onBattle: () -> Void

    var body: some View {
        ScreenColumn {
            Spacer()
            VStack(spacing: Spacing.tileGap) {
                TileWord(text: Self.title, style: .accent)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.bottom, Spacing.tileGap)
                if hasSavedGame {
                    TileWordButton(text: "RESUME", action: onResume)
                }
                TileWordButton(text: "SOLO", action: onSolo)
                TileWordButton(text: "BATTLE", action: onBattle)
            }
            Spacer()
        }
    }
}

#Preview {
    HomeScreen(hasSavedGame: true, onResume: {}, onSolo: {}, onBattle: {})
        .preferredColorScheme(.dark)
}
