// swift-tools-version: 6.0
import PackageDescription

// 小队设置: the squad's page. `SquadDomain` holds what it shows and does (the captain renames
// the squad, removes members and hands the captaincy on; everyone invites and can leave; last
// week's crown winner, or the captain, picks the week's scene once) behind its
// `SquadSettingsService` port, and is pure Swift, so it tests on Linux. `SquadUI` draws the page,
// with the scene tiles and picker of `ScenePick`.
let package = Package(
    name: "Squad",
    defaultLocalization: "zh-Hans",
    platforms: [.iOS("26.0"), .macOS("26.0")],
    products: [
        .library(name: "SquadDomain", targets: ["SquadDomain"]),
        .library(name: "SquadUI", targets: ["SquadUI"]),
    ],
    dependencies: [
        .package(path: "../Avatar"),
        .package(path: "../CheckIn"),
        .package(path: "../Contracts"),
        .package(path: "../DesignSystem"),
        .package(path: "../ScenePick"),
    ],
    targets: [
        .target(
            name: "SquadDomain",
            dependencies: [
                "Contracts", .product(name: "DesignSystem", package: "DesignSystem"),
                .product(name: "ScenePickDomain", package: "ScenePick"),
            ]),
        .target(
            name: "SquadUI",
            dependencies: [
                "SquadDomain", "Contracts",
                .product(name: "AvatarArt", package: "Avatar"), .product(name: "AvatarDomain", package: "Avatar"),
                .product(name: "AvatarUI", package: "Avatar"),
                .product(name: "CheckInUI", package: "CheckIn"),
                .product(name: "DesignSystem", package: "DesignSystem"),
                .product(name: "DesignSystemUI", package: "DesignSystem"),
                .product(name: "ScenePickDomain", package: "ScenePick"),
                .product(name: "ScenePickUI", package: "ScenePick"),
            ],
            resources: [.process("Resources/Localizable.xcstrings")]),
        .testTarget(name: "SquadDomainTests", dependencies: ["SquadDomain", "Contracts"]),
        // The String Catalog read as a file; the page needs a simulator.
        .testTarget(name: "SquadUITests", dependencies: ["SquadUI"]),
    ]
)
