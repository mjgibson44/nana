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
/// The modifiers sit here rather than behind doors of their own because each
/// is the same game offering you something different — same board, same pile,
/// same way of building a word — and a second door would say otherwise.
struct SoloSetupScreen: View {
    /// The pace the last Solo game was played at.
    var pace: SoloPace
    /// And what the board was up to.
    var modifier: SoloModifier = .none
    var onPlay: (SoloPace, SoloModifier) -> Void
    var onClose: () -> Void

    @State private var chosen: SoloPace?
    @State private var chosenModifier: SoloModifier?

    private var selected: SoloPace { chosen ?? pace }
    private var selectedModifier: SoloModifier { chosenModifier ?? modifier }

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

                ForEach(MODIFIER_OPTIONS, id: \.modifier) { option in
                    let isSelected = selectedModifier == option.modifier
                    TileWordButton(
                        text: option.name.uppercased(),
                        style: isSelected ? .accent : .dim
                    ) {
                        chosenModifier = option.modifier
                    }
                    .accessibilityLabel(option.name)
                    .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
                }

                Text(modifierNote)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Palette.inkSoft)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 300)
                    .padding(.vertical, Spacing.tileGap)

                TileWordButton(text: "PLAY", style: .accentButton) {
                    onPlay(selected, selectedModifier)
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

    /// What a modifier offers, in the one sentence that matters — which for
    /// both of them is the decay, because that is what makes a gold square a
    /// decision rather than a chore. The rest is on `MODIFIER_INFO`.
    private var modifierNote: String {
        let life = Int(PRIZE_SECONDS)
        switch selectedModifier {
        case .none:
            return "Nothing but the pile and the clock."
        case .gold:
            return "Gold squares appear near your board for \(life)s. "
                + "Land a tile on one for \(GOLD_TOP_POINTS) points — "
                + "less every second you leave it."
        case .salvage:
            return "Gold squares appear near your board for \(life)s. "
                + "Land a tile on one to clear \(SALVAGE_TOP_TILES) tiles off your pile — "
                + "fewer every second you leave it."
        }
    }
}

#Preview {
    SoloSetupScreen(pace: .regular, modifier: .none, onPlay: { _, _ in }, onClose: {})
        .preferredColorScheme(.dark)
}
