// swift-tools-version: 6.0
import PackageDescription

// 我: the member's own tab. `MeDomain` holds what the tab shows and does (the overview, the
// switches, signing out and deleting the account) behind its `MeService` port, and is pure Swift,
// so it tests on Linux. `MeUI` is the tab (the player card), its 设置 page and 注销账号.
let package = Package(
    name: "Me",
    defaultLocalization: "zh-Hans",
    platforms: [.iOS("26.0"), .macOS("26.0")],
    products: [
        .library(name: "MeDomain", targets: ["MeDomain"]),
        .library(name: "MeUI", targets: ["MeUI"]),
    ],
    dependencies: [
        .package(path: "../Avatar"), .package(path: "../Contracts"), .package(path: "../DesignSystem"),
    ],
    targets: [
        .target(
            name: "MeDomain",
            dependencies: [
                .product(name: "AvatarDomain", package: "Avatar"), .product(name: "AvatarArt", package: "Avatar"),
                .product(name: "Contracts", package: "Contracts"),
            ]),
        .target(
            name: "MeUI",
            dependencies: [
                "MeDomain",
                .product(name: "AvatarDomain", package: "Avatar"), .product(name: "AvatarArt", package: "Avatar"),
                .product(name: "AvatarUI", package: "Avatar"), .product(name: "Contracts", package: "Contracts"),
                .product(name: "DesignSystem", package: "DesignSystem"),
                .product(name: "DesignSystemUI", package: "DesignSystem"),
            ],
            resources: [.process("Resources/Localizable.xcstrings")]),
        .testTarget(
            name: "MeDomainTests",
            dependencies: [
                "MeDomain", .product(name: "AvatarArt", package: "Avatar"),
                .product(name: "Contracts", package: "Contracts"),
            ]),
        // The model and its String Catalog read as a file; the screens need a simulator.
        .testTarget(
            name: "MeUITests",
            dependencies: ["MeUI", "MeDomain", .product(name: "AvatarArt", package: "Avatar")]),
    ]
)
