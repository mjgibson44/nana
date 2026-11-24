import SwiftUI
import WordCore

/// The screen the app opens on: the game's name, and the ways to play, each
/// spelled out in tiles.
struct HomeScreen: View {
    /// The name, as the home screen spells it: one word, set on two lines.
    static let titleLines = ["TIME", "TILES"]

    var onSolo: () -> Void
    var onDuel: () -> Void
    var onBattle: () -> Void
    /// The tutorial again, on purpose. It runs by itself before the first
    /// door a new player opens; this is the way back to it after that.
    var onHowToPlay: () -> Void = {}

    var body: some View {
        ScreenColumn {
            Spacer()
            VStack(spacing: Spacing.menuButtonGap) {
                title
                MenuButton(title: "Solo", action: onSolo)
                MenuButton(title: "Duel", action: onDuel)
                MenuButton(title: "Battle", action: onBattle)
            }
            Spacer()
            Button(action: onHowToPlay) {
                Text("How to play")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Palette.inkSoft)
                    .underline()
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    /// TIME over TILES, both starting from the same left edge, with a clock
    /// tile closing out TIME so the two lines are the same five tiles wide
    /// and the name sits as one block.
    private var title: some View {
        VStack(alignment: .leading, spacing: Spacing.tileGap) {
            HStack(spacing: Spacing.tileGap) {
                TileWord(text: Self.titleLines[0], style: .accent, size: Spacing.headerTile)
                RoundedRectangle(cornerRadius: Spacing.tileRadius, style: .continuous)
                    .fill(TileStyle.accent.fill)
                    .overlay {
                        Image(systemName: "clock")
                            .font(.system(size: Spacing.headerTile * 0.5, weight: .bold))
                            .foregroundStyle(TileStyle.accent.ink)
                    }
                    .frame(width: Spacing.headerTile, height: Spacing.headerTile)
            }
            TileWord(text: Self.titleLines[1], style: .accent, size: Spacing.headerTile)
        }
        .padding(.bottom, Spacing.headerGap)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Time Tiles")
        .accessibilityAddTraits(.isHeader)
    }
}

#Preview {
    HomeScreen(onSolo: {}, onDuel: {}, onBattle: {})
        .preferredColorScheme(.dark)
}
