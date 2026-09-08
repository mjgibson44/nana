import SwiftUI
import WordCore

/// The screen the app opens on: the game's name, and the three ways to play,
/// each spelled out in tiles. A game the OS took away mid-run comes back
/// first — it's the one thing here the player didn't choose to leave.
struct HomeScreen: View {
    /// The name, as the home screen spells it. One place to change.
    static let title = "TIMETILES"

    var hasSavedGame: Bool
    /// Whether today's puzzle is still to be played. Played out, the door
    /// still opens — onto the day you had, not a second go at it.
    var dailyPlayed: Bool = false
    /// How many days in a row, shown on the door once there is a run worth
    /// keeping. The reason to come back tomorrow belongs where you'd see it
    /// on the way past, not on a stats page.
    var dailyStreak: Int = 0
    var onResume: () -> Void
    var onSolo: () -> Void
    var onDaily: () -> Void = {}
    var onBattle: () -> Void
    var onOccupy: () -> Void = {}

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
                TileWordButton(
                    text: "DAILY", style: dailyPlayed ? .dim : .accent, action: onDaily)
                if dailyStreak > 1 {
                    Text("\(dailyStreak) day streak")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Palette.inkSoft)
                        .accessibilityLabel("\(dailyStreak) day streak")
                }
                TileWordButton(text: "BATTLE", action: onBattle)
                // Occupy's door is closed for now — its ideas live on as
                // Battle's shared board rather than as a mode of their own
                // (`OCCUPY_DOOR_ENABLED`).
                if OCCUPY_DOOR_ENABLED {
                    TileWordButton(text: "OCCUPY", action: onOccupy)
                }
            }
            Spacer()
        }
    }
}

#Preview {
    HomeScreen(
        hasSavedGame: true, dailyPlayed: false, dailyStreak: 4,
        onResume: {}, onSolo: {}, onDaily: {}, onBattle: {}, onOccupy: {})
        .preferredColorScheme(.dark)
}
