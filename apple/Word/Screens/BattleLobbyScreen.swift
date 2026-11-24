import SwiftUI
import WordCore
import WordNet

/// The room a battle is organised in: who's here, who referees, and the one
/// button that starts it — or, in a match of strangers, the countdown that
/// starts it by itself.
///
/// The roster is the host's snapshot, so it is the same list on every screen —
/// including the seats being *held* for someone whose connection dropped. A
/// battle plays on without a disconnected player rather than pausing for
/// them (plan §7.4), so their seat has to read as held rather than gone.
struct BattleLobbyScreen: View {
    /// Which game the room plays: how many it seats, and what the note says.
    var mode: GameMode = .battle
    /// A duel or a battle: the room's name, and what an empty seat is waiting for.
    var room: RoomKind = .battle
    var state: BattleState?
    var selfID: String
    var isHost: Bool
    var canStart: Bool
    var isReconnecting: Bool
    /// Set when the host refused us — a version mismatch or a full lobby.
    var rejection: String?
    /// Non-nil for a random match, which deals itself on this rule.
    var autoStart: AutoStartRule? = nil
    /// Seconds until a random match deals, while it's counting down.
    var countdown: Int? = nil
    var onStart: () -> Void
    var onLeave: () -> Void

    private var players: [BattlePlayer] {
        (state?.players ?? []).filter { !$0.left }
    }

    var body: some View {
        ScreenColumn {
            Spacer()
            VStack(spacing: Spacing.tileGap) {
                ScreenHeader(mode == .occupy ? "OCCUPY" : room.word)

                if let rejection {
                    note(rejection, tone: Palette.gaugeBad)
                } else if isReconnecting {
                    note(
                        "Reconnecting — your seat is held for "
                            + "\(Int(RECONNECT_GRACE_SECONDS)) seconds.",
                        tone: Palette.gaugeWarn)
                }

                roster
                    .padding(.vertical, Spacing.gap)

                if let countdown {
                    // Decided: everyone's here, and the deal is seconds away.
                    BigTile(text: "\(countdown)")
                        .accessibilityLabel("Starting in \(countdown)")
                    note("Starting…")
                } else if let autoStart {
                    switch autoStart {
                    case .duel:
                        note(
                            players.count < (mode == .occupy ? OCCUPY_MIN_PLAYERS : BATTLE_MIN_PLAYERS)
                                ? "Waiting for an opponent…" : "Starting…")
                    case .party:
                        note("Starts \(Int(PARTY_IDLE_SECONDS)) seconds after the last player arrives.")
                    }
                } else if isHost {
                    if !canStart {
                        note(
                            mode == .occupy
                                ? "Occupy needs \(OCCUPY_MIN_PLAYERS) to \(OCCUPY_MAX_PLAYERS) players."
                                : room == .duel
                                    ? "Waiting for an opponent…"
                                    : "A battle needs at least \(BATTLE_MIN_PLAYERS) players.")
                    }
                } else {
                    note("Waiting for the host to start.")
                }
            }
            Spacer()
            MenuFooter(onBack: onLeave) {
                // START is the host's alone, and only in a room that waits
                // for one rather than counting itself down.
                if isHost, autoStart == nil, countdown == nil {
                    MenuButton(
                        title: "Start", style: canStart ? .primary : .secondary,
                        disabled: !canStart, action: onStart)
                }
            }
        }
    }

    @ViewBuilder
    private var roster: some View {
        VStack(spacing: Spacing.tileGap) {
            if players.isEmpty {
                note("Waiting for the roster…")
            } else {
                ForEach(players) { player in
                    seatRow(player)
                }
            }
        }
        .frame(width: Spacing.tile * 8 + Spacing.tileGap * 7)
    }

    private func seatRow(_ player: BattlePlayer) -> some View {
        HStack(spacing: 8) {
            Text(player.name.uppercased())
                .font(.system(size: 15, weight: .bold))
                .tracking(1)
                .foregroundStyle(Palette.ink.opacity(player.connected ? 1 : 0.5))
                .lineLimit(1)
            if player.id == selfID {
                chip("YOU")
            }
            if player.host {
                chip("HOST")
            }
            Spacer(minLength: 6)
            if let status = status(for: player) {
                Text(status)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(player.connected ? Palette.inkSoft : Palette.gaugeWarn)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: Spacing.tile)
        .background(
            RoundedRectangle(cornerRadius: Spacing.tileRadius, style: .continuous)
                .fill(Palette.surface))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel(for: player))
    }

    private func chip(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .bold))
            .tracking(1)
            .foregroundStyle(Palette.accent)
    }

    private func status(for player: BattlePlayer) -> String? {
        // Held, not lost — the battle plays on around them.
        if !player.connected { return "holding" }
        if player.waiting { return "next game" }
        return nil
    }

    private func accessibilityLabel(for player: BattlePlayer) -> String {
        var parts = [player.id == selfID ? "\(player.name), you" : player.name]
        if player.host { parts.append("refereeing") }
        if player.waiting { parts.append("waiting for the next game") }
        if !player.connected { parts.append("connection dropped, seat held") }
        return parts.joined(separator: ", ")
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
