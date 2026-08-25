import GameKit
import SwiftUI

/// Game Center's own floating badge — the standard way in to leaderboards,
/// achievements and the player's profile, and (plan §8.4) part of what earns a
/// game its placement in the Apple Games app.
///
/// It is a single global object rather than a view, so this modifier's whole
/// job is turning it on while the home screen is up and off again afterwards.
/// Leaving it on would float it over the board.
struct GameCenterAccessPoint: ViewModifier {
    var active: Bool

    func body(content: Content) -> some View {
        content
            .onAppear { apply(active) }
            .onDisappear { apply(false) }
            .onChange(of: active) { _, now in apply(now) }
    }

    private func apply(_ active: Bool) {
        let point = GKAccessPoint.shared
        guard active else {
            point.isActive = false
            return
        }
        point.location = .topTrailing
        // Surfaces the player's standing rather than just an icon — the reason
        // to adopt it at all.
        point.showHighlights = true
        point.isActive = true
    }
}
