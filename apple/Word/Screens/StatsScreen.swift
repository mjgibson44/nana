import SwiftUI
import WordCore

/// The record page (StatsPage.tsx): how many games have been finished, and the
/// recent ones with their scores and when they were played.
struct StatsScreen: View {
    var stats: Stats
    /// The cross-device picture (§9.1). Separate from `stats`, which stays the
    /// web-compatible local blob.
    var progress = MergedProgress()
    var earned: Set<AchievementID> = []
    var dailyStreak = 0
    var onClose: () -> Void
    var scrollable = true

    private static let stamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    var body: some View {
        PageScaffold(
            eyebrow: "Your record", title: "Stats", onClose: onClose, scrollable: scrollable
        ) {
            HStack(spacing: 12) {
                PageStat(value: "\(stats.gamesPlayed)",
                    label: stats.gamesPlayed == 1 ? "Game played" : "Games played")
                if !stats.recent.isEmpty {
                    PageStat(value: "\(best)", label: "Best recent score")
                }
            }

            if dailyStreak > 0 || !progress.dailyDays.isEmpty {
                HStack(spacing: 12) {
                    PageStat(value: "\(progress.dailyDays.count)", label: "Daily Deals")
                    if dailyStreak > 0 {
                        PageStat(value: "\(dailyStreak)", label: "Day streak")
                    }
                    if progress.bestDailyScore > 0 {
                        PageStat(value: "\(progress.bestDailyScore)", label: "Best daily")
                    }
                }
            }

            PageSection("Recent games") {
                if stats.recent.isEmpty {
                    Text("Nothing here yet — finish a game and it lands on this page.")
                        .font(.callout)
                        .foregroundStyle(Ink.ink.opacity(0.7))
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    VStack(spacing: 5) {
                        ForEach(stats.recent, id: \.at) { game in
                            HStack(spacing: 10) {
                                Text(Self.stamp.string(from: date(of: game)))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Ink.ink.opacity(0.7))
                                Spacer(minLength: 6)
                                Text("\(game.words) \(game.words == 1 ? "word" : "words")")
                                    .font(.caption)
                                    .foregroundStyle(Ink.ink.opacity(0.6))
                                Text("\(game.score)")
                                    .font(.caption.bold().monospacedDigit())
                                    .foregroundStyle(Ink.okInk)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 3)
                                    .background(Capsule().fill(Ink.okBg))
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .background(RoundedRectangle(cornerRadius: 10).fill(Ink.surface))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .strokeBorder(Ink.lineSoft, lineWidth: 2))
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
            }

            PageSection("Achievements") {
                // Shown from local progress rather than Game Center: the game
                // is fully playable signed out (§7.1), so the badges have to be
                // too. Game Center mirrors them once there's an account.
                VStack(spacing: 5) {
                    ForEach(AchievementID.allCases, id: \.rawValue) { id in
                        let got = earned.contains(id)
                        HStack(spacing: 10) {
                            Image(systemName: got ? "checkmark.seal.fill" : "seal")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(got ? Ink.okInk : Ink.ink.opacity(0.3))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(id.title)
                                    .font(.caption.bold())
                                    .foregroundStyle(Ink.ink.opacity(got ? 1 : 0.55))
                                Text(id.detail)
                                    .font(.caption2)
                                    .foregroundStyle(Ink.ink.opacity(0.6))
                                    .lineLimit(2)
                            }
                            Spacer(minLength: 4)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Ink.surface))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(Ink.lineSoft, lineWidth: 2))
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(
                            "\(id.title), \(got ? "earned" : "not yet earned"). \(id.detail)")
                    }
                }
            }

            Button("Back to the game", action: onClose)
                .buttonStyle(InkActionButtonStyle(primary: true))
        }
    }

    private var best: Int {
        stats.recent.reduce(0) { max($0, $1.score) }
    }

    /// The web stores milliseconds since the epoch (stats.ts).
    private func date(of game: GameRecord) -> Date {
        Date(timeIntervalSince1970: game.at / 1000)
    }
}

/// The options page (SettingsPage.tsx): the theme choice, the sound switch,
/// and — new on Apple platforms — haptics (plan §6.5).
struct SettingsScreen: View {
    @Bindable var settings: AppSettings
    var onClose: () -> Void
    var scrollable = true

    var body: some View {
        PageScaffold(
            eyebrow: "Options", title: "Settings", onClose: onClose, scrollable: scrollable
        ) {
            PageSection("Appearance") {
                VStack(spacing: 8) {
                    ForEach(ThemePreference.allCases) { option in
                        Button {
                            settings.theme = option
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(option.label).font(.callout.bold())
                                    Text(option.detail)
                                        .font(.caption)
                                        .foregroundStyle(Ink.ink.opacity(0.65))
                                }
                                Spacer()
                                if settings.theme == option {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 13, weight: .bold))
                                }
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 11)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Ink.ink)
                        .background(
                            RoundedRectangle(cornerRadius: 11)
                                .fill(settings.theme == option ? Ink.surfaceAlt : Ink.surface))
                        .overlay(
                            RoundedRectangle(cornerRadius: 11).strokeBorder(
                                settings.theme == option ? Ink.ink : Ink.lineSoft,
                                lineWidth: settings.theme == option ? 3 : 2))
                        .accessibilityAddTraits(
                            settings.theme == option ? [.isButton, .isSelected] : .isButton)
                    }
                }
            }

            PageSection("Audio") {
                VStack(spacing: 8) {
                    settingToggle(
                        "Game sound",
                        detail: "Countdown ticks, tiles landing, words going down",
                        isOn: $settings.soundEnabled)
                    #if os(iOS)
                    settingToggle(
                        "Haptics",
                        detail: "A tap in the hand for landings and warnings",
                        isOn: $settings.hapticsEnabled)
                    #endif
                }
            }

            Button("Done", action: onClose)
                .buttonStyle(InkActionButtonStyle(primary: true))
        }
    }

    private func settingToggle(
        _ label: String, detail: String, isOn: Binding<Bool>
    ) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 1) {
                Text(label).font(.callout.bold())
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(Ink.ink.opacity(0.65))
            }
        }
        .tint(Ink.ink)
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(RoundedRectangle(cornerRadius: 11).fill(Ink.surface))
        .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(Ink.lineSoft, lineWidth: 2))
    }
}

/// The full-screen page chrome both of the above wear. Built as one opaque
/// window-filling cover rather than `fullScreenCover`, which doesn't exist on
/// native macOS (plan §6.1).
struct PageScaffold<Content: View>: View {
    var eyebrow: String
    var title: String
    var onClose: () -> Void
    /// Off in snapshot tests — `ImageRenderer` draws nothing inside a
    /// `ScrollView`.
    var scrollable = true
    @ViewBuilder var content: Content

    var body: some View {
        page
            .background(Ink.bg.ignoresSafeArea())
            .overlay(alignment: .topTrailing) {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Ink.ink)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Ink.surface))
                    .overlay(Circle().strokeBorder(Ink.ink, lineWidth: 2))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
            .padding(16)
        }
        .accessibilityAddTraits(.isModal)
    }

    @ViewBuilder
    private var page: some View {
        if scrollable {
            ScrollView { body(of: content) }
        } else {
            body(of: content)
        }
    }

    private func body(of content: Content) -> some View {
        VStack(spacing: 22) {
            VStack(spacing: 4) {
                Text(eyebrow.uppercased())
                    .font(.caption.bold())
                    .tracking(1.1)
                    .foregroundStyle(Ink.ink.opacity(0.65))
                Text(title)
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                    .foregroundStyle(Ink.ink)
            }
            content
        }
        .frame(maxWidth: 560)
        .padding(.horizontal, 22)
        .padding(.vertical, 36)
        .frame(maxWidth: .infinity)
    }
}

struct PageStat: View {
    var value: String
    var label: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 34, weight: .heavy, design: .rounded))
                .monospacedDigit()
            Text(label.uppercased())
                .font(.system(size: 10, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(Ink.ink.opacity(0.65))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: 16).fill(Ink.surface))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Ink.ink, lineWidth: 3))
        .accessibilityElement(children: .combine)
    }
}

struct PageSection<Content: View>: View {
    var title: String
    @ViewBuilder var content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .bold))
                .tracking(0.9)
                .foregroundStyle(Ink.ink.opacity(0.6))
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
