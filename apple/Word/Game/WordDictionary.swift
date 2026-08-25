import Foundation
import WordCore

/// The validation dictionary, parsed once for the whole process.
///
/// It is 172,823 words — a 1.74 MB file that becomes a `Set<String>` of tens
/// of megabytes. Every `GameModel` used to build its own: fine for the one a
/// player has open, wasteful the moment there are two (a battle board beside a
/// solo one), and genuinely harmful in the test suite, where a hundred-odd
/// models each parsing their own copy put enough memory pressure on the
/// simulator to fail reads and take the test host down with it.
///
/// Sharing it also collapses concurrent callers onto one parse: the second
/// caller awaits the first's task rather than starting a second one.
@MainActor
enum WordDictionary {
    private static var cached: Set<String>?
    private static var loading: Task<Set<String>?, Never>?

    static func shared() async -> Set<String>? {
        if let cached { return cached }
        if let loading { return await loading.value }

        let task = Task.detached(priority: .userInitiated) { () -> Set<String>? in
            guard
                let url = Bundle.main.url(forResource: "dictionary", withExtension: "txt"),
                let text = try? String(contentsOf: url, encoding: .utf8)
            else { return nil }
            return parseDictionary(text)
        }
        loading = task
        let parsed = await task.value
        loading = nil
        cached = parsed
        return parsed
    }
}
