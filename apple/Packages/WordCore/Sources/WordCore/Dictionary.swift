/// Validation-dictionary parsing. Ported from `src/game/dictionary.ts`.
///
/// The full ENABLE word list (`public/dictionary.txt`, ~173k words) is
/// app-provided by design — the app bundles the canonical file and hands its
/// text here; the package itself bundles only the generation pool.

/// One lowercase word per line; blank lines ignored; whitespace trimmed and
/// input lowercased, exactly like the TS parser (so the same file bytes
/// yield the same set on both platforms).
public func parseDictionary(_ text: String) -> Set<String> {
    var words = Set<String>()
    // Split on any newline, not the Character "\n": in Swift "\r\n" is a
    // single grapheme, so a plain split(separator: "\n") would not split a
    // CRLF file at all.
    for line in text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
        let word = line.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !word.isEmpty { words.insert(word) }
    }
    return words
}
