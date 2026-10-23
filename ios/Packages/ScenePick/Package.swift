// swift-tools-version: 6.0
import PackageDescription

// Picking the squad's scene for next week: last week's crown winner (or the captain) picks
// once, on the 战报's last page or in squad settings, and the pick plays the unboxing reveal.
// `ScenePickDomain` holds the picker's rules and the reveal's timeline, frame by frame; it is
// pure Swift, so it tests on Linux. `ScenePickUI` draws the sticker and the reveal.
let package = Package(
    name: "ScenePick",
    defaultLocalization: "zh-Hans",
    platforms: [.iOS("26.0"), .macOS("26.0")],
    products: [
        .library(name: "ScenePickDomain", targets: ["ScenePickDomain"]),
        .library(name: "ScenePickUI", targets: ["ScenePickUI"]),
    ],
    dependencies: [.package(path: "../DesignSystem")],
    targets: [
        .target(name: "ScenePickDomain", dependencies: [.product(name: "DesignSystem", package: "DesignSystem")]),
        .target(
            name: "ScenePickUI",
            dependencies: [
                "ScenePickDomain",
                .product(name: "DesignSystem", package: "DesignSystem"),
                .product(name: "DesignSystemUI", package: "DesignSystem"),
            ],
            resources: [.process("Resources/Localizable.xcstrings")]),
        .testTarget(name: "ScenePickDomainTests", dependencies: ["ScenePickDomain"]),
        // The String Catalog read as a file; the views need a simulator.
        .testTarget(
            name: "ScenePickUITests",
            dependencies: ["ScenePickUI"]),
    ]
)
