import SwiftUI
import WordCore

/// The door into a Solo game: pick a speed, then play.
///
/// Speed used to be a line in the in-game menu, where picking one threw the
/// game away and dealt another — a setting that acted like a button. It is a
/// choice about the game you're *about* to play, so it is made before there
/// is a game, and the screen opens on whatever was played last so playing the
/// same thing again stays one tap.
struct SoloSetupScreen: View {
    /// The pace the last Solo game was played at.
    var pace: SoloPace
    var onPlay: (SoloPace) -> Void
    var onClose: () -> Void

    @State private var chosen: SoloPace?

    private var selected: SoloPace { chosen ?? pace }

    var body: some View {
        ScreenColumn {
            Spacer()
            // Centred rows with a centred note, like the other doors
            // (`BattleEntryScreen`) rather than the left-edged blocks the
            // results screen uses.
            VStack(spacing: Spacing.tileGap) {
                TileWord(text: "SPEED", style: .accent)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.bottom, Spacing.tileGap)

                ForEach(PACE_OPTIONS, id: \.pace) { option in
                    let isSelected = selected == option.pace
                    TileWordButton(
                        text: option.name.uppercased(),
                        style: isSelected ? .accent : .dim
                    ) {
                        chosen = option.pace
                    }
                    .accessibilityLabel(option.name)
                    .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
                }

                Text(note)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Palette.inkSoft)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 300)
                    .padding(.vertical, Spacing.tileGap)

                TileWordButton(text: "PLAY", style: .accentButton) {
                    onPlay(selected)
                }
                TileWordButton(text: "BACK", action: onClose)
                    .padding(.top, Spacing.tileGap)
            }
            Spacer()
        }
    }

    /// What the chosen speed actually costs you, in the three numbers that
    /// decide a game: the hand you open with, how long you get to work it,
    /// and how hard the clock leans afterwards.
    private var note: String {
        let opening = formatSeconds(Double(endlessInitialSeconds(selected)))
        let seconds = GameHeaderView.clockText(endlessDripSeconds(0, selected))
        let tiles = endlessDripTiles(0, selected)
        return "\(SOLO_START_TILES) tiles, \(opening) to work them — "
            + "then +\(tiles) every \(seconds)."
    }
}

#Preview {
    SoloSetupScreen(pace: .regular, onPlay: { _ in }, onClose: {})
        .preferredColorScheme(.dark)
}
