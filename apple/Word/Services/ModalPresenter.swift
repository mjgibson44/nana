import Foundation

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Putting a UIKit/AppKit view controller on screen from SwiftUI.
///
/// Two GameKit flows need this — the sign-in sheet and the matchmaker — and
/// both hand back a platform view controller rather than a view. Presenting it
/// is not optional: ignoring the one auth offers strands the player signed out
/// with no way forward.
///
/// The platform split is small but fiddly enough to be worth having once:
/// iOS presents modally from the key window's root, macOS runs a sheet on the
/// key window.
@MainActor
enum ModalPresenter {
    #if os(iOS)
    typealias ViewController = UIViewController
    #elseif os(macOS)
    typealias ViewController = NSViewController
    #endif

    #if os(iOS)
    /// - Returns: false when there was nowhere to present from, or something
    ///   is already up — callers use it to avoid stacking two sheets.
    @discardableResult
    static func present(_ viewController: UIViewController) -> Bool {
        guard let root = keyRoot(), root.presentedViewController == nil else { return false }
        root.present(viewController, animated: true)
        return true
    }

    static func dismiss(_ viewController: UIViewController) {
        viewController.presentingViewController?.dismiss(animated: true)
    }

    private static func keyRoot() -> UIViewController? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }?
            .keyWindow?.rootViewController
    }

    #elseif os(macOS)
    @discardableResult
    static func present(_ viewController: NSViewController) -> Bool {
        guard let window = NSApplication.shared.keyWindow ?? NSApplication.shared.windows.first,
            window.attachedSheet == nil
        else { return false }
        window.beginSheet(NSWindow(contentViewController: viewController))
        return true
    }

    static func dismiss(_ viewController: NSViewController) {
        guard let sheet = viewController.view.window else { return }
        sheet.sheetParent?.endSheet(sheet)
    }
    #endif
}
