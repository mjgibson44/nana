import SwiftUI
import WordBoard

/// One place hands pointer events to the gesture machine, from every surface
/// (board and rack tiles alike) — the SwiftUI stand-in for the web's
/// window-level pointer listeners keyed by `pointerId` (App.tsx:2509–2533).
///
/// Each surface synthesizes a fresh pointer id per touch-down, sends
/// down/move/up in the shared "game" coordinate space, and reports
/// system-cancelled gestures (the `@GestureState` reset is the only signal
/// SwiftUI gives for those).
@MainActor private var pointerSerial = 0

struct PointerSurface: ViewModifier {
    /// Resolve what sits under the pointer at press time.
    var target: (CGPoint) -> GestureMachine.DownTarget?
    /// The machine's press-time context, sampled live from the game state.
    var context: () -> GestureMachine.Context
    var dispatch: (GestureMachine.Event) -> Void
    /// Sampled at press time, not stored: the player can put the Pencil down
    /// and pick the trackpad up between one touch and the next.
    var kind: () -> GestureMachine.PointerKind = { PointerKindTracker.shared.current }

    @State private var pointerID: Int?
    @GestureState private var pressed = false

    func body(content: Content) -> some View {
        content
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named(GameScreen.space))
                    .updating($pressed) { _, state, _ in state = true }
                    .onChanged { value in
                        let time = value.time.timeIntervalSinceReferenceDate
                        if pointerID == nil {
                            pointerSerial += 1
                            pointerID = pointerSerial
                            // A press the surface claims for itself (the
                            // rotate control) never reaches the machine.
                            guard let target = target(value.startLocation) else { return }
                            dispatch(
                                .down(
                                    id: pointerSerial, kind: kind(),
                                    location: value.startLocation, target: target,
                                    time: time, context: context()))
                        }
                        guard let pointerID else { return }
                        dispatch(.move(id: pointerID, location: value.location, time: time))
                    }
                    .onEnded { value in
                        guard let id = pointerID else { return }
                        pointerID = nil
                        dispatch(
                            .up(
                                id: id, location: value.location,
                                time: value.time.timeIntervalSinceReferenceDate,
                                velocity: CGSize(
                                    width: value.velocity.width, height: value.velocity.height)))
                    }
            )
            .onChange(of: pressed) { _, isPressed in
                // Ended never fired but the gesture is gone: the system
                // cancelled it (an interrupting alert, a system gesture).
                if !isPressed, let id = pointerID {
                    pointerID = nil
                    dispatch(.cancel(id: id))
                }
            }
    }
}

extension View {
    func pointerSurface(
        target: @escaping (CGPoint) -> GestureMachine.DownTarget?,
        context: @escaping () -> GestureMachine.Context = { .init() },
        dispatch: @escaping (GestureMachine.Event) -> Void
    ) -> some View {
        modifier(PointerSurface(target: target, context: context, dispatch: dispatch))
    }
}

// SwiftUI gestures still don't say what produced them — `PointerKindTracker`
// (fed by `BoardInputBridge`) is where the answer now comes from, so an iPad
// trackpad gets the mouse rules instead of the touch ones.
