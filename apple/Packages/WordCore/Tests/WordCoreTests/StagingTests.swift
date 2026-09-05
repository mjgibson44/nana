import Foundation
import Testing
@testable import WordCore

/// Words built on the board by dropping tiles: judged as one placement when
/// they're confirmed — one line, no holes, joined to something (or the
/// opener on its start square), and every run a real word.

private let words: Set<String> = ["cat", "cats", "tea", "eat", "ate", "art", "rat", "tar", "at"]
private func isWord(_ w: String) -> Bool { words.contains(w) }

private let start = Cell(row: 16, col: 16)

/// CAT across from the start square, already down.
private let cat: TileMap = [keyOf(16, 16): "c", keyOf(16, 17): "a", keyOf(16, 18): "t"]

@Suite("Staged tiles") struct StagingTests {
    @Test("an opener on its start square lands, and reads across")
    func openerOnStart() throws {
        let word = try judgeStaged(
            tiles: [keyOf(16, 15): "c", keyOf(16, 16): "a", keyOf(16, 17): "t"], board: TileMap(),
            opener: true, start: start, isWord: isWord)
        #expect(word.direction == .across)
        #expect(word.borrowed.isEmpty)
        #expect(word.runs.map(\.word) == ["cat"])
    }

    @Test("an opener can run down as well, as long as it covers the start")
    func openerDown() throws {
        let word = try judgeStaged(
            tiles: [keyOf(15, 16): "c", keyOf(16, 16): "a", keyOf(17, 16): "t"], board: TileMap(),
            opener: true, start: start, isWord: isWord)
        #expect(word.direction == .down)
    }

    @Test("an opener that misses the start square is refused")
    func openerOffStart() {
        #expect(throws: StagedRefusal.openerOffStart) {
            try judgeStaged(
                tiles: [keyOf(3, 3): "c", keyOf(3, 4): "a", keyOf(3, 5): "t"], board: TileMap(),
                opener: true, start: start, isWord: isWord)
        }
    }

    @Test("nothing, a scatter, or a hole is refused before anything is spelled")
    func shape() {
        #expect(throws: StagedRefusal.nothing) {
            try judgeStaged(tiles: [:], board: cat, opener: false, start: start, isWord: isWord)
        }
        #expect(throws: StagedRefusal.notInALine) {
            try judgeStaged(
                tiles: [keyOf(17, 18): "e", keyOf(18, 19): "a"], board: cat, opener: false,
                start: start, isWord: isWord)
        }
        #expect(throws: StagedRefusal.brokenLine) {
            try judgeStaged(
                tiles: [keyOf(17, 18): "e", keyOf(19, 18): "a"], board: cat, opener: false,
                start: start, isWord: isWord)
        }
    }

    @Test("a later word has to join a letter that's down")
    func mustJoin() {
        #expect(throws: StagedRefusal.mustJoin) {
            try judgeStaged(
                tiles: [keyOf(20, 20): "t", keyOf(20, 21): "e", keyOf(20, 22): "a"], board: cat,
                opener: false, start: start, isWord: isWord)
        }
    }

    @Test("a word hung off a letter borrows it, and every run it makes has to read")
    func joinsAndBorrows() throws {
        // TEA down from the T of CAT.
        let word = try judgeStaged(
            tiles: [keyOf(17, 18): "e", keyOf(18, 18): "a"], board: cat, opener: false,
            start: start, isWord: isWord)
        #expect(word.direction == .down)
        #expect(word.borrowed == [keyOf(16, 18)])
        #expect(word.runs.map(\.word) == ["tea"])

        // TZZ doesn't.
        #expect(throws: StagedRefusal.notAWord(["tzz"])) {
            try judgeStaged(
                tiles: [keyOf(17, 18): "z", keyOf(18, 18): "z"], board: cat, opener: false,
                start: start, isWord: isWord)
        }
        // An A under CAT's A, beside an R: R-A across and A-A down, and
        // the refusal names both.
        var board = cat
        board[keyOf(17, 16)] = "r"
        #expect(throws: StagedRefusal.notAWord(["ra", "aa"])) {
            try judgeStaged(
                tiles: [keyOf(17, 17): "a"], board: board, opener: false, start: start,
                isWord: isWord)
        }
    }

    @Test("a word run through a letter borrows only what's on its line")
    func crossingBorrowsTheLine() throws {
        // C-A-T-S: the S extends CAT and borrows all three.
        let extended = try judgeStaged(
            tiles: [keyOf(16, 19): "s"], board: cat, opener: false, start: start, isWord: isWord)
        #expect(extended.direction == .across)
        #expect(extended.borrowed == [keyOf(16, 16), keyOf(16, 17), keyOf(16, 18)])

        // E and T either side of the A: EAT down, borrowing just the A.
        let crossed = try judgeStaged(
            tiles: [keyOf(15, 17): "e", keyOf(17, 17): "t"], board: cat, opener: false,
            start: start, isWord: isWord)
        #expect(crossed.direction == .down)
        #expect(crossed.borrowed == [keyOf(16, 17)])
        #expect(Set(crossed.runs.map(\.word)) == ["eat"])
    }

    @Test("a lone tile reads in whichever direction makes the longer word")
    func loneTileDirection() throws {
        // A board with CAT across and, below the T, an E: dropping an A
        // under the E makes TEA down (three letters) and nothing across.
        var board = cat
        board[keyOf(17, 18)] = "e"
        let word = try judgeStaged(
            tiles: [keyOf(18, 18): "a"], board: board, opener: false, start: start, isWord: isWord)
        #expect(word.direction == .down)
        #expect(word.borrowed == [keyOf(16, 18), keyOf(17, 18)])
    }

    @Test("every refusal says something a player can act on")
    func messages() {
        let refusals: [StagedRefusal] = [
            .nothing, .notInALine, .brokenLine, .mustJoin, .openerOffStart, .notAWord(["tzz"]),
            .notAWord(["tzz", "qq"]),
        ]
        for refusal in refusals {
            #expect(!refusal.message.isEmpty)
        }
        #expect(StagedRefusal.notAWord(["tzz"]).message == "TZZ isn’t a word")
        #expect(StagedRefusal.notAWord(["tzz", "qq"]).message == "TZZ, QQ aren’t words")
    }
}
