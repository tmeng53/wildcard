// swift-tools-version: 6.0
import PackageDescription

// The 6pm daily push, long-pressed: the squad's week, who patted the member, and teammates'
// check-ins today, each with the 动态 reaction row, so the member reacts without opening the
// app. `DailyPushDomain` reads what the push carries and holds the rules of reacting there (the
// same emoji again takes it back; a reaction shows at once and is put back if it fails); it
// sends through its `ReactionSender` port and is pure Swift, so it tests on Linux.
// `DailyPushUI` is the view the notification content extension shows.
let package = Package(
    name: "DailyPush",
    defaultLocalization: "zh-Hans",
    platforms: [.iOS("26.0"), .macOS("26.0")],
    products: [
        .library(name: "DailyPushDomain", targets: ["DailyPushDomain"]),
        .library(name: "DailyPushUI", targets: ["DailyPushUI"]),
    ],
    dependencies: [
        .package(path: "../Contracts"),
        .package(path: "../DesignSystem"),
        .package(path: "../Avatar"),
        .package(path: "../Sports"),
        .package(path: "../Feed"),
    ],
    targets: [
        .target(
            name: "DailyPushDomain",
            dependencies: ["Contracts", .product(name: "FeedDomain", package: "Feed")]),
        .target(
            name: "DailyPushUI",
            dependencies: [
                "DailyPushDomain", "Contracts",
                .product(name: "FeedDomain", package: "Feed"),
                .product(name: "DesignSystem", package: "DesignSystem"),
                .product(name: "DesignSystemUI", package: "DesignSystem"),
                .product(name: "AvatarArt", package: "Avatar"),
                .product(name: "AvatarDomain", package: "Avatar"),
                .product(name: "AvatarUI", package: "Avatar"),
                .product(name: "SportsUI", package: "Sports"),
            ],
            resources: [.process("Resources/Localizable.xcstrings"), .process("Resources/Media.xcassets")]
        ),
        .testTarget(
            name: "DailyPushDomainTests",
            dependencies: ["DailyPushDomain", "Contracts", .product(name: "FeedDomain", package: "Feed")]),
        .testTarget(
            name: "DailyPushUITests",
            dependencies: [
                "DailyPushUI", "DailyPushDomain", "Contracts", .product(name: "AvatarArt", package: "Avatar"),
                .product(name: "AvatarDomain", package: "Avatar"),
            ]),
    ]
)
