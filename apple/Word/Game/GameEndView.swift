import SwiftUI
import WordCore

/// The end of a game: the score in big tiles (or, in a battle, the placing),
/// the ways onward, and straight under them who placed where and the words
/// this player put down — all on the first screenful, scrolling only if the
/// word list runs long. It also serves a buried battle player while the
/// battle plays on around them: the standings update live, and the host's
/// controls appear when it's decided.
struct GameEndView: View {
    struct Standing: Identifiable, Equatable {
        var id: String
        /// Shown once the battle is decided; nil while it's still running.
        var rank: Int?
        var name: String
        var isSelf: Bool
        var note: String
    }

    var score: Int
    var words: [ScoredWord]
    /// Battle: shown in place of the score.
    var placing: String?
    var standings: [Standing] = []
    /// A line under the actions: what's being waited for.
    var note: String?
    var restart: (() -> Void)?
    var onSeeGame: () -> Void
    var onLobby: (() -> Void)?
    var leaveLabel = "HOME"
    var onLeave: (() -> Void)?
    /// Off in snapshot tests — `ImageRenderer` draws nothing inside a
    /// `ScrollView`.
    var scrollable = true

    var body: some View {
        Group {
            if scrollable {
                ScrollView { content }
            } else {
                content
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Palette.bg.ignoresSafeArea())
        .accessibilityAddTraits(.isModal)
    }

    private var content: some View {
        VStack(spacing: Spacing.gap * 2) {
            // The block first and the standings right under it: who placed
            // where has to be on screen without a scroll, on a phone.
            block
                .frame(maxWidth: .infinity)
                .padding(.top, Spacing.gap)

            if !standings.isEmpty {
                section("Standings") {
                    ForEach(standings) { row in
                        HStack(spacing: 10) {
                            Text(row.rank.map(ordinal) ?? "")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(Palette.accent)
                                .frame(width: 40, alignment: .leading)
                            Text(row.name.uppercased())
                                .font(.system(size: 15, weight: .bold))
                                .tracking(1)
                                .foregroundStyle(Palette.ink)
                                .lineLimit(1)
                            if row.isSelf {
                                Text("YOU")
                                    .font(.system(size: 10, weight: .bold))
                                    .tracking(1)
                                    .foregroundStyle(Palette.accent)
                            }
                            Spacer(minLength: 6)
                            Text(row.note)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Palette.inkSoft)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(
                            RoundedRectangle(cornerRadius: Spacing.tileRadius, style: .continuous)
                                .fill(Palette.surface))
                        .accessibilityElement(children: .combine)
                    }
                }
            }

            section("Your words") {
                if sortedWords.isEmpty {
                    Text("No words made it onto the board.")
                        .font(.system(size: 14))
                        .foregroundStyle(Palette.inkSoft)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach(Array(sortedWords.enumerated()), id: \.offset) { _, word in
                        HStack {
                            Text(word.word.uppercased())
                                .font(.system(size: 15, weight: .bold))
                                .tracking(2)
                                .foregroundStyle(Palette.ink)
                            Spacer()
                            Text("+\(word.points)")
                                .font(.system(size: 14, weight: .bold))
                                .monospacedDigit()
                                .foregroundStyle(Palette.accent)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(
                            RoundedRectangle(cornerRadius: Spacing.tileRadius, style: .continuous)
                                .fill(Palette.surface))
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
        .frame(maxWidth: Spacing.maxWidth)
        .padding(Spacing.margin)
        .frame(maxWidth: .infinity)
    }

    /// The centred block every mockup shares: rows starting at one left edge.
    private var block: some View {
        TileBlock {
            TileWord(text: "GAME END", style: .accent)

            if let placing {
                BigTile(text: placing)
                    .accessibilityLabel("You finished \(placing)")
            } else {
                let digits = String(score).map(String.init)
                let unit = digits.count > 5 ? Spacing.tile * 0.6 : Spacing.tile
                HStack(spacing: Spacing.tileGap) {
                    ForEach(Array(digits.enumerated()), id: \.offset) { _, digit in
                        BigTile(text: digit, unit: unit)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Final score \(score)")
            }

            if let restart {
                TileWordButton(text: "RESTART", action: restart)
            }
            TileWordButton(text: "SEE GAME", action: onSeeGame)
            if let onLobby {
                TileWordButton(text: "LOBBY", action: onLobby)
            }
            if let onLeave {
                TileWordButton(text: leaveLabel, action: onLeave)
            }
            if let note {
                Text(note)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Palette.inkSoft)
                    .padding(.top, 4)
            }
        }
    }

    private func section<Content: View>(
        _ title: String, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(text: title)
                .padding(.bottom, 4)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var sortedWords: [ScoredWord] {
        words.sorted {
            $0.points == $1.points
                ? $0.word.localizedStandardCompare($1.word) == .orderedAscending
                : $0.points > $1.points
        }
    }
}
