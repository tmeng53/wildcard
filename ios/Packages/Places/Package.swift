// swift-tools-version: 6.0
import PackageDescription

// A place's own page (地点页, Tracy 2026-11-12): any place in Apple Maps or one the squad added, as
// a business card over its map, with what the squad did there. Every place in the app opens it:
// a post's place tag, the 战报, 收藏 and the squad's map. `PlacesDomain` holds the page as the app
// reads it (the squad's numbers, its rows and posts, what Maps says) behind its `PlaceSource` and
// `PlaceDirectory` ports; it is pure Swift, so it tests on Linux. `PlacesUI` draws the page and
// reads Maps through MapKit.
let package = Package(
    name: "Places",
    defaultLocalization: "zh-Hans",
    platforms: [.iOS("26.0"), .macOS("26.0")],
    products: [
        .library(name: "PlacesDomain", targets: ["PlacesDomain"]),
        .library(name: "PlacesUI", targets: ["PlacesUI"]),
    ],
    dependencies: [
        .package(path: "../Contracts"),
        .package(path: "../DesignSystem"),
        .package(path: "../Avatar"),
        .package(path: "../Sports"),
        // A place's kind and its icon, as the post's tag shows it.
        .package(path: "../CheckIn"),
        // 今天, 昨天, 周三: a post's day as 动态 says it.
        .package(path: "../Feed"),
    ],
    targets: [
        .target(
            name: "PlacesDomain",
            dependencies: [
                "Contracts", .product(name: "DesignSystem", package: "DesignSystem"),
                .product(name: "CheckInDomain", package: "CheckIn"),
                // The sample squad's numbers, counted from its 动态.
                .product(name: "FeedDomain", package: "Feed"),
            ]),
        .target(
            name: "PlacesUI",
            dependencies: [
                "PlacesDomain", "Contracts",
                .product(name: "DesignSystem", package: "DesignSystem"),
                .product(name: "DesignSystemUI", package: "DesignSystem"),
                .product(name: "AvatarArt", package: "Avatar"),
                .product(name: "AvatarDomain", package: "Avatar"),
                .product(name: "AvatarUI", package: "Avatar"),
                .product(name: "SportsUI", package: "Sports"),
                .product(name: "CheckInDomain", package: "CheckIn"),
                .product(name: "FeedDomain", package: "Feed"),
                .product(name: "FeedUI", package: "Feed"),
            ],
            resources: [.process("Resources/Localizable.xcstrings")]
        ),
        .testTarget(
            name: "PlacesDomainTests",
            dependencies: [
                "PlacesDomain", "Contracts", .product(name: "DesignSystem", package: "DesignSystem"),
                .product(name: "FeedDomain", package: "Feed"),
            ]),
        // The String Catalog read as a file; runs on Linux too.
        .testTarget(name: "PlacesUITests", dependencies: ["PlacesUI"]),
    ]
)
