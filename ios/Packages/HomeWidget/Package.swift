// swift-tools-version: 6.0
import PackageDescription

// The home screen widgets (桌面小组件): 我的一周, small, and 小队今天, medium. `HomeWidgetDomain`
// turns the home the app keeps (`CheckInDomain`'s `Home`) and today's Apple Health workouts into
// what a widget shows, says when it should look again and which place in the app a tap opens; it
// is pure Swift, so it tests on Linux. `HomeWidgetUI` draws the two widgets from design system
// pieces and the squad's characters; the app's widget extension wires them to WidgetKit.
let package = Package(
    name: "HomeWidget",
    defaultLocalization: "zh-Hans",
    platforms: [.iOS("26.0"), .macOS("26.0")],
    products: [
        .library(name: "HomeWidgetDomain", targets: ["HomeWidgetDomain"]),
        .library(name: "HomeWidgetUI", targets: ["HomeWidgetUI"]),
    ],
    dependencies: [
        .package(path: "../Contracts"),
        .package(path: "../DesignSystem"),
        .package(path: "../Avatar"),
        .package(path: "../CheckIn"),
        .package(path: "../Sports"),
        .package(path: "../Health"),
    ],
    targets: [
        .target(
            name: "HomeWidgetDomain",
            dependencies: [
                "Contracts", .product(name: "CheckInDomain", package: "CheckIn"),
                .product(name: "HealthDomain", package: "Health"),
            ]),
        .target(
            name: "HomeWidgetUI",
            dependencies: [
                "HomeWidgetDomain", "Contracts",
                .product(name: "DesignSystem", package: "DesignSystem"),
                .product(name: "DesignSystemUI", package: "DesignSystem"),
                .product(name: "AvatarArt", package: "Avatar"),
                .product(name: "AvatarDomain", package: "Avatar"),
                .product(name: "AvatarUI", package: "Avatar"),
                .product(name: "CheckInDomain", package: "CheckIn"),
                .product(name: "SportsUI", package: "Sports"),
                .product(name: "HealthDomain", package: "Health"),
            ],
            resources: [.process("Resources/Localizable.xcstrings")]),
        .testTarget(
            name: "HomeWidgetDomainTests",
            dependencies: [
                "HomeWidgetDomain", "Contracts", .product(name: "CheckInDomain", package: "CheckIn"),
                .product(name: "HealthDomain", package: "Health"),
            ]),
        // Reads HomeWidgetUI's sources and catalog as files, so it runs on Linux too.
        .testTarget(name: "HomeWidgetUITests"),
    ]
)
