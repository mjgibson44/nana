import SwiftUI
import WordCore

/// The screen the app opens on: the game's name, and the ways to play, each
/// spelled out in tiles. A Solo game the OS took away mid-run is picked back
/// up behind the SOLO door (`SoloSetupScreen`), with the rest of that game's
/// choices, rather than from a row up here.
struct HomeScreen: View {
    /// The name, as the home screen spells it. One place to change.
    static let title = "TIMETILES"

    /// Whether today's puzzle is still to be played. Played out, the door
    /// still opens — onto the day you had, not a second go at it.
    var dailyPlayed: Bool = false
    /// How many days in a row, shown on the door once there is a run worth
    /// keeping. The reason to come back tomorrow belongs where you'd see it
    /// on the way past, not on a stats page.
    var dailyStreak: Int = 0
    var onSolo: () -> Void
    var onDaily: () -> Void = {}
    var onBattle: () -> Void
    var onOccupy: () -> Void = {}

    var body: some View {
        ScreenColumn {
            Spacer()
            // The doors come in groups, a section gap apart: the ones you
            // play alone, and the ones that need other people. Inside a group
            // the rows sit tile-tight, so the grouping is what the eye reads
            // first.
            VStack(spacing: Spacing.section) {
                TileTitle(text: Self.title)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.bottom, Spacing.tileGap)
                VStack(spacing: Spacing.tileGap) {
                    TileWordButton(text: "SOLO", action: onSolo)
                    TileWordButton(
                        text: "DAILY", style: dailyPlayed ? .dim : .accent, action: onDaily)
                    if dailyStreak > 1 {
                        Text("\(dailyStreak) day streak")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Palette.inkSoft)
                            .accessibilityLabel("\(dailyStreak) day streak")
                    }
                }
                VStack(spacing: Spacing.tileGap) {
                    TileWordButton(text: "BATTLE", action: onBattle)
                    TileWordButton(text: "OCCUPY", action: onOccupy)
                }
            }
            Spacer()
        }
    }
}

#Preview {
    HomeScreen(
        dailyPlayed: false, dailyStreak: 4,
        onSolo: {}, onDaily: {}, onBattle: {}, onOccupy: {})
        .preferredColorScheme(.dark)
}
