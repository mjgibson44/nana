import Testing
@testable import WordCore

/// Ported behavior of src/game/dictionary.ts's parser.
@Suite("Dictionary: parseDictionary") struct DictionaryParse {
    @Test("splits lines into a lowercase set, skipping empties")
    func parsesLines() {
        let set = parseDictionary("aa\naah\n\nZebra\n  cat  \n")
        #expect(set == ["aa", "aah", "zebra", "cat"])
    }

    @Test("tolerates CRLF line endings")
    func toleratesCRLF() {
        #expect(parseDictionary("aa\r\nbee\r\n") == ["aa", "bee"])
    }

    @Test("an empty text yields an empty set")
    func emptyText() {
        #expect(parseDictionary("") == [])
    }

    @Test("every generation-pool word would validate")
    func poolIsSubsetShape() {
        // The real subset relation is asserted in GeneratorTests against the
        // bundled pool; here just prove the parser accepts the pool's shape.
        let set = parseDictionary(commonWords.joined(separator: "\n"))
        #expect(set.count > 4000)
        #expect(set.contains("the"))
    }
}
