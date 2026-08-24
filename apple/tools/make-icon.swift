// Renders the app icon from the game's own design tokens.
//
// Kept as a script rather than a checked-in binary so the icon is
// reproducible and adjustable — the same reason the dictionary is referenced
// from the web app rather than copied, and the fixtures are generated.
//
//   swift apple/tools/make-icon.swift
//
// A placeholder, honestly: it is the game's visual language (ink on paper,
// bordered tiles, heavy rounded type) rather than a designed mark. Good enough
// for TestFlight; worth replacing before the App Store.

import AppKit

let ink = NSColor(srgbRed: 0x16 / 255, green: 0x16 / 255, blue: 0x16 / 255, alpha: 1)
let paper = NSColor(srgbRed: 0xF4 / 255, green: 0xF4 / 255, blue: 0xF3 / 255, alpha: 1)
let tileFace = NSColor.white

/// One 2×2 block of tiles spelling the game's first word.
let letters = [["T", "I"], ["M", "E"]]

func roundedFont(size: CGFloat) -> NSFont {
    let base = NSFont.systemFont(ofSize: size, weight: .heavy)
    guard let descriptor = base.fontDescriptor.withDesign(.rounded),
        let rounded = NSFont(descriptor: descriptor, size: size)
    else { return base }
    return rounded
}

/// Draws at exactly `pixels` square.
///
/// Drawn into an explicitly sized bitmap rather than via `NSImage.lockFocus`,
/// which rasterises at the Mac's backing scale — on a Retina display that
/// quietly doubles every icon, and the asset catalog rejects all of them.
///
/// - Parameter inset: fraction of the canvas left as margin. iOS masks the
///   icon itself so it wants full bleed; macOS bakes its own squircle in.
func drawIcon(pixels: Int, inset: CGFloat, squircle: Bool) -> NSBitmapImageRep {
    let size = CGFloat(pixels)
    guard
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
    else { fatalError("could not allocate a \(pixels)px bitmap") }
    // One point per pixel, so the drawing below needs no scale factor.
    rep.size = NSSize(width: size, height: size)

    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    guard let graphics = NSGraphicsContext(bitmapImageRep: rep) else {
        fatalError("could not bind a context to the bitmap")
    }
    NSGraphicsContext.current = graphics
    let context = graphics.cgContext
    context.setShouldAntialias(true)

    let margin = size * inset
    let plate = CGRect(x: margin, y: margin, width: size - margin * 2, height: size - margin * 2)

    if squircle {
        // macOS draws its own rounded plate; iOS gets a full-bleed square.
        NSColor.clear.setFill()
        context.fill(CGRect(x: 0, y: 0, width: size, height: size))
        let path = NSBezierPath(
            roundedRect: plate, xRadius: plate.width * 0.22, yRadius: plate.width * 0.22)
        paper.setFill()
        path.fill()
    } else {
        paper.setFill()
        context.fill(CGRect(x: 0, y: 0, width: size, height: size))
    }

    // Four tiles, laid out inside the plate.
    let field = plate.insetBy(dx: plate.width * 0.13, dy: plate.height * 0.13)
    let gap = field.width * 0.055
    let tile = (field.width - gap) / 2
    let radius = tile * 0.17
    let border = max(1, tile * 0.075)

    for (row, line) in letters.enumerated() {
        for (column, letter) in line.enumerated() {
            // AppKit's origin is bottom-left; the first row should be on top.
            let x = field.minX + CGFloat(column) * (tile + gap)
            let y = field.minY + CGFloat(1 - row) * (tile + gap)
            let rect = CGRect(x: x, y: y, width: tile, height: tile)

            let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
            tileFace.setFill()
            path.fill()
            ink.setStroke()
            path.lineWidth = border
            path.stroke()

            let font = roundedFont(size: tile * 0.62)
            let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: ink]
            let text = NSAttributedString(string: letter, attributes: attributes)
            let bounds = text.size()
            text.draw(
                at: NSPoint(
                    x: rect.midX - bounds.width / 2,
                    // Optical centring: cap-height sits above the baseline.
                    y: rect.midY - bounds.height / 2 + tile * 0.015))
        }
    }
    return rep
}

func write(_ rep: NSBitmapImageRep, to url: URL) {
    guard let data = rep.representation(using: .png, properties: [:]) else {
        fatalError("could not encode \(url.lastPathComponent)")
    }
    try! data.write(to: url)
    print("wrote \(url.lastPathComponent) (\(rep.pixelsWide)px)")
}

let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
let iconSet = root.appendingPathComponent("Word/Assets.xcassets/AppIcon.appiconset")
try! FileManager.default.createDirectory(at: iconSet, withIntermediateDirectories: true)

// iOS: full bleed, the system applies the mask.
write(
    drawIcon(pixels: 1024, inset: 0, squircle: false),
    to: iconSet.appendingPathComponent("icon-ios-1024.png"))

// macOS: its own plate, with the margin Apple's grid expects.
let macSizes = [16, 32, 64, 128, 256, 512, 1024]
for pixels in macSizes {
    write(
        drawIcon(pixels: pixels, inset: 0.09, squircle: true),
        to: iconSet.appendingPathComponent("icon-mac-\(pixels).png"))
}

// The catalog manifest.
var images: [String] = [
    #"{"filename":"icon-ios-1024.png","idiom":"universal","platform":"ios","size":"1024x1024"}"#
]
for (points, scale) in [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)] {
    images.append(
        """
        {"filename":"icon-mac-\(points * scale).png","idiom":"mac",\
        "scale":"\(scale)x","size":"\(points)x\(points)"}
        """)
}
let manifest = """
{
  "images" : [
    \(images.joined(separator: ",\n    "))
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}

"""
try! manifest.write(
    to: iconSet.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
print("wrote Contents.json")
