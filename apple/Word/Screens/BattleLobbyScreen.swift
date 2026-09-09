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
    /// The host changing what the room plays by. Nil for a client, which is
    /// what makes the same rows read-only there.
    var onBoardView: ((BattleBoardView) -> Void)? = nil
    var onModifier: ((SoloModifier) -> Void)? = nil

    private var players: [BattlePlayer] {
        (state?.players ?? []).filter { !$0.left }
    }

    var body: some View {
        ScreenColumn {
            Spacer()
            VStack(spacing: Spacing.tileGap) {
                VStack(spacing: Spacing.tileGap) {
                    TileTitle(text: "LOBBY")
                        .accessibilityAddTraits(.isHeader)
                    if mode == .occupy {
                        TileWord(text: "OCCUPY", style: .dim)
                            .accessibilityLabel("Occupy")
                    }
                }
                .padding(.bottom, Spacing.section - Spacing.tileGap)

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

                settings

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
                    TileWordButton(
                        text: "START", style: canStart ? .accentButton : .plain,
                        disabled: !canStart, action: onStart)
                    if !canStart {
                        note(
                            mode == .occupy
                                ? "Occupy needs \(OCCUPY_MIN_PLAYERS) to \(OCCUPY_MAX_PLAYERS) players."
                                : "A battle needs at least \(BATTLE_MIN_PLAYERS) players.")
                    }
                } else {
                    note("Waiting for the host to start.")
                }

                TileWordButton(text: "LEAVE", action: onLeave)
                    .padding(.top, Spacing.section)
            }
            Spacer()
        }
    }

    /// What this room plays by, as the snapshot says it — so a client is
    /// reading the rule it will actually play under rather than a guess, and
    /// the host is looking at the thing it just changed.
    ///
    /// Each row shows its *value* and cycles on tap, rather than offering
    /// every option as its own row: a lobby already carries a roster of up to
    /// eight, and this has to sit under it on a phone.
    @ViewBuilder
    private var settings: some View {
        // Occupy has one layout and no modifiers; a game in progress has
        // settled its rules already.
        if mode == .battle, state?.phase == .lobby {
            VStack(spacing: Spacing.tileGap) {
                if OPEN_BOARD_VIEWS.count > 1 {
                    settingRow(
                        caption: "Board",
                        value: boardViewName,
                        change: onBoardView.map { change in
                            { change(cycled(boardView, in: OPEN_BOARD_VIEWS.map(\.view))) }
                        })
                }
                settingRow(
                    caption: "Squares",
                    value: modifierName,
                    change: onModifier.map { change in
                        { change(cycled(modifier, in: MODIFIER_OPTIONS.map(\.modifier))) }
                    })
                note(settingsNote)
            }
        }
    }

    private var boardView: BattleBoardView { state?.boardView ?? .separate }
    private var modifier: SoloModifier { state?.modifier ?? .none }

    private var boardViewName: String {
        BOARD_VIEW_OPTIONS.first { $0.view == boardView }?.name ?? "Separate"
    }

    private var modifierName: String {
        MODIFIER_OPTIONS.first { $0.modifier == modifier }?.name ?? "Clear"
    }

    /// One line for the whole room, rather than one per setting: what these
    /// two add up to is the game, and reading it as a sentence is how you
    /// tell whether it's the one you meant to set up.
    private var settingsNote: String {
        let board =
            OPEN_BOARD_VIEWS.count > 1 ? boardViewNote(boardView) + " " : ""
        switch modifier {
        case .none:
            return board + "No squares to chase — just the drip and the pile."
        case .prizes:
            return board
                + "Squares light up on every board at once: gold pays up to "
                + "\(GOLD_TOP_POINTS) points, blue clears up to \(SALVAGE_TOP_TILES) "
                + "tiles off your pile. Both fall in value while you think."
        }
    }

    /// The next option along, wrapping. A value that isn't offered any more
    /// lands on the first one rather than sticking.
    private func cycled<T: Equatable>(_ value: T, in options: [T]) -> T {
        guard let at = options.firstIndex(of: value) else { return options[0] }
        return options[(at + 1) % options.count]
    }

    @ViewBuilder
    private func settingRow(
        caption: String, value: String, change: (() -> Void)?
    ) -> some View {
        VStack(spacing: 2) {
            Text(caption.uppercased())
                .font(.system(size: 11, weight: .bold))
                .tracking(1.5)
                .foregroundStyle(Palette.inkSoft)
            if let change {
                TileWordButton(text: value.uppercased(), style: .accent, action: change)
                    .accessibilityLabel("\(caption): \(value). Tap to change.")
            } else {
                // A client's copy: the room's rule, not a control.
                TileWord(text: value.uppercased(), style: .dim)
                    .accessibilityLabel("\(caption): \(value)")
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
