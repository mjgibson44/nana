import SwiftUI
import WordCore

/// The screen the app opens on (HomeScreen.tsx): the game's name, the mode
/// doors side by side, and — set a little apart — the three things that aren't
/// a game. A door says only what the mode is called; what it *is* gets
/// explained once, in the card that fronts its first game.
struct HomeScreen: View {
    var hasSavedGame: Bool
    /// Shows Game Center's own access point over the home screen. Off in
    /// snapshot tests and previews — it's a UIKit/AppKit overlay the renderer
    /// can't draw, and it needs a signed-in player to say anything.
    var showsGameCenter = false
    var daily: DailyStatus?
    var onResume: () -> Void
    var onDaily: () -> Void
    var onChoose: (GameDoor) -> Void
    var onTutorial: () -> Void
    var onStats: () -> Void
    var onSettings: () -> Void
    /// Off in snapshot tests: `ImageRenderer` draws nothing inside a
    /// `ScrollView` (same reason `SoloSummaryView` carries this flag).
    var scrollable = true

    /// What the home screen asks a window to be, at minimum.
    ///
    /// It scrolls, so its *content* height must not become the window's floor
    /// — that is the same failure the board caused (`WindowSizingTests`), just
    /// slower: every row added here would ratchet the minimum window up until
    /// one day it didn't fit a screen. Declaring an ideal decouples the two,
    /// and content taller than the window does what a ScrollView is for.
    private static let idealHeight: CGFloat = 360

    @ViewBuilder
    var body: some View {
        if scrollable {
            ScrollView { content }
                .frame(idealHeight: Self.idealHeight)
                .background(Ink.bg.ignoresSafeArea())
                .modifier(GameCenterAccessPoint(active: showsGameCenter))
        } else {
            content.background(Ink.bg)
        }
    }

    private var content: some View {
        VStack(spacing: 26) {
                VStack(spacing: 6) {
                    Text("Time Tiles")
                        .font(.system(size: 46, weight: .heavy, design: .rounded))
                        .foregroundStyle(Ink.ink)
                    Text("Race to weave every tile into one crossword.")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(Ink.ink.opacity(0.7))
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 12)

                // A game the OS took away mid-run comes back first: it's the
                // one thing on this screen the player didn't choose to leave.
                if hasSavedGame {
                    Button(action: onResume) {
                        HStack(spacing: 10) {
                            Image(systemName: "play.fill")
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Resume your game")
                                    .font(.callout.bold())
                                Text("Picked up where you left off")
                                    .font(.caption)
                                    .foregroundStyle(Ink.inkInvert.opacity(0.75))
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Ink.inkInvert)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Ink.ink))
                }

                // The Daily Deal is a row rather than a third door card: it's
                // the one mode with state to report — today's date, whether
                // it's been played, and the streak riding on it.
                if let daily {
                    dailyRow(daily)
                }

                HStack(spacing: 12) {
                    doorCard(.solo, icon: "person.fill")
                    doorCard(.battle, icon: "crown.fill")
                }

                HStack(spacing: 10) {
                    homeAction("Tutorial", icon: "info.circle.fill", action: onTutorial)
                    homeAction("Stats", icon: "chart.bar.fill", action: onStats)
                    homeAction("Settings", icon: "gearshape.fill", action: onSettings)
                }
            }
        .frame(maxWidth: 520)
        .padding(.horizontal, 22)
        .padding(.vertical, 28)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func dailyRow(_ daily: DailyStatus) -> some View {
        Button(action: onDaily) {
            HStack(spacing: 12) {
                VStack(spacing: 1) {
                    Text(daily.deal.monthLabel.uppercased())
                        .font(.system(size: 10, weight: .heavy, design: .rounded))
                        .foregroundStyle(Ink.ink.opacity(0.65))
                    Text(daily.deal.dayOfMonthLabel)
                        .font(.system(size: 21, weight: .heavy, design: .rounded))
                        .foregroundStyle(Ink.ink)
                }
                .frame(width: 46)
                .padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 10).fill(Ink.surfaceAlt))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Ink.line, lineWidth: 2))

                VStack(alignment: .leading, spacing: 2) {
                    Text(DAILY_DEAL_INFO.name)
                        .font(.callout.bold())
                        .foregroundStyle(Ink.ink)
                    // One line, truncating: this row sits on a screen that has
                    // to survive a small window, and a wrapping tagline drives
                    // the whole home screen's minimum height up with it.
                    Text(subtitle(for: daily))
                        .font(.caption)
                        .foregroundStyle(Ink.ink.opacity(0.7))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if daily.streak > 1 {
                    Text("\(daily.streak)-day streak")
                        .font(.caption2.bold())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Ink.okBg))
                        .foregroundStyle(Ink.okInk)
                        .accessibilityLabel("\(daily.streak) day streak")
                }

                Image(systemName: daily.isPlayed ? "checkmark.circle.fill" : "chevron.right")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Ink.ink.opacity(daily.isPlayed ? 0.85 : 0.5))
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        .background(RoundedRectangle(cornerRadius: 14).fill(Ink.surface))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Ink.ink, lineWidth: 3))
        .accessibilityLabel("\(DAILY_DEAL_INFO.name), \(daily.deal.date)")
        .accessibilityHint(subtitle(for: daily))
    }

    private func subtitle(for daily: DailyStatus) -> String {
        if let result = daily.result {
            return "Played · \(result.score) points"
        }
        return DAILY_DEAL_INFO.tagline
    }

    private func doorCard(_ door: GameDoor, icon: String) -> some View {
        let info = DOOR_INFO[door]
        return Button {
            onChoose(door)
        } label: {
            VStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 27, weight: .bold))
                Text(info?.name ?? door.rawValue.capitalized)
                    .font(.title3.bold())
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 26)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Ink.ink)
        .background(RoundedRectangle(cornerRadius: 16).fill(Ink.surface))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Ink.ink, lineWidth: 3))
        .accessibilityLabel(info?.name ?? door.rawValue)
        .accessibilityHint(info?.tagline ?? "")
    }

    private func homeAction(
        _ label: String, icon: String, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .bold))
                Text(label)
                    .font(.caption.bold())
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Ink.ink)
        .background(RoundedRectangle(cornerRadius: 12).fill(Ink.surfaceAlt))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Ink.line, lineWidth: 2))
    }
}

/// A mode's card, standing between choosing it and playing it (ModeInfoDialog.tsx):
/// what it is, and its headline rules. Each is shown once ever — a mode's the
/// first time its door is opened, the tutorial's before a player's first game.
struct ModeInfoCard: View {
    var info: ModeInfo
    var confirmLabel: String
    var skipLabel: String?
    var onConfirm: () -> Void
    var onSkip: (() -> Void)?

    var body: some View {
        DialogCard(dismiss: onSkip ?? onConfirm) {
            VStack(spacing: 14) {
                VStack(spacing: 5) {
                    Text(info.name)
                        .font(.system(size: 27, weight: .heavy, design: .rounded))
                        .foregroundStyle(Ink.ink)
                    Text(info.tagline)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(Ink.ink.opacity(0.72))
                        .multilineTextAlignment(.center)
                }

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(info.details, id: \.self) { detail in
                        HStack(alignment: .top, spacing: 8) {
                            Circle()
                                .fill(Ink.ink.opacity(0.5))
                                .frame(width: 5, height: 5)
                                .padding(.top, 6)
                            Text(detail)
                                .font(.callout)
                                .foregroundStyle(Ink.ink.opacity(0.85))
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 10) {
                    if let skipLabel, let onSkip {
                        Button(skipLabel, action: onSkip)
                            .buttonStyle(InkActionButtonStyle())
                    }
                    Button(confirmLabel, action: onConfirm)
                        .buttonStyle(InkActionButtonStyle(primary: true))
                }
            }
        }
        .accessibilityLabel("About \(info.name)")
    }
}

/// The setup sheet a configurable mode raises on the way in (SetupDialog.tsx):
/// its settings, and a Play button under them. Nothing is decided until Play,
/// so backing out changes nothing.
struct SoloSetupCard: View {
    @State var pace: SoloPace
    var onPlay: (SoloPace) -> Void
    var onDismiss: () -> Void

    var body: some View {
        DialogCard(dismiss: onDismiss) {
            VStack(spacing: 16) {
                VStack(spacing: 4) {
                    Text(SOLO_INFO.name)
                        .font(.system(size: 25, weight: .heavy, design: .rounded))
                    Text("Set up your game")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(Ink.ink.opacity(0.7))
                }

                VStack(alignment: .leading, spacing: 7) {
                    Text("SPEED")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(0.9)
                        .foregroundStyle(Ink.ink.opacity(0.6))
                    Picker("Speed", selection: $pace) {
                        ForEach(PACE_OPTIONS, id: \.pace) { option in
                            Text(option.name).tag(option.pace)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                Button("Play") { onPlay(pace) }
                    .buttonStyle(InkActionButtonStyle(primary: true))
                    .frame(minWidth: 160)
            }
        }
        .accessibilityLabel("\(SOLO_INFO.name) — set up your game")
    }
}

/// The shared chrome every card sits in: a dimmed backdrop that dismisses on
/// tap, and an inked panel with a close button in its corner.
struct DialogCard<Content: View>: View {
    var dismiss: () -> Void
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            Color.black.opacity(0.42)
                .ignoresSafeArea()
                .onTapGesture(perform: dismiss)
                .accessibilityHidden(true)

            content
                .padding(.horizontal, 26)
                .padding(.vertical, 24)
                .frame(maxWidth: 420)
                .background(RoundedRectangle(cornerRadius: 18).fill(Ink.surface))
                .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Ink.ink, lineWidth: 3))
                .overlay(alignment: .topTrailing) {
                    Button(action: dismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Ink.ink)
                            .padding(9)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close")
                }
                .shadow(color: .black.opacity(0.3), radius: 22, y: 10)
                .padding(22)
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }
}
