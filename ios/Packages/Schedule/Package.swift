// swift-tools-version: 6.0
import PackageDescription

// 出赛表: the member's week as a poster they plan on and save to share. `ScheduleDomain` holds
// which weeks show, what may change in each (the week starts Monday; this week only moves its
// days still to come and keeps its number of rest days; next week changes freely; past weeks
// are read-only) and the store the screen binds to. It is pure Swift, so it tests on Linux.
// `ScheduleUI` is the tab's screen and the 3:4 poster it saves.
let package = Package(
    name: "Schedule",
    defaultLocalization: "zh-Hans",
    platforms: [.iOS("26.0"), .macOS("26.0")],
    products: [
        .library(name: "ScheduleDomain", targets: ["ScheduleDomain"]),
        .library(name: "ScheduleUI", targets: ["ScheduleUI"]),
    ],
    dependencies: [
        .package(path: "../Contracts"),
        .package(path: "../DesignSystem"),
        .package(path: "../Avatar"),
        .package(path: "../Sports"),
    ],
    targets: [
        .target(name: "ScheduleDomain", dependencies: [.product(name: "Contracts", package: "Contracts")]),
        .target(
            name: "ScheduleUI",
            dependencies: [
                "ScheduleDomain",
                .product(name: "Contracts", package: "Contracts"),
                .product(name: "DesignSystem", package: "DesignSystem"),
                .product(name: "DesignSystemUI", package: "DesignSystem"),
                .product(name: "AvatarArt", package: "Avatar"),
                .product(name: "AvatarDomain", package: "Avatar"),
                .product(name: "AvatarUI", package: "Avatar"),
                .product(name: "SportsUI", package: "Sports"),
            ],
            resources: [.process("Resources/Localizable.xcstrings")]),
        .testTarget(
            name: "ScheduleDomainTests",
            dependencies: ["ScheduleDomain", .product(name: "Contracts", package: "Contracts")]),
        // The in-memory squad and the String Catalog read as a file; the screen needs a simulator.
        .testTarget(
            name: "ScheduleUITests",
            dependencies: ["ScheduleUI", "ScheduleDomain", .product(name: "Contracts", package: "Contracts")]),
    ]
)
