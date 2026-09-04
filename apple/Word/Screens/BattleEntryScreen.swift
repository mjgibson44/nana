import SwiftUI
import WordCore

/// The way into a battle — or an Occupy game, which shares the road: find
/// strangers, open a room, or join someone else's.
///
/// Which friends' options appear depends on what the player's OS can do
/// (plan §7.3). Party codes are a 26-and-up feature, so below that the only
/// road to friends is Game Center's invite sheet — friends, Messages threads,
/// nearby players. Random matches work everywhere.
struct BattleEntryScreen: View {
    /// Which game the room is for. Only the title knows.
    var mode: GameMode = .battle
    var supportsPartyCodes: Bool
    /// Non-nil once we're hosting: the code to read out.
    var partyCode: String?
    /// Non-nil while strangers are being found: which kind of match.
    var searching: RandomMatchKind?
    /// What the search is doing right now ("Finding players…").
    var searchStatus: String?
    var isBusy: Bool
    var error: String?
    var onHost: () -> Void
    var onJoin: (String) -> Void
    var onInvite: () -> Void
    var onDuel: () -> Void
    var onParty: () -> Void
    var onCancelSearch: () -> Void
    var onClose: () -> Void

    @State private var typedCode = ""

    var body: some View {
        ScreenColumn {
            Spacer()
            VStack(spacing: Spacing.tileGap) {
                TileWord(text: mode == .occupy ? "OCCUPY" : "BATTLE", style: .accent)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.bottom, Spacing.tileGap)

                if let error {
                    note(error, tone: Palette.gaugeBad)
                }

                if let searching {
                    // Looking for strangers: the kind being sought, what the
                    // search is up to, and the way out of it.
                    TileWord(text: searching.word, style: .accent)
                        .accessibilityLabel("Finding a \(searching.rawValue)")
                    note(searchStatus ?? "Finding players…")
                    TileWordButton(text: "CANCEL", action: onCancelSearch)
                        .padding(.top, Spacing.tileGap)
                } else if let partyCode {
                    // The code, spelled out like everything else: read it out,
                    // or share the link from the Games app.
                    TileWord(text: partyCode, style: .accent)
                        .accessibilityLabel(
                            "Party code, \(partyCode.map(String.init).joined(separator: " "))")
                    note("Read this out, or share the link from the Games app.")
                } else {
                    note("Play strangers")
                    TileWordButton(text: RandomMatchKind.duel.word, action: onDuel)
                        .disabled(isBusy)
                    TileWordButton(text: RandomMatchKind.party.word, action: onParty)
                        .disabled(isBusy)

                    note("Play friends")
                        .padding(.top, Spacing.tileGap)
                    if supportsPartyCodes {
                        TileWordButton(text: "HOST", action: onHost)
                            .disabled(isBusy)
                    }
                    TileWordButton(text: "INVITE", action: onInvite)
                        .disabled(isBusy)

                    if supportsPartyCodes {
                        HStack(spacing: Spacing.tileGap) {
                            TextField("CODE", text: $typedCode)
                                .textFieldStyle(.plain)
                                .font(.system(size: 18, weight: .bold, design: .monospaced))
                                .foregroundStyle(Palette.ink)
                                .multilineTextAlignment(.center)
                                .frame(width: Spacing.tile * 4 + Spacing.tileGap * 3, height: Spacing.tile)
                                .background(
                                    RoundedRectangle(
                                        cornerRadius: Spacing.tileRadius, style: .continuous
                                    )
                                    .fill(Palette.surface))
                                #if os(iOS)
                                .textInputAutocapitalization(.characters)
                                .autocorrectionDisabled()
                                #endif
                                .accessibilityLabel("Party code")
                            TileWordButton(
                                text: "JOIN", style: .accentButton,
                                disabled: isBusy || typedCode.trimmed.isEmpty
                            ) {
                                onJoin(typedCode)
                            }
                        }
                        .padding(.top, Spacing.tileGap)
                    }
                }

                if isBusy, searching == nil {
                    // Hosting parks here with the code up while people join,
                    // so the wait has to name what it's waiting for.
                    note(partyCode == nil ? "Talking to Game Center…" : "Waiting for players…")
                }

                if searching == nil {
                    TileWordButton(text: "BACK", action: onClose)
                        .padding(.top, Spacing.tileGap)
                }
            }
            Spacer()
        }
    }

    private func note(_ text: String, tone: Color = Palette.inkSoft) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(tone)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 300)
            .padding(.vertical, Spacing.tileGap)
    }
}

extension String {
    fileprivate var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
