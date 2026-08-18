import SwiftUI

/// The native Solo game. The phase-1 proof-of-life screen this replaced lives
/// on in git history; phase 2 now drives WordCore through the unified board
/// gesture layer, editing loop, and paced session lifecycle.
struct ContentView: View {
    var body: some View {
        GameScreen()
    }
}

#Preview {
    ContentView()
}
