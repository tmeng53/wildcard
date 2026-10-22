// swift-tools-version: 6.0
import PackageDescription

// The 动态 tab: the squad's check-ins, newest first, with teammates' reactions. `FeedDomain`
// holds what the screen reads and the rules of reacting (one emoji per teammate, none on your
// own post, which move the author's character plays) and loads through its `FeedSource` port.
// It is pure Swift, so it builds and tests on Linux. `FeedUI` is the screen: post cards with
// the author's character, the emoji bar and the empty scene.
let package = Package(
    name: "Feed",
    defaultLocalization: "zh-Hans",
    platforms: [.iOS("26.0"), .macOS("26.0")],
    products: [
        .library(name: "FeedDomain", targets: ["FeedDomain"]),
        .library(name: "FeedUI", targets: ["FeedUI"]),
    ],
    dependencies: [
        .package(path: "../Contracts"),
        .package(path: "../DesignSystem"),
        .package(path: "../Avatar"),
        .package(path: "../Sports"),
        .package(path: "../CheckIn"),
    ],
    targets: [
        .target(name: "FeedDomain", dependencies: ["Contracts"]),
        .target(
            name: "FeedUI",
            dependencies: [
                "FeedDomain", "Contracts",
                .product(name: "DesignSystem", package: "DesignSystem"),
                .product(name: "DesignSystemUI", package: "DesignSystem"),
                .product(name: "AvatarArt", package: "Avatar"),
                .product(name: "AvatarDomain", package: "Avatar"),
                .product(name: "AvatarUI", package: "Avatar"),
                .product(name: "SportsUI", package: "Sports"),
                .product(name: "CheckInUI", package: "CheckIn"),
            ],
            resources: [.process("Resources/Localizable.xcstrings")]
        ),
        .testTarget(name: "FeedDomainTests", dependencies: ["FeedDomain", "Contracts"]),
        // The screen's non-visual parts, and its String Catalog read as a file; runs on Linux too.
        .testTarget(name: "FeedUITests", dependencies: ["FeedUI", "FeedDomain", "Contracts"]),
    ]
)
