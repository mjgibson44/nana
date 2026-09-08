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
///
/// A Solo game the OS took away mid-run is picked back up here too, beside
/// PLAY: the two are the same either/or — carry on, or throw that game away
/// for one dealt on the settings above — and putting them a row apart is what
/// makes that choice legible.
struct SoloSetupScreen: View {
    /// The pace the last Solo game was played at.
    var pace: SoloPace
    /// And what the board was up to.
    var hazard: SoloHazard = .none
    /// Whether there's a Solo game left half-played. A saved *Daily* isn't
    /// one of these — that day is picked back up behind the DAILY door.
    var hasSavedGame: Bool = false
    var onResume: () -> Void = {}
    var onPlay: (SoloPace, SoloHazard) -> Void
    var onClose: () -> Void

    @State private var chosen: SoloPace?
    @State private var chosenHazard: SoloHazard?

    private var selected: SoloPace { chosen ?? pace }
    private var selectedHazard: SoloHazard { chosenHazard ?? hazard }

    var body: some View {
        ScreenColumn {
            Spacer()
            // One settled block per question, a section gap apart. The title
            // says which game this is; the two questions are labelled in
            // plain type under it, because a word set in tiles is something
            // you press.
            VStack(spacing: Spacing.section) {
                TileTitle(text: "SOLO")
                    .accessibilityAddTraits(.isHeader)
                    .padding(.bottom, Spacing.tileGap)

                section("Speed") {
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
                }

                section("Board") {
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
                }

                VStack(spacing: Spacing.tileGap) {
                    if hasSavedGame {
                        TileWordButton(text: "RESUME", style: .accent, action: onResume)
                    }
                    TileWordButton(text: "PLAY", style: .accentButton) {
                        onPlay(selected, selectedHazard)
                    }
                }
                TileWordButton(text: "BACK", action: onClose)
            }
            Spacer()
        }
    }

    /// One question: what it is, in plain type, over the answers in tiles.
    private func section<Content: View>(
        _ label: String, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: Spacing.tileGap) {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Palette.inkSoft)
                .padding(.bottom, Spacing.tileGap)
            content()
        }
    }
}

#Preview {
    SoloSetupScreen(
        pace: .regular, hazard: .none, hasSavedGame: true,
        onResume: {}, onPlay: { _, _ in }, onClose: {})
        .preferredColorScheme(.dark)
}
