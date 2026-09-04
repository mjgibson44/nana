import SwiftUI

@main
struct WordApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                // The game is one dark theme, by design.
                .preferredColorScheme(.dark)
                // A floor small enough that a Mac window can always be dragged
                // smaller: the board scrolls and zooms, so it never needs room
                // for the whole lattice — but nothing below this leaves space
                // for the header, the word row, the pile and the buttons.
                .frame(minWidth: 400, minHeight: 640)
        }
        // Opens phone-shaped rather than inheriting the lattice's own
        // dimensions (macOS; ignored where windows are managed).
        .defaultSize(width: 440, height: 900)
    }
}
