import SwiftUI
import WordBoard

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// The three things SwiftUI's gesture vocabulary can't tell us, sensed from
/// the platform's own input stack.
///
/// 1. **The live pinch midpoint.** `MagnifyGesture` reports `startAnchor` and
///    nothing after it, but the web re-aims the anchored board point at the
///    fingers *every frame* — that is what makes a pinch that also travels
///    pan the board instead of zooming about a stale spot (ui.md §8.10,
///    App.tsx:2823–2861). `PinchAnchor.alignedOffset` has always taken a live
///    midpoint; this is the thing that finally has one to give it.
/// 2. **What kind of pointer is in the player's hand** (iOS). SwiftUI gestures
///    don't say, so the port had to assume touch on every non-Mac device —
///    which hands an iPad trackpad the *touch* rules and arms hold-to-drag on
///    a pointer the web deliberately excludes (App.tsx:2639). A `UITouch`
///    knows; nothing else does.
/// 3. **Scroll-to-pan** (macOS). Owning the board offset instead of hosting a
///    ScrollView is what lets zoom and its scroll correction land in one frame
///    (ui.md §8.5–8.7), but it also means no scroll wheel or two-finger
///    trackpad scroll reaches the board unless something forwards it.
///
/// The bridge is deliberately a **sensor, not a driver**: SwiftUI still
/// recognizes the pinch and still owns the drag pipeline. If the bridge never
/// attaches, pinch keeps working off `startAnchor` and the pointer keeps
/// reading as touch — the behavior this port shipped with — rather than
/// breaking outright.
struct BoardInputBridge: View {
    /// The live two-finger midpoint in the board viewport's own coordinates,
    /// or nil when no pinch is in flight.
    var onMidpoint: (CGPoint?) -> Void
    /// A scroll gesture's pan delta (macOS).
    var onScroll: (CGSize) -> Void
    /// False while an overlay owns the screen — the board shouldn't drift
    /// under a pause card.
    var isEnabled: Bool

    var body: some View {
        Representable(onMidpoint: onMidpoint, onScroll: onScroll, isEnabled: isEnabled)
            // Our platform views refuse hits of their own accord; this keeps
            // SwiftUI's hit-testing from routing anything here either.
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// What input device the player is using *right now*.
///
/// Read imperatively at press time rather than published: a pointer-kind
/// change must never invalidate a view, or a board of a thousand cells
/// re-renders on hover (the churn ui.md §8.10 warns about).
@MainActor
final class PointerKindTracker {
    static let shared = PointerKindTracker()

    /// Before the platform says otherwise, assume the device's usual pointer.
    private(set) var current: GestureMachine.PointerKind = {
        #if os(macOS)
        return .mouse
        #else
        return .touch
        #endif
    }()

    func note(_ kind: GestureMachine.PointerKind) {
        current = kind
    }
}

// MARK: - iOS

#if os(iOS)

extension BoardInputBridge {
    fileprivate struct Representable: UIViewRepresentable {
        var onMidpoint: (CGPoint?) -> Void
        var onScroll: (CGSize) -> Void
        var isEnabled: Bool

        func makeUIView(context: Context) -> BridgeView {
            let view = BridgeView()
            view.onMidpoint = onMidpoint
            view.isEnabledForInput = isEnabled
            return view
        }

        func updateUIView(_ view: BridgeView, context: Context) {
            view.onMidpoint = onMidpoint
            view.isEnabledForInput = isEnabled
        }

        static func dismantleUIView(_ view: BridgeView, coordinator: ()) {
            view.detach()
        }
    }
}

/// A view that is only ever a coordinate space and a place to hang
/// recognizers. It takes no touches: the recognizers live on the window, so
/// they see every touch without this view having to be in anyone's hit-test
/// path — which is what keeps SwiftUI's own gesture routing byte-for-byte
/// unchanged.
final class BridgeView: UIView, UIGestureRecognizerDelegate {
    var onMidpoint: ((CGPoint?) -> Void)?
    var isEnabledForInput = true

    private weak var host: UIView?
    private var pinch: UIPinchGestureRecognizer?
    private var probe: TouchTypeProbe?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is unused") }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? { nil }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        detach()
        guard let window else { return }
        attach(to: window)
    }

    private func attach(to host: UIView) {
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(pinched))
        let probe = TouchTypeProbe()
        probe.onTouchType = { PointerKindTracker.shared.note(.init($0)) }

        for recognizer in [pinch, probe] as [UIGestureRecognizer] {
            // Strictly an observer: never swallow a touch, never delay one,
            // and never make SwiftUI's recognizers wait on it.
            recognizer.delegate = self
            recognizer.cancelsTouchesInView = false
            recognizer.delaysTouchesBegan = false
            recognizer.delaysTouchesEnded = false
            host.addGestureRecognizer(recognizer)
        }

        self.host = host
        self.pinch = pinch
        self.probe = probe
    }

    func detach() {
        if let pinch { host?.removeGestureRecognizer(pinch) }
        if let probe { host?.removeGestureRecognizer(probe) }
        host = nil
        pinch = nil
        probe = nil
    }

    @objc private func pinched(_ recognizer: UIPinchGestureRecognizer) {
        switch recognizer.state {
        case .began, .changed:
            // A finger lifting mid-pinch leaves the recognizer live with a
            // meaningless midpoint; hold the last good one instead.
            guard isEnabledForInput, recognizer.numberOfTouches >= 2 else { return }
            onMidpoint?(recognizer.location(in: self))
        default:
            onMidpoint?(nil)
        }
    }

    // The whole point is to coexist with SwiftUI's gestures.
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
    ) -> Bool { true }
}

/// Sees the first touch of every sequence purely to read its type, then fails
/// so it can never affect recognition.
private final class TouchTypeProbe: UIGestureRecognizer {
    var onTouchType: ((UITouch.TouchType) -> Void)?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        if let type = touches.first?.type { onTouchType?(type) }
        state = .failed
    }
}

extension GestureMachine.PointerKind {
    fileprivate init(_ type: UITouch.TouchType) {
        switch type {
        case .pencil:
            // Pen keeps the touch rules (hold-to-drag included) — the web
            // treats pen like touch everywhere (ui.md §3.9); naming it is
            // what lets that stay a decision rather than an accident.
            self = .pen
        case .indirectPointer, .indirect:
            self = .mouse
        default:
            self = .touch
        }
    }
}

#endif

// MARK: - macOS

#if os(macOS)

extension BoardInputBridge {
    fileprivate struct Representable: NSViewRepresentable {
        var onMidpoint: (CGPoint?) -> Void
        var onScroll: (CGSize) -> Void
        var isEnabled: Bool

        func makeNSView(context: Context) -> BridgeView {
            let view = BridgeView()
            view.onMidpoint = onMidpoint
            view.onScroll = onScroll
            view.isEnabledForInput = isEnabled
            return view
        }

        func updateNSView(_ view: BridgeView, context: Context) {
            view.onMidpoint = onMidpoint
            view.onScroll = onScroll
            view.isEnabledForInput = isEnabled
        }

        static func dismantleNSView(_ view: BridgeView, coordinator: ()) {
            view.stopMonitoring()
        }
    }
}

/// AppKit reaches the board through a local event monitor rather than
/// `scrollWheel(with:)`, for the same reason iOS hangs its recognizers on the
/// window: a monitor sees the events without this view needing to sit in the
/// hit-test path and disturb SwiftUI's routing.
final class BridgeView: NSView {
    var onMidpoint: ((CGPoint?) -> Void)?
    var onScroll: ((CGSize) -> Void)?
    var isEnabledForInput = true

    private var monitor: Any?

    /// Top-left origin, so a converted point is already viewport coordinates.
    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        stopMonitoring()
        guard window != nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .magnify]) {
            [weak self] event in
            guard let self else { return event }
            return self.handle(event)
        }
    }

    func stopMonitoring() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        guard isEnabledForInput, let window, event.window === window else { return event }
        let local = convert(event.locationInWindow, from: nil)
        guard bounds.contains(local) else {
            if event.type == .magnify { onMidpoint?(nil) }
            return event
        }

        switch event.type {
        case .magnify:
            // SwiftUI's MagnifyGesture still drives the scale; all this adds
            // is the midpoint it can't report. Pass the event along.
            let finished = event.phase.contains(.ended) || event.phase.contains(.cancelled)
            onMidpoint?(finished ? nil : local)
            return event

        case .scrollWheel:
            let delta = ScrollPan.panDelta(
                x: event.scrollingDeltaX, y: event.scrollingDeltaY,
                precise: event.hasPreciseScrollingDeltas)
            guard delta != .zero else { return event }
            onScroll?(delta)
            // Nothing behind the board scrolls, so keep the event from
            // reaching anything else.
            return nil

        default:
            return event
        }
    }
}

#endif
