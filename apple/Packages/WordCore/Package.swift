// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "WordCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
        .visionOS(.v1),
    ],
    products: [
        .library(name: "WordCore", targets: ["WordCore"])
    ],
    targets: [
        .target(
            name: "WordCore",
            resources: [
                .copy("Resources/common-words.txt")
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "WordCoreTests",
            dependencies: ["WordCore"],
            resources: [
                .copy("Fixtures")
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
