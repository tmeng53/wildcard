// swift-tools-version: 6.0
import PackageDescription

// The Sunday 战报: a squad's week told as a story of full-screen pages. The weekly AI run fills
// one template per squad-week on the server; the app only plays it. `RecapDomain` holds the
// story as the app reads it, which pages play in which order, how long each lasts, what the
// characters do on each, and the tap-to-advance player; it is pure Swift, so it tests on Linux.
// `RecapUI` draws the pages, the covered entry tile in 动态 and the pending page.
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
    ],
    targets: [
        .target(name: "RecapDomain", dependencies: ["Contracts"]),
        .target(
            name: "RecapUI",
            dependencies: [
                "RecapDomain", "Contracts",
                .product(name: "DesignSystem", package: "DesignSystem"),
                .product(name: "DesignSystemUI", package: "DesignSystem"),
                .product(name: "AvatarArt", package: "Avatar"),
                .product(name: "AvatarDomain", package: "Avatar"),
                .product(name: "AvatarUI", package: "Avatar"),
            ],
            resources: [.process("Resources/Localizable.xcstrings")]
        ),
        .testTarget(name: "RecapDomainTests", dependencies: ["RecapDomain", "Contracts"]),
        // The String Catalog read as a file; runs on Linux too.
        .testTarget(name: "RecapUITests", dependencies: ["RecapUI"]),
    ]
)
