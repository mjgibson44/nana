import SwiftUI
import WordCore

/// Phase-1 proof of life: WordCore dealing real puzzles natively, with the
/// bundled dictionary loaded. Phase 2 (the real board UI, plan §6) replaces
/// this screen; it exists so the very first native build shows the port
/// working end to end.
struct ContentView: View {
    @State private var puzzle: Puzzle?
    @State private var seed = "hello"
    @State private var dictionaryCount = 0

    var body: some View {
        VStack(spacing: 20) {
            Text("WordCore is alive")
                .font(.title.bold())

            Text("seed “\(seed)” — same letters as the web game")
                .font(.callout)
                .foregroundStyle(.secondary)

            if let puzzle {
                letterRack(puzzle.letters)
                if let solution = puzzle.solution {
                    solutionBoard(solution)
                    Text("hidden solution: \(puzzle.sourceWords.joined(separator: " · "))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Text(dictionaryCount > 0
                ? "dictionary loaded: \(dictionaryCount) words"
                : "loading dictionary…")
                .font(.footnote.monospacedDigit())
                .foregroundStyle(.secondary)

            Button("Deal again") {
                seed = randomSeed()
                deal()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(32)
        .frame(minWidth: 420, minHeight: 480)
        .task {
            deal()
            loadDictionary()
        }
    }

    private func deal() {
        puzzle = try? generatePuzzle(wordPool: commonWords, tileCount: 20, rng: seededRng(seed))
    }

    private func loadDictionary() {
        guard dictionaryCount == 0,
              let url = Bundle.main.url(forResource: "dictionary", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8)
        else { return }
        dictionaryCount = parseDictionary(text).count
    }

    private func letterRack(_ letters: [String]) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(36), spacing: 6), count: 10), spacing: 6) {
            ForEach(Array(letters.enumerated()), id: \.offset) { _, letter in
                Text(letter.uppercased())
                    .font(.headline)
                    .frame(width: 36, height: 36)
                    .background(RoundedRectangle(cornerRadius: 6).stroke(lineWidth: 2))
            }
        }
    }

    private func solutionBoard(_ solution: TileMap) -> some View {
        let cells = solution.keys.map(parseKey)
        let rows = (cells.map(\.row).min() ?? 0)...(cells.map(\.row).max() ?? 0)
        let cols = (cells.map(\.col).min() ?? 0)...(cells.map(\.col).max() ?? 0)
        return VStack(spacing: 2) {
            ForEach(Array(rows), id: \.self) { row in
                HStack(spacing: 2) {
                    ForEach(Array(cols), id: \.self) { col in
                        Text(solution[row, col]?.uppercased() ?? "")
                            .font(.caption.bold())
                            .frame(width: 22, height: 22)
                            .background(
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(solution[row, col] == nil
                                        ? Color.clear
                                        : Color.primary.opacity(0.08))
                            )
                    }
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
