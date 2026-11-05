// swift-tools-version: 6.0
import PackageDescription

// 群聊, the squad's group chat, opened from the round button beside 打卡 on 今天. `ChatDomain`
// holds what the screen reads and its rules: messages oldest first with the member's own shown
// at once and sent behind under their own id (so a retry saves once), replies, @s, reactions,
// deleting and reporting, the push alerts, how far the member read, and the coach's three dots;
// it loads through its `ChatSource` port and is pure Swift, so it builds and tests on Linux.
// `ChatUI` is the screen and the entry button.
let package = Package(
    name: "Chat",
    defaultLocalization: "zh-Hans",
    platforms: [.iOS("26.0"), .macOS("26.0")],
    products: [
        .library(name: "ChatDomain", targets: ["ChatDomain"]),
        .library(name: "ChatUI", targets: ["ChatUI"]),
    ],
    dependencies: [
        .package(path: "../Contracts"),
        .package(path: "../DesignSystem"),
        .package(path: "../Avatar"),
    ],
    targets: [
        .target(name: "ChatDomain", dependencies: ["Contracts"]),
        .target(
            name: "ChatUI",
            dependencies: [
                "ChatDomain", "Contracts",
                .product(name: "DesignSystem", package: "DesignSystem"),
                .product(name: "DesignSystemUI", package: "DesignSystem"),
                .product(name: "AvatarArt", package: "Avatar"),
                .product(name: "AvatarDomain", package: "Avatar"),
                .product(name: "AvatarUI", package: "Avatar"),
            ],
            resources: [.process("Resources/Localizable.xcstrings")]
        ),
        .testTarget(name: "ChatDomainTests", dependencies: ["ChatDomain", "Contracts"]),
        // The screen's String Catalog read as a file; runs on Linux too.
        .testTarget(name: "ChatUITests", dependencies: ["ChatUI", "ChatDomain"]),
    ]
)
