import SwiftUI

/// The web game's monochrome ink palette (styles.css:1–125): everything
/// structural is black, white and grey; the only color is the functional tile
/// feedback (valid / invalid / disconnected / isolated). Light and dark values
/// are the stylesheet's tokens verbatim; `system` theme just lets the
/// environment pick the variant, exactly like the web's `prefers-color-scheme`
/// fallback.
enum Ink {
    static let bg = paired(0xF4F4F3, 0x131313)
    static let surface = paired(0xFFFFFF, 0x1E1E1E)
    static let surfaceAlt = paired(0xEDEDEC, 0x292929)
    static let boardBg = paired(0xE9E9E7, 0x181818)
    static let cellBg = paired(0xF7F7F6, 0x212121)
    static let cellLine = paired(0xDCDCDA, 0x2F2F2F)
    static let ink = paired(0x161616, 0xECECEC)
    static let inkInvert = paired(0xFFFFFF, 0x131313)
    static let line = paired(0xBDBDBB, 0x555553)
    static let lineSoft = paired(0xE3E3E1, 0x323230)
    static let tileFace = paired(0xFFFFFF, 0x2B2B2B)
    static let tileEdge = paired(0xC6C6C4, 0x505050)
    static let focus = paired(0x161616, 0xECECEC)
    static let selectBg = paired(0xE0E0DE, 0x3C3C3A)

    // Functional tile feedback: ok(green) / bad(red) / warn(orange) / iso(yellow).
    static let okBg = paired(0xDDEDCC, 0x2B3D1D)
    static let okEdge = paired(0x86AC67, 0x5B8039)
    static let okInk = paired(0x3C5C21, 0xBCD99E)
    static let badBg = paired(0xF6C9C2, 0x4B211C)
    static let badEdge = paired(0xDD7C71, 0xA4544A)
    static let badInk = paired(0xA32E23, 0xF0A89F)
    static let warnBg = paired(0xFFD9A6, 0x46311A)
    static let warnEdge = paired(0xE08A3C, 0xA86A2E)
    static let warnInk = paired(0x94520F, 0xEEC089)
    static let isoBg = paired(0xFFEEBB, 0x403919)
    static let isoEdge = paired(0xDFB45E, 0x94803E)
    static let isoInk = paired(0x8A6210, 0xDFCF8E)

    private static func paired(_ light: UInt32, _ dark: UInt32) -> Color {
        #if canImport(UIKit)
        return Color(UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
        #else
        return Color(NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light)
        })
        #endif
    }
}

#if canImport(UIKit)
import UIKit

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1)
    }
}
#else
import AppKit

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1)
    }
}
#endif
