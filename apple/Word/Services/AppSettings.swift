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
