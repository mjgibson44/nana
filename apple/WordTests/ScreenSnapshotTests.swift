import SwiftUI
import WordBoard
import WordCore
import WordNet
import XCTest

@testable import Word

/// Renders every screen offscreen for eyeballing during development, and
/// asserts they compose at all — a SwiftUI view that traps on layout fails
/// here rather than on a device. PNGs land in /tmp/word-*.png.
@MainActor
final class ScreenSnapshotTests: XCTestCase {
    /// An iPhone 17 Pro, in points.
    static let phone = CGSize(width: 402, height: 874)

    private func write(_ image: CGImage, to name: String) {
        let url = URL(fileURLWithPath: "/tmp/word-\(name).png")
        guard
            let dest = CGImageDestinationCreateWithURL(
                url as CFURL, "public.png" as CFString, 1, nil)
        else { return }
        CGImageDestinationAddImage(dest, image, nil)
        CGImageDestinationFinalize(dest)
    }

    private func render<V: View>(_ view: V, name: String, size: CGSize = phone) throws {
        let renderer = ImageRenderer(
            content: view
                .frame(width: size.width, height: size.height)
                .background(Palette.bg)
                .environment(\.colorScheme, .dark)
                .environment(\.snapshotRendering, true))
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.cgImage, "\(name) failed to render")
        write(image, to: name)
    }

    /// A game a few words in, through the real rules.
    private func playedModel() async throws -> GameModel {
        let model = GameModel()
        model.newGame(seed: "snapshot")
        model.dismissSplash()
        await model.loadDictionary()
        try TestPlays.placeOpener(on: model)
        try TestPlays.attachWord(on: model)
        return model
    }

    func testSoloSetupRenders() throws {
        try render(
            SoloSetupScreen(pace: .regular, onPlay: { _ in }, onClose: {}), name: "solo-setup")
        try render(
            SoloSetupScreen(pace: .fast, onPlay: { _ in }, onClose: {}), name: "solo-setup-fast")
    }

    func testTheGameMenuRenders() throws {
        try render(
            GameMenuView(
                items: [
                    .init(title: "RESULTS", accent: true, action: {}),
                    .init(title: "NEW GAME", action: {}),
                    .init(title: "HOME", action: {}),
                ], onClose: {}),
            name: "game-menu")
    }

    func testHomeScreenRenders() throws {
        try render(
            HomeScreen(hasSavedGame: true, onResume: {}, onSolo: {}, onBattle: {}),
            name: "home")
        try render(
            HomeScreen(hasSavedGame: false, onResume: {}, onSolo: {}, onBattle: {}),
            name: "home-fresh")
    }

    func testGameScreenRenders() async throws {
        let model = try await playedModel()
        // Stage a word with a gap so the word row shows both kinds of tile.
        model.togglePick(0)
        model.addGap()
        model.togglePick(1)
        try render(GameScreen(model: model), name: "game")
    }

    func testGameScreenRendersTheOpener() async throws {
        let model = GameModel()
        model.newGame(seed: "snapshot")
        model.dismissSplash()
        await model.loadDictionary()
        if let (_, indices) = TestPlays.spellableWord(in: model) {
            for index in indices { model.togglePick(index) }
        }
        try render(GameScreen(model: model), name: "game-opener")
    }

    func testSoloResultsRender() throws {
        try render(
            GameEndView(
                score: 114,
                words: [
                    ScoredWord(word: "crossword", points: 36),
                    ScoredWord(word: "orbit", points: 10),
                    ScoredWord(word: "solar", points: 10),
                    ScoredWord(word: "ray", points: 3),
                ],
                restart: {}, onSeeGame: {}, onLeave: {}, scrollable: false),
            name: "results-solo", size: CGSize(width: Self.phone.width, height: 1_300))
    }

    func testBattleResultsRender() throws {
        try render(
            GameEndView(
                score: 84,
                words: [ScoredWord(word: "orbit", points: 10), ScoredWord(word: "tin", points: 3)],
                placing: "1st",
                standings: [
                    .init(id: "a", rank: 1, name: "Ada", isSelf: true, note: "won"),
                    .init(id: "b", rank: 2, name: "Grace", isSelf: false, note: "buried"),
                    .init(id: "c", rank: 3, name: "Katherine", isSelf: false, note: "left"),
                ],
                restart: {}, onSeeGame: {}, onLobby: {}, leaveLabel: "LEAVE", onLeave: {},
                scrollable: false),
            name: "results-battle", size: CGSize(width: Self.phone.width, height: 1_300))
        try render(
            GameEndView(
                score: 40,
                words: [ScoredWord(word: "tin", points: 3)],
                placing: "3rd",
                standings: [
                    .init(id: "a", rank: nil, name: "Ada", isSelf: false, note: "12 tiles"),
                    .init(id: "b", rank: nil, name: "Grace", isSelf: false, note: "20 tiles"),
                    .init(id: "c", rank: nil, name: "Me", isSelf: true, note: "out"),
                ],
                note: "You’re out — 2 still standing.",
                onSeeGame: {}, leaveLabel: "LEAVE", onLeave: {}, scrollable: false),
            name: "results-spectating", size: CGSize(width: Self.phone.width, height: 1_100))
    }

    func testBattleLobbyRenders() throws {
        let state = BattleState(
            phase: .lobby,
            players: [
                BattlePlayer(id: "a", name: "Ada", host: true),
                BattlePlayer(id: "b", name: "Grace"),
                BattlePlayer(id: "c", name: "Katherine", connected: false),
                BattlePlayer(id: "d", name: "Dorothy", waiting: true),
            ],
            game: 1,
            winnerId: nil)
        try render(
            BattleLobbyScreen(
                state: state, selfID: "b", isHost: false, canStart: false,
                isReconnecting: false, rejection: nil, onStart: {}, onLeave: {}),
            name: "battle-lobby")
        try render(
            BattleLobbyScreen(
                state: state, selfID: "a", isHost: true, canStart: true,
                isReconnecting: false, rejection: nil, onStart: {}, onLeave: {}),
            name: "battle-lobby-host")

        // A match of strangers: no START for anyone, the door's rule instead,
        // and then the countdown.
        let party = BattleState(
            phase: .lobby,
            players: [
                BattlePlayer(id: "a", name: "Ada", host: true),
                BattlePlayer(id: "b", name: "Grace"),
                BattlePlayer(id: "c", name: "Katherine"),
            ],
            game: 0,
            winnerId: nil)
        try render(
            BattleLobbyScreen(
                state: party, selfID: "a", isHost: true, canStart: false,
                isReconnecting: false, rejection: nil, autoStart: .party, countdown: nil,
                onStart: {}, onLeave: {}),
            name: "battle-lobby-party")
        var counting = party
        counting.countdown = 3
        try render(
            BattleLobbyScreen(
                state: counting, selfID: "b", isHost: false, canStart: false,
                isReconnecting: false, rejection: nil, autoStart: .party, countdown: 3,
                onStart: {}, onLeave: {}),
            name: "battle-lobby-countdown")
    }

    func testBattleEntryRenders() throws {
        try render(
            BattleEntryScreen(
                supportsPartyCodes: true, partyCode: "ABC-DEF", searching: nil,
                searchStatus: nil, isBusy: true, error: nil,
                onHost: {}, onJoin: { _ in }, onInvite: {}, onDuel: {}, onParty: {},
                onCancelSearch: {}, onClose: {}),
            name: "battle-entry-hosting")
        try render(
            BattleEntryScreen(
                supportsPartyCodes: true, partyCode: nil, searching: nil,
                searchStatus: nil, isBusy: false, error: nil,
                onHost: {}, onJoin: { _ in }, onInvite: {}, onDuel: {}, onParty: {},
                onCancelSearch: {}, onClose: {}),
            name: "battle-entry")
        try render(
            BattleEntryScreen(
                supportsPartyCodes: false, partyCode: nil, searching: nil,
                searchStatus: nil, isBusy: false,
                error: "Game Center couldn’t open matchmaking.",
                onHost: {}, onJoin: { _ in }, onInvite: {}, onDuel: {}, onParty: {},
                onCancelSearch: {}, onClose: {}),
            name: "battle-entry-invites")
        try render(
            BattleEntryScreen(
                supportsPartyCodes: true, partyCode: nil, searching: .party,
                searchStatus: "Connecting 2 of 3…", isBusy: true, error: nil,
                onHost: {}, onJoin: { _ in }, onInvite: {}, onDuel: {}, onParty: {},
                onCancelSearch: {}, onClose: {}),
            name: "battle-entry-searching")
    }

    func testOverlaysRender() throws {
        try render(PauseView(onResume: {}), name: "pause")
        try render(
            SplashView(splash: .speedUp(seconds: 30, tiles: 7), pace: .regular, onDismiss: {}),
            name: "splash")
        try render(NoticeCard(text: "Battle needs Game Center — sign in to play with friends.") {},
            name: "notice")
    }

    func testTheGaugeRendersEveryTone() throws {
        try render(
            VStack(spacing: Spacing.gap) {
                ForEach([(5, PileTone.ok), (18, .warn), (22, .urgent)], id: \.0) { count, tone in
                    VStack(spacing: Spacing.gap / 2) {
                        GameHeaderView(
                            headline: "4444", headlineLabel: "Score", secondsToTiles: 14,
                            tilesComing: 5, onPause: {}, onMenu: {})
                        PileGaugeView(count: count, tone: tone)
                    }
                }
            }
            .padding(Spacing.margin),
            name: "gauge", size: CGSize(width: Self.phone.width, height: 260))
    }

    /// A battle header: the placing, the drip, and the field's piles in one
    /// row of small bars under your own.
    func testTheBattleHeaderRendersEveryonesPile() throws {
        try render(
            VStack(spacing: Spacing.gap / 2) {
                GameHeaderView(
                    headline: "2nd", headlineLabel: "Standing 2nd", secondsToTiles: 8,
                    tilesComing: 2, onPause: nil, onMenu: {})
                PileGaugeView(count: 11, tone: .ok)
                RivalGaugesView(rivals: [
                    .init(id: "a", name: "Ada", tiles: 4, isOut: false),
                    .init(id: "b", name: "Grace", tiles: 14, isOut: false),
                    .init(id: "c", name: "Katherine", tiles: 18, isOut: false),
                    .init(id: "d", name: "Dorothy", tiles: 21, isOut: false),
                    .init(id: "e", name: "Joan", tiles: 24, isOut: true),
                ])
            }
            .padding(Spacing.margin),
            name: "battle-header", size: CGSize(width: Self.phone.width, height: 120))
    }

    /// The word held over a letter: amber when it reads, red when it doesn't.
    func testTheAimPreviewRendersBothVerdicts() async throws {
        let model = try await playedModel()
        let scene = BoardScene(
            metrics: BoardMetrics(bounds: model.bounds, cellBase: CELL_BASE_COMPACT, zoom: 1),
            tiles: model.board.entries.map { (key: $0.key, letter: $0.value) })
        let aimed = model.board.entries.reduce(into: [CellKey: String]()) { into, entry in
            into[entry.key] = entry.value
        }
        for isGood in [true, false] {
            var withAim = scene
            withAim.aim = aimed
            withAim.aimIsGood = isGood
            try render(
                BoardContentView(scene: withAim)
                    .frame(width: 1_600, height: 1_600, alignment: .center)
                    .scaleEffect(0.25),
                name: "aim-\(isGood ? "good" : "bad")",
                size: CGSize(width: 402, height: 402))
        }
    }
}
