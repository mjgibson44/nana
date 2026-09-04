import SwiftUI
import WordCore

/// A card that briefly covers the board — the opening deal, a speed-up, or
/// a game coming back from being put away. Tap anywhere to dismiss.
struct SplashView: View {
    var splash: SoloSplash
    var pace: SoloPace
    var onDismiss: () -> Void

    var body: some View {
        ZStack {
            Palette.bg.opacity(0.82)
                .ignoresSafeArea()
            VStack(spacing: Spacing.gap) {
                TileBlock {
                    ForEach(Array(title.split(separator: " ").enumerated()), id: \.offset) { _, word in
                        TileWord(text: String(word), style: .accent)
                    }
                }
                Text(note)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Palette.inkSoft)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 300)
            }
            .padding(Spacing.margin)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onDismiss)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(named: "Dismiss", onDismiss)
    }

    private var title: String {
        switch splash {
        case .start: "GAME ON"
        case .speedUp: "FASTER"
        case .resumed: "WELCOME BACK"
        }
    }

    private var note: String {
        switch splash {
        case .start:
            "\(ENDLESS_START_TILES) tiles · "
                + "\(formatSeconds(Double(endlessInitialSeconds(pace)))) until more arrive"
        case let .speedUp(seconds, tiles):
            "+\(tiles) tiles every \(formatSeconds(Double(seconds))) from here"
        case .resumed:
            "Your game is where you left it — the clock starts when you tap."
        }
    }
}

/// The pause screen hides the board: a stopped clock mustn't be planning time.
struct PauseView: View {
    var onResume: () -> Void

    @FocusState private var resumeFocused: Bool

    var body: some View {
        ScreenColumn {
            Spacer()
            TileBlock {
                TileWord(text: "PAUSED", style: .accent)
                TileWordButton(text: "RESUME", action: onResume)
                    .focused($resumeFocused)
                    .keyboardShortcut(.cancelAction)
            }
            Spacer()
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .task { resumeFocused = true }
    }
}

/// The single toast slot over the board (App.tsx:415, 1746–1750).
struct ToastView: View {
    var toast: GameToast
    var onExpire: (Int) -> Void

    var body: some View {
        Text(toast.text)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Palette.ink)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: Spacing.tileRadius, style: .continuous)
                    .fill(Palette.surfaceRaised))
            .padding(.top, 10)
            .padding(.horizontal, 10)
            .transition(.opacity)
            .task(id: toast.serial) {
                // Tiles landing, a refusal, an achievement: things the board
                // can't show. The web's toast is an aria-live region; this is
                // its announcement (plan §6.6).
                AccessibilityNotification.Announcement(toast.text).post()
                try? await Task.sleep(for: .seconds(2.5))
                onExpire(toast.serial)
            }
            .accessibilityHidden(true)
            .allowsHitTesting(false)
    }
}

/// A short notice over a screen — one line of text and a way back.
struct NoticeCard: View {
    var text: String
    var dismissLabel = "BACK"
    var onDismiss: () -> Void

    var body: some View {
        ZStack {
            Palette.bg.opacity(0.82)
                .ignoresSafeArea()
                .onTapGesture(perform: onDismiss)
                .accessibilityHidden(true)
            VStack(spacing: Spacing.gap) {
                Text(text)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Palette.ink)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 300)
                TileWordButton(text: dismissLabel, action: onDismiss)
            }
            .padding(Spacing.margin)
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }
}
