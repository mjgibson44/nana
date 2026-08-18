import SwiftUI

@main
struct WordApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                // A floor small enough that the window can always be dragged
                // smaller: the board scrolls and zooms, so it never needs room
                // for the whole lattice — but nothing below this leaves space
                // for the header, the word bar and the pile together.
                .frame(minWidth: 420, minHeight: 520)
        }
        // Opens at a comfortable board-and-pile size rather than inheriting the
        // lattice's own dimensions (macOS; ignored where windows are managed).
        .defaultSize(width: 980, height: 760)
    }
}
