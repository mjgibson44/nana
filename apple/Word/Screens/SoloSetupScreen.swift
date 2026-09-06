import SwiftUI
import WordCore

/// The door into a Solo game: pick a speed and what the board is up to, then
/// play.
///
/// Speed used to be a line in the in-game menu, where picking one threw the
/// game away and dealt another — a setting that acted like a button. It is a
/// choice about the game you're *about* to play, so it is made before there
/// is a game, and the screen opens on whatever was played last so playing the
/// same thing again stays one tap.
///
/// Wildfire sits here rather than behind a door of its own because it is the
/// same game leaning on you differently — same board, same pile, same way of
/// building a word — and a second door would say otherwise.
struct SoloSetupScreen: View {
    /// The pace the last Solo game was played at.
    var pace: SoloPace
    /// And what the board was up to.
    var hazard: SoloHazard = .none
    var onPlay: (SoloPace, SoloHazard) -> Void
    var onClose: () -> Void

    @State private var chosen: SoloPace?
    @State private var chosenHazard: SoloHazard?

    private var selected: SoloPace { chosen ?? pace }
    private var selectedHazard: SoloHazard { chosenHazard ?? hazard }

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

                TileWord(text: "BOARD", style: .accent)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.bottom, Spacing.tileGap)

                ForEach(HAZARD_OPTIONS, id: \.hazard) { option in
                    let isSelected = selectedHazard == option.hazard
                    TileWordButton(
                        text: option.name.uppercased(),
                        style: isSelected ? .accent : .dim
                    ) {
                        chosenHazard = option.hazard
                    }
                    .accessibilityLabel(option.name)
                    .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
                }

                Text(hazardNote)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Palette.inkSoft)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 300)
                    .padding(.vertical, Spacing.tileGap)

                TileWordButton(text: "PLAY", style: .accentButton) {
                    onPlay(selected, selectedHazard)
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

    /// What fire costs, in the one sentence that matters: it burns on a clock
    /// you already know, and playing near it is the answer. The rest is on
    /// `WILDFIRE_INFO`.
    private var hazardNote: String {
        switch selectedHazard {
        case .none:
            "Nothing but the pile and the clock."
        case .wildfire:
            "Squares catch fire. Play on or beside one to put it out — "
                + "leave it and it takes a tile back and spreads."
        }
    }
}

#Preview {
    SoloSetupScreen(pace: .regular, hazard: .none, onPlay: { _, _ in }, onClose: {})
        .preferredColorScheme(.dark)
}
