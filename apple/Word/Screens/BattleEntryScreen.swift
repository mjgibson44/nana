import SwiftUI
import WordCore

/// The way into a battle — or an Occupy game, which shares the road: open a
/// room, or join someone else's.
///
/// Which options appear depends on what the player's OS can do (plan §7.3).
/// Party codes are a 26-and-up feature, so below that the only road is Game
/// Center's invite sheet — friends, Messages threads, nearby players.
struct BattleEntryScreen: View {
    /// Which game the room is for. Only the title knows.
    var mode: GameMode = .battle
    var supportsPartyCodes: Bool
    /// Non-nil once we're hosting: the code to read out.
    var partyCode: String?
    var isBusy: Bool
    var error: String?
    var onHost: () -> Void
    var onJoin: (String) -> Void
    var onInvite: () -> Void
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

                if let partyCode {
                    // The code, spelled out like everything else: read it out,
                    // or share the link from the Games app.
                    TileWord(text: partyCode, style: .accent)
                        .accessibilityLabel(
                            "Party code, \(partyCode.map(String.init).joined(separator: " "))")
                    note("Read this out, or share the link from the Games app.")
                } else {
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

                if isBusy {
                    // Hosting parks here with the code up while people join,
                    // so the wait has to name what it's waiting for.
                    note(partyCode == nil ? "Talking to Game Center…" : "Waiting for players…")
                }

                TileWordButton(text: "BACK", action: onClose)
                    .padding(.top, Spacing.tileGap)
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
