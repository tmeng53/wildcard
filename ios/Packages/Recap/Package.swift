// swift-tools-version: 6.0
import PackageDescription

// The Sunday 战报 (每周战报): a squad's week told as a story of full-screen pages. The server
// freezes each squad-week's story at its awards and the AI run adds the words; the app only
// plays it. `RecapDomain` holds the
// story as the app reads it, which pages play in which order, how long each lasts, what the
// characters do on each, and the tap-to-advance player; it is pure Swift, so it tests on Linux.
// `RecapUI` draws the pages, the covered entry tile in 动态 and the pending page, and puts
// `ScenePick`'s sticker and reveal on the last page for whoever picks next week's scene.
let package = Package(
    name: "Recap",
    defaultLocalization: "zh-Hans",
    platforms: [.iOS("26.0"), .macOS("26.0")],
    products: [
        .library(name: "RecapDomain", targets: ["RecapDomain"]),
        .library(name: "RecapUI", targets: ["RecapUI"]),
    ],
    dependencies: [
        .package(path: "../Contracts"),
        .package(path: "../DesignSystem"),
        .package(path: "../Avatar"),
        .package(path: "../Sports"),
        .package(path: "../ScenePick"),
        // The picked scene's art, as home draws it, behind the reveal.
        .package(path: "../CheckIn"),
    ],
    targets: [
        .target(
            name: "RecapDomain",
            dependencies: ["Contracts", .product(name: "DesignSystem", package: "DesignSystem")]),
        .target(
            name: "RecapUI",
            dependencies: [
                "RecapDomain", "Contracts",
                .product(name: "DesignSystem", package: "DesignSystem"),
                .product(name: "DesignSystemUI", package: "DesignSystem"),
                .product(name: "AvatarArt", package: "Avatar"),
                .product(name: "AvatarDomain", package: "Avatar"),
                .product(name: "AvatarUI", package: "Avatar"),
                // Sport names, as every picker shows them.
                .product(name: "SportsUI", package: "Sports"),
                .product(name: "ScenePickDomain", package: "ScenePick"),
                .product(name: "ScenePickUI", package: "ScenePick"),
                .product(name: "CheckInUI", package: "CheckIn"),
            ],
            resources: [.process("Resources/Localizable.xcstrings")]
        ),
        .testTarget(
            name: "RecapDomainTests",
            dependencies: ["RecapDomain", "Contracts", .product(name: "DesignSystem", package: "DesignSystem")]),
        // The String Catalog read as a file, and the story's clips and award parts; runs on Linux too.
        .testTarget(name: "RecapUITests", dependencies: ["RecapUI"]),
    ]
)
