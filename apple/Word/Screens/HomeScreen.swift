import SwiftUI
import WordCore

/// The screen the app opens on: the game's name, and the two ways to play,
/// each spelled out in tiles. A game the OS took away mid-run comes back
/// first — it's the one thing here the player didn't choose to leave.
struct HomeScreen: View {
    /// The name, as the home screen spells it. One place to change.
    static let title = "FEWTILES"

    var hasSavedGame: Bool
    /// Shows Game Center's own access point over the home screen. Off in
    /// snapshot tests and previews — it's a UIKit/AppKit overlay the renderer
    /// can't draw, and it needs a signed-in player to say anything.
    var showsGameCenter = false
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
        .modifier(GameCenterAccessPoint(active: showsGameCenter))
    }
}

#Preview {
    HomeScreen(hasSavedGame: true, onResume: {}, onSolo: {}, onBattle: {})
        .preferredColorScheme(.dark)
}
