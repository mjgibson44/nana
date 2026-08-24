import Observation
import SwiftUI
import WordCore

/// Light / dark / follow the device — the web's `nana.theme.v1` preference
/// (theme.ts), where "system" means no override at all.
enum ThemePreference: String, CaseIterable, Identifiable {
    case light
    case dark
    case system

    var id: String { rawValue }

    var label: String {
        switch self {
        case .light: "Light"
        case .dark: "Dark"
        case .system: "System"
        }
    }

    var detail: String {
        switch self {
        case .light: "Bright board, dark letters"
        case .dark: "Dark board, light letters"
        case .system: "Follow your device"
        }
    }

    /// `nil` = let the environment decide, exactly like removing the web's
    /// `data-theme` attribute.
    var colorScheme: ColorScheme? {
        switch self {
        case .light: .light
        case .dark: .dark
        case .system: nil
        }
    }
}

/// The player's preferences, persisted through WordCore's storage helpers so
/// the keys and defensive-parsing semantics stay identical to the web's.
@Observable @MainActor
final class AppSettings {
    /// The web's theme key (theme.ts:9).
    private static let themeKey = "nana.theme.v1"
    /// New on Apple platforms — sound has its own switch on the web, and
    /// haptics get a separate one (plan §6.5).
    private static let hapticsKey = "nana.haptics.v1"
    /// The Daily Deal's explainer is shown once, like a door's. It isn't a
    /// `GameDoor` — the mode is a row on the home screen with its own state,
    /// not one of the two mode cards — so it keeps its own flag rather than
    /// bending the ported onboarding module around it.
    private static let dailySeenKey = "nana.daily.seen.v1"

    private let store: KeyValueStore

    var theme: ThemePreference {
        didSet {
            guard theme != oldValue else { return }
            store.set(Self.themeKey, theme.rawValue)
        }
    }

    var soundEnabled: Bool {
        didSet {
            guard soundEnabled != oldValue else { return }
            WordCore.setSoundEnabled(soundEnabled, in: store)
        }
    }

    var hapticsEnabled: Bool {
        didSet {
            guard hapticsEnabled != oldValue else { return }
            store.set(Self.hapticsKey, hapticsEnabled ? "on" : "off")
        }
    }

    /// The pace the setup sheet opens on — the last one played (setups.ts).
    var pace: SoloPace {
        didSet {
            guard pace != oldValue else { return }
            saveSoloSetup(SoloSetup(pace: pace), to: store)
        }
    }

    init(store: KeyValueStore = UserDefaultsStore()) {
        self.store = store
        theme = store.get(Self.themeKey).flatMap(ThemePreference.init(rawValue:)) ?? .system
        soundEnabled = WordCore.isSoundEnabled(in: store)
        // Anything but an explicit "off" is on, matching the sound pref.
        hapticsEnabled = store.get(Self.hapticsKey) != "off"
        pace = loadSoloSetup(from: store).pace
    }

    // MARK: Onboarding (onboarding.ts)

    func hasSeenTutorialOffer() -> Bool { hasSeenTutorial(in: store) }
    func markTutorialOfferSeen() { markTutorialSeen(in: store) }
    func hasSeen(door: GameDoor) -> Bool { hasSeenDoor(door, in: store) }
    func markSeen(door: GameDoor) { markDoorSeen(door, in: store) }

    // MARK: Stats (stats.ts)

    func stats() -> Stats { loadStats(from: store) }

    @discardableResult
    func record(score: Int, words: Int, at date: Date = .now) -> Stats {
        recordGame(
            GameRecord(score: score, words: words, at: date.timeIntervalSince1970 * 1000),
            in: store)
    }

    // MARK: Daily Deal (plan §8.2)

    func hasSeenDailyExplainer() -> Bool { store.get(Self.dailySeenKey) == "1" }
    func markDailyExplainerSeen() { store.set(Self.dailySeenKey, "1") }

    func dailyHistory() -> DailyHistory { DailyHistory.load(from: store) }

    /// Today, and what's been done about it.
    func dailyStatus(at now: Date = .now) -> DailyStatus {
        let deal = dailyDeal(at: now)
        let history = dailyHistory()
        return DailyStatus(
            deal: deal, result: history.result(for: deal.day),
            streak: history.streak(today: deal.day))
    }

    @discardableResult
    func recordDaily(_ result: DailyResult) -> DailyHistory {
        var history = dailyHistory()
        history.record(result)
        history.save(to: store)
        return history
    }

    // MARK: Saved solo game (plan §6.1 — solo games survive process death)

    func loadSavedGame() -> SavedSoloGame? {
        SavedSoloGame.load(from: store)
    }

    func save(_ game: SavedSoloGame?) {
        if let game {
            game.save(to: store)
        } else {
            SavedSoloGame.clear(in: store)
        }
    }
}
