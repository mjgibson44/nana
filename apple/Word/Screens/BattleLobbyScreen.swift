import SwiftUI
import WordCore
import WordNet

/// The room a battle is organised in: who's here, who referees, and the one
/// button that starts it.
///
/// The roster is the host's snapshot, so it is the same list on every screen —
/// including the seats being *held* for someone whose connection dropped. That
/// distinction is the lobby's real job: a battle plays on without a
/// disconnected player rather than pausing for them (plan §7.4), so their seat
/// has to read as held rather than gone, or the field looks like it lost
/// someone it hasn't.
struct BattleLobbyScreen: View {
    var state: BattleState?
    var selfID: String
    var hostID: String?
    var isHost: Bool
    var canStart: Bool
    var isReconnecting: Bool
    /// Set when the host refused us — a version mismatch or a full lobby.
    var rejection: String?
    var onStart: () -> Void
    var onLeave: () -> Void
    var scrollable = true

    private var players: [BattlePlayer] {
        (state?.players ?? []).filter { !$0.left }
    }

    var body: some View {
        PageScaffold(
            eyebrow: BATTLE_ROYALE_INFO.name.uppercased(),
            title: "Lobby",
            onClose: onLeave,
            scrollable: scrollable
        ) {
            if let rejection {
                noticeCard(
                    icon: "exclamationmark.triangle.fill",
                    text: rejection,
                    tone: Ink.badInk)
            } else if isReconnecting {
                noticeCard(
                    icon: "antenna.radiowaves.left.and.right",
                    text: "Reconnecting — your seat is held for "
                        + "\(Int(RECONNECT_GRACE_SECONDS)) seconds.",
                    tone: Ink.warnInk)
            }

            HStack(spacing: 12) {
                PageStat(
                    value: "\(players.count)",
                    label: players.count == 1 ? "Player" : "Players")
                PageStat(value: "\(BATTLE_MAX_PLAYERS)", label: "Seats")
            }

            PageSection("Who's here") {
                if players.isEmpty {
                    Text("Waiting for the roster…")
                        .font(.callout)
                        .foregroundStyle(Ink.ink.opacity(0.7))
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    VStack(spacing: 5) {
                        ForEach(players) { player in
                            seatRow(player)
                        }
                    }
                }
            }

            if isHost {
                VStack(spacing: 8) {
                    Button("Start the battle", action: onStart)
                        .buttonStyle(InkActionButtonStyle(primary: true))
                        .disabled(!canStart)
                    if !canStart {
                        Text(
                            "A battle needs at least \(BATTLE_MIN_PLAYERS) players."
                        )
                        .font(.caption)
                        .foregroundStyle(Ink.ink.opacity(0.7))
                    }
                }
            } else {
                Text("Waiting for the host to start.")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(Ink.ink.opacity(0.7))
            }

            Button("Leave", action: onLeave)
                .buttonStyle(InkActionButtonStyle())
        }
    }

    @ViewBuilder
    private func seatRow(_ player: BattlePlayer) -> some View {
        HStack(spacing: 10) {
            Image(systemName: player.host ? "crown.fill" : "person.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Ink.ink.opacity(player.connected ? 0.85 : 0.35))
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 1) {
                Text(player.id == selfID ? "\(player.name) (you)" : player.name)
                    .font(.callout.bold())
                    .foregroundStyle(Ink.ink.opacity(player.connected ? 1 : 0.55))
                if let note = note(for: player) {
                    Text(note)
                        .font(.caption2)
                        .foregroundStyle(Ink.ink.opacity(0.65))
                }
            }

            Spacer(minLength: 4)

            if !player.connected {
                // Held, not lost — the battle plays on around them.
                Text("Holding")
                    .font(.caption2.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Ink.warnBg))
                    .foregroundStyle(Ink.warnInk)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 10).fill(Ink.surface))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Ink.lineSoft, lineWidth: 2))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel(for: player))
    }

    private func note(for player: BattlePlayer) -> String? {
        if player.host { return "Refereeing" }
        if player.waiting { return "Joined mid-game — in from the next one" }
        return nil
    }

    private func accessibilityLabel(for player: BattlePlayer) -> String {
        var parts = [player.id == selfID ? "\(player.name), you" : player.name]
        if player.host { parts.append("refereeing") }
        if player.waiting { parts.append("waiting for the next game") }
        if !player.connected { parts.append("connection dropped, seat held") }
        return parts.joined(separator: ", ")
    }

    @ViewBuilder
    private func noticeCard(icon: String, text: String, tone: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .bold))
            Text(text)
                .font(.caption.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(tone)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Ink.surfaceAlt))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(tone.opacity(0.5), lineWidth: 2))
        .accessibilityElement(children: .combine)
    }
}
