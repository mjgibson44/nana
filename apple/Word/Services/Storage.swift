import Foundation
import WordCore

/// `UserDefaults` behind WordCore's storage protocol, keeping the web game's
/// exact keys and semantics: a failed read falls back to the default and a
/// write never throws (plan §9.1 — same keys so a future migration can read
/// web exports).
struct UserDefaultsStore: KeyValueStore {
    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func get(_ key: String) -> String? {
        defaults.string(forKey: key)
    }

    func set(_ key: String, _ value: String) {
        defaults.set(value, forKey: key)
    }

    func remove(_ key: String) {
        defaults.removeObject(forKey: key)
    }
}

/// An in-memory store for tests and previews.
final class MemoryStore: KeyValueStore, @unchecked Sendable {
    private var values: [String: String]

    init(_ values: [String: String] = [:]) {
        self.values = values
    }

    func get(_ key: String) -> String? { values[key] }
    func set(_ key: String, _ value: String) { values[key] = value }
    func remove(_ key: String) { values[key] = nil }
}
