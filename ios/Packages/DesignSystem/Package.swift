// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DesignSystem",
    defaultLocalization: "zh-Hans",
    platforms: [.iOS("26.0"), .macOS(.v14)],
    products: [
        .library(name: "DesignSystem", targets: ["DesignSystem"]),
        .library(name: "DesignSystemUI", targets: ["DesignSystemUI"]),
    ],
    targets: [
        // Tokens as plain values: pure Swift, builds and tests on Linux.
        .target(name: "DesignSystem"),
        // SwiftUI views of the tokens, the bundled scoreboard font and the style guide.
        .target(
            name: "DesignSystemUI",
            dependencies: ["DesignSystem"],
            resources: [
                .copy("Resources/Fonts"),
                .process("Resources/Localizable.xcstrings"),
            ]
        ),
        .testTarget(name: "DesignSystemTests", dependencies: ["DesignSystem"]),
        .testTarget(name: "DesignSystemUITests", dependencies: ["DesignSystemUI"]),
    ]
)
