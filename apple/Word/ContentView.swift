import SwiftUI

/// Phase 2a: the real board. The phase-1 proof-of-life screen this replaced
/// lives on in git history; the game screen now deals through WordCore and
/// drives the board with the unified gesture layer (plan §6.2).
struct ContentView: View {
    var body: some View {
        GameScreen()
    }
}

#Preview {
    ContentView()
}
