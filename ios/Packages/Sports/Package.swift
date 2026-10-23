// swift-tools-version: 6.0
import PackageDescription

// Sports as people see them: each sport's name in the String Catalog, its symbol, and search by
// name. The list itself is `Contracts`' `Sport`, the API's. Shared by 练了 and sign-up's
// 平时练什么？, so a sport is named the same everywhere.
let package = Package(
    name: "Sports",
    defaultLocalization: "zh-Hans",
    platforms: [.iOS("26.0"), .macOS("26.0")],
    products: [.library(name: "SportsUI", targets: ["SportsUI"])],
    dependencies: [.package(path: "../Contracts")],
    targets: [
        .target(
            name: "SportsUI",
            dependencies: [.product(name: "Contracts", package: "Contracts")],
            resources: [.process("Resources/Localizable.xcstrings")]
        ),
        // The String Catalog read as a file; runs on Linux too.
        .testTarget(
            name: "SportsUITests",
            dependencies: ["SportsUI", .product(name: "Contracts", package: "Contracts")]),
    ]
)
