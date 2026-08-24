import SwiftUI
import WordCore

/// The way into a battle: open a room, or join someone else's.
///
/// Which options appear depends on what the player's OS can do (plan §7.3).
/// Party codes are a 26-and-up feature, so below that the only road is Game
/// Center's invite sheet — friends, Messages threads, nearby players. The
/// screen says which it's offering rather than hiding the difference, because
/// "send an invite" and "read out a code" are different things to ask of the
/// person you're playing with.
struct BattleEntryScreen: View {
    var supportsPartyCodes: Bool
    /// Non-nil once we're hosting: the code to read out.
    var partyCode: String?
    var isBusy: Bool
    var error: String?
    var onHost: () -> Void
    var onJoin: (String) -> Void
    var onInvite: () -> Void
    var onClose: () -> Void
    var scrollable = true

    @State private var typedCode = ""

    var body: some View {
        PageScaffold(
            eyebrow: BATTLE_ROYALE_INFO.name.uppercased(),
            title: "Play together",
            onClose: onClose,
            scrollable: scrollable
        ) {
            if let error {
                Text(error)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Ink.badInk)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Ink.surfaceAlt))
                    .accessibilityElement(children: .combine)
            }

            if let partyCode {
                PageSection("Your code") {
                    VStack(spacing: 6) {
                        Text(partyCode)
                            .font(.system(size: 34, weight: .heavy, design: .monospaced))
                            .foregroundStyle(Ink.ink)
                            .textSelection(.enabled)
                            .accessibilityLabel(
                                "Party code, \(partyCode.map(String.init).joined(separator: " "))")
                        Text("Read this out, or share the link from the Games app.")
                            .font(.caption)
                            .foregroundStyle(Ink.ink.opacity(0.7))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Ink.surface))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12).strokeBorder(Ink.ink, lineWidth: 3))
                }
            } else {
                PageSection("Start one") {
                    VStack(spacing: 8) {
                        if supportsPartyCodes {
                            Button("Open a room", action: onHost)
                                .buttonStyle(InkActionButtonStyle(primary: true))
                                .disabled(isBusy)
                            Text("Gives you a code to read out.")
                                .font(.caption)
                                .foregroundStyle(Ink.ink.opacity(0.7))
                        }
                        Button(
                            supportsPartyCodes ? "Invite from Game Center" : "Invite friends",
                            action: onInvite
                        )
                        .buttonStyle(InkActionButtonStyle(primary: !supportsPartyCodes))
                        .disabled(isBusy)
                        Text("Friends, a Messages thread, or players nearby.")
                            .font(.caption)
                            .foregroundStyle(Ink.ink.opacity(0.7))
                    }
                }

                if supportsPartyCodes {
                    PageSection("Or join one") {
                        VStack(spacing: 8) {
                            TextField("Code", text: $typedCode)
                                .textFieldStyle(.plain)
                                .font(.system(size: 22, weight: .bold, design: .monospaced))
                                .multilineTextAlignment(.center)
                                .padding(.vertical, 10)
                                .background(RoundedRectangle(cornerRadius: 10).fill(Ink.surface))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .strokeBorder(Ink.line, lineWidth: 2)
                                )
                                #if os(iOS)
                                .textInputAutocapitalization(.characters)
                                .autocorrectionDisabled()
                                #endif
                                .accessibilityLabel("Party code")
                            Button("Join") { onJoin(typedCode) }
                                .buttonStyle(InkActionButtonStyle(primary: true))
                                .disabled(isBusy || typedCode.trimmed.isEmpty)
                        }
                    }
                }
            }

            if isBusy {
                // Hosting parks here with the code up while people join, so
                // the wait has to name what it's waiting for.
                Text(partyCode == nil ? "Talking to Game Center…" : "Waiting for players…")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(Ink.ink.opacity(0.7))
            }

            Button("Back", action: onClose)
                .buttonStyle(InkActionButtonStyle())
        }
    }
}

extension String {
    fileprivate var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
