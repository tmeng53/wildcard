// swift-tools-version: 6.0
import PackageDescription

// Sports as people see them: each sport's name in the String Catalog, its symbol, search by
// name, and `SportPicker`, the sheet of every sport. The list itself is `Contracts`' `Sport`, the
// API's. Shared by 练了, sign-up's 平时练什么？ and 出赛表, so a sport is named the same everywhere.
let package = Package(
    name: "Sports",
    defaultLocalization: "zh-Hans",
    platforms: [.iOS("26.0"), .macOS("26.0")],
    products: [.library(name: "SportsUI", targets: ["SportsUI"])],
    dependencies: [.package(path: "../Contracts"), .package(path: "../DesignSystem")],
    targets: [
        .target(
            name: "SportsUI",
            dependencies: [
                .product(name: "Contracts", package: "Contracts"),
                .product(name: "DesignSystem", package: "DesignSystem"),
                .product(name: "DesignSystemUI", package: "DesignSystem"),
            ],
            resources: [.process("Resources/Localizable.xcstrings")]
        ),
        // The String Catalog read as a file; runs on Linux too.
        .testTarget(
            name: "SportsUITests",
            dependencies: ["SportsUI", .product(name: "Contracts", package: "Contracts")]),
    ]
)
