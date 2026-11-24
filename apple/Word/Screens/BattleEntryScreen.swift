import SwiftUI
import WordCore

/// Which room the DUEL and BATTLE doors open: two players, or up to
/// `BATTLE_MAX_PLAYERS`. Both play the same game; only the seats differ.
enum RoomKind: String, Equatable {
    case duel
    case battle

    /// The word the screens spell it as.
    var word: String { rawValue.uppercased() }

    /// How many the room seats, host included. Nil leaves the mode's own cap.
    var seatLimit: Int? {
        switch self {
        case .duel: return 2
        case .battle: return nil
        }
    }
}

/// The way into a duel or a battle: open a room and share its code, or join
/// someone else's with theirs.
///
/// Party codes are a 26-and-up feature (plan §7.3). Below that HOST raises
/// Game Center's invite sheet instead, and an invite is accepted from Game
/// Center itself, so there is no JOIN to offer.
struct BattleEntryScreen: View {
    var room: RoomKind = .battle
    var supportsPartyCodes: Bool
    /// Non-nil once we're hosting: the code to read out.
    var partyCode: String?
    var isBusy: Bool
    var error: String?
    var onHost: () -> Void
    var onJoin: (String) -> Void
    var onClose: () -> Void

    /// JOIN was pressed: the screen asks for a code rather than offering
    /// HOST or JOIN.
    @State var enteringCode = false
    @State var typedCode = ""

    @Environment(\.snapshotRendering) private var snapshotRendering

    var body: some View {
        ScreenColumn {
            Spacer()
            VStack(spacing: Spacing.menuButtonGap) {
                ScreenHeader(room.word)

                if let error {
                    note(error, tone: Palette.gaugeBad)
                }

                if let partyCode {
                    hosting(partyCode)
                } else if enteringCode {
                    codeEntry
                } else {
                    MenuButton(title: "Host", style: .primary, disabled: isBusy, action: onHost)
                    if supportsPartyCodes {
                        MenuButton(title: "Join", disabled: isBusy) {
                            enteringCode = true
                        }
                    } else {
                        note("Friends join from the Game Center invite you send them.")
                    }
                }

                if isBusy, partyCode == nil {
                    note("Talking to Game Center…")
                }
            }
            Spacer()
            MenuFooter(onBack: back) {
                if let partyCode {
                    ShareLink(item: shareMessage(partyCode)) {
                        MenuButtonLabel(
                            title: "Share", systemImage: "square.and.arrow.up", style: .primary)
                    }
                    .buttonStyle(PressedTileStyle())
                    .accessibilityLabel("Share code")
                } else if enteringCode {
                    MenuButton(
                        title: "Join", style: .primary,
                        disabled: isBusy || typedCode.trimmed.isEmpty,
                        action: submit)
                }
            }
        }
    }

    /// Out of the code box first; out of the screen after that.
    private func back() {
        if enteringCode, partyCode == nil, !isBusy {
            enteringCode = false
            typedCode = ""
        } else {
            onClose()
        }
    }

    /// The room is open: its code and what it's waiting for. SHARE is at the
    /// foot of the screen.
    @ViewBuilder
    private func hosting(_ code: String) -> some View {
        note("Your code")
        Text(code)
            .font(.system(size: 34, weight: .bold, design: .monospaced))
            .tracking(2)
            .foregroundStyle(Palette.accent)
            .accessibilityLabel("Party code, \(code.map(String.init).joined(separator: " "))")
        note(isBusy ? "Waiting for players…" : "Send this to whoever you're playing.")
    }

    private func shareMessage(_ code: String) -> String {
        let what = room == .duel ? "a duel" : "a battle"
        return "Play \(what) of Time Tiles with me — tap JOIN on \(room.word) and enter \(code)."
    }

    /// Typing someone else's code.
    private var codeEntry: some View {
        VStack(spacing: Spacing.tileGap) {
            note("Enter the host's code")
            if snapshotRendering {
                // The offscreen renderer can't draw a text field; this is
                // what one looks like with the code typed in.
                Text(typedCode)
                    .font(.system(size: 22, weight: .bold, design: .monospaced))
                    .foregroundStyle(Palette.ink)
                    .frame(width: Spacing.menuButtonWidth, height: Spacing.menuButtonHeight)
                    .background(
                        RoundedRectangle(cornerRadius: Spacing.menuButtonRadius, style: .continuous)
                            .fill(Palette.surface))
            } else {
                TextField("CODE", text: $typedCode)
                    .textFieldStyle(.plain)
                    .font(.system(size: 22, weight: .bold, design: .monospaced))
                    .foregroundStyle(Palette.ink)
                    .multilineTextAlignment(.center)
                    .frame(width: Spacing.menuButtonWidth, height: Spacing.menuButtonHeight)
                    .background(
                        RoundedRectangle(cornerRadius: Spacing.menuButtonRadius, style: .continuous)
                            .fill(Palette.surface))
                    #if os(iOS)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    #endif
                    .submitLabel(.join)
                    .onSubmit(submit)
                    .accessibilityLabel("Party code")
            }
        }
    }

    private func submit() {
        guard !isBusy, !typedCode.trimmed.isEmpty else { return }
        onJoin(typedCode)
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
