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
///
/// A Solo game the OS took away mid-run is picked back up here too, beside
/// PLAY: the two are the same either/or — carry on, or throw that game away
/// for one dealt on the settings above — and putting them a row apart is what
/// makes that choice legible.
struct SoloSetupScreen: View {
    /// The pace the last Solo game was played at.
    var pace: SoloPace
    /// And what the board was up to.
    var modifier: SoloModifier = .none
    /// Whether there's a Solo game left half-played. A saved *Daily* isn't
    /// one of these — that day is picked back up behind the DAILY door.
    var hasSavedGame: Bool = false
    var onResume: () -> Void = {}
    var onPlay: (SoloPace, SoloModifier) -> Void
    var onClose: () -> Void

    @State private var chosen: SoloPace?
    @State private var chosenModifier: SoloModifier?

    private var selected: SoloPace { chosen ?? pace }
    private var selectedModifier: SoloModifier { chosenModifier ?? modifier }

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

                section("Speed", note: paceNote) {
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

                section("Board", note: modifierNote) {
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
                }

                VStack(spacing: Spacing.tileGap) {
                    if hasSavedGame {
                        TileWordButton(text: "RESUME", style: .accent, action: onResume)
                    }
                    TileWordButton(text: "PLAY", style: .accentButton) {
                        onPlay(selected, selectedModifier)
                    }
                }
                TileWordButton(text: "BACK", action: onClose)
            }
            Spacer()
        }
    }

    /// What the chosen speed actually costs you, in the three numbers that
    /// decide a game: the hand you open with, how long you get to work it,
    /// and how hard the clock leans afterwards.
    private var paceNote: String {
        let opening = formatSeconds(Double(endlessInitialSeconds(selected)))
        let seconds = GameHeaderView.clockText(endlessDripSeconds(0, selected))
        let tiles = endlessDripTiles(0, selected)
        return "\(SOLO_START_TILES) tiles, \(opening) to work them — "
            + "then +\(tiles) every \(seconds)."
    }

    /// What the squares offer, in the one sentence that matters — which is
    /// the decay, because that is what makes a lit square a decision rather
    /// than a chore. The rest is on `MODIFIER_INFO`.
    ///
    /// One sentence covers both kinds because they *are* one mechanic: this
    /// row used to be a three-way choice between nothing, gold and salvage,
    /// which asked before the game which of two payouts you would want during
    /// it. Now both appear and the board asks it live, so the row is a
    /// switch.
    private var modifierNote: String {
        let life = Int(PRIZE_SECONDS)
        switch selectedModifier {
        case .none:
            return "Nothing but the pile and the clock."
        case .prizes:
            return "Squares light up near your board for \(life)s — "
                + "gold pays up to \(GOLD_TOP_POINTS) points, blue clears up to "
                + "\(SALVAGE_TOP_TILES) tiles off your pile. "
                + "Both are worth less every second you leave them."
        }
    }

    /// One question: what it is in plain type, the answers in tiles, and what
    /// the chosen answer means in plain type under them.
    ///
    /// The layout rework dropped these notes, and flagged at the time that it
    /// left the board setting unexplained anywhere in the app. They are back
    /// under that rework's own rule rather than against it — plain type
    /// explains, tiles are what you press — because a modifier's whole
    /// mechanic is that a square is worth less the longer you leave it, and
    /// nothing else says so: there is no card, and the board can only show
    /// the number falling once you are already playing.
    private func section<Content: View>(
        _ label: String, note: String, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: Spacing.tileGap) {
            caption(label)
                .padding(.bottom, Spacing.tileGap)
            content()
            caption(note)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
                .padding(.top, Spacing.tileGap)
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Palette.inkSoft)
    }
}

#Preview {
    SoloSetupScreen(
        pace: .regular, modifier: .prizes, hasSavedGame: true,
        onResume: {}, onPlay: { _, _ in }, onClose: {})
        .preferredColorScheme(.dark)
}
