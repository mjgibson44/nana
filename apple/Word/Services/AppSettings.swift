import Observation
import SwiftUI
import WordCore

/// The player's preferences, persisted through WordCore's storage helpers so
/// the keys and defensive-parsing semantics stay identical to the web's.
///
/// There is no settings page any more, so what's here is what the game reads
/// on its own: the sound and haptics switches (still honoured if a stored
/// value says off), the last Solo pace, the local stats, and the saved game.
@Observable @MainActor
final class AppSettings {
    /// New on Apple platforms — sound has its own switch on the web, and
    /// haptics get a separate one (plan §6.5).
    private static let hapticsKey = "nana.haptics.v1"

    private let store: KeyValueStore

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

    /// The pace Solo deals at — the last one chosen from the game menu.
    var pace: SoloPace {
        didSet {
            guard pace != oldValue else { return }
            saveSoloSetup(SoloSetup(pace: pace), to: store)
        }
    }

    init(store: KeyValueStore = UserDefaultsStore()) {
        self.store = store
        soundEnabled = WordCore.isSoundEnabled(in: store)
        // Anything but an explicit "off" is on, matching the sound pref.
        hapticsEnabled = store.get(Self.hapticsKey) != "off"
        pace = loadSoloSetup(from: store).pace
    }

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
