// swift-tools-version:6.0
import PackageDescription

// The board's interaction brain, kept out of the app target so it tests in CI
// without a simulator (plan §11): the gesture disambiguation state machine and
// the board geometry math (zoom, pinch anchoring, auto-fit, growth
// compensation). Pure logic over Foundation geometry types — no SwiftUI, no
// platform input APIs — so it builds and tests on Linux like WordCore.
let package = Package(
    name: "WordBoard",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
        .visionOS(.v1),
    ],
    products: [
        .library(name: "WordBoard", targets: ["WordBoard"])
    ],
    dependencies: [
        .package(path: "../WordCore")
    ],
    targets: [
        .target(
            name: "WordBoard",
            dependencies: ["WordCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "WordBoardTests",
            dependencies: ["WordBoard"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
