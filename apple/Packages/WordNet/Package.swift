// swift-tools-version:6.0
import PackageDescription

// The battle protocol, transport-agnostic. Everything here runs over an
// injectable transport, so the host/client sessions — roster, seat grace,
// attack splitting, referee, host election, version gating — test in CI at
// unit-test speed (plan §7.5: "only the GKMatch adapter needs devices").
// No GameKit import lives in this package; the adapter is app-layer.
let package = Package(
    name: "WordNet",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
        .visionOS(.v1),
    ],
    products: [
        .library(name: "WordNet", targets: ["WordNet"])
    ],
    dependencies: [
        .package(path: "../WordCore")
    ],
    targets: [
        .target(
            name: "WordNet",
            dependencies: ["WordCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "WordNetTests",
            dependencies: ["WordNet"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
