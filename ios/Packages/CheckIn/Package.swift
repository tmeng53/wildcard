// swift-tools-version: 6.0
import PackageDescription

// Checking in. `CheckInDomain` holds the rules (which day a check-in counts for, what may be
// posted or deleted, the weekly, squad and lifetime counts); it is pure Swift on top of
// `Contracts`, so it builds and tests on Linux. `CheckInUI` is the 今天 screen: the 打卡 burst,
// the photo and compose steps, the 免责声明 card and the payoff on the scene.
let package = Package(
    name: "CheckIn",
    defaultLocalization: "zh-Hans",
    platforms: [.iOS("26.0"), .macOS("26.0")],
    products: [
        .library(name: "CheckInDomain", targets: ["CheckInDomain"]),
        .library(name: "CheckInUI", targets: ["CheckInUI"]),
    ],
    dependencies: [
        .package(path: "../Contracts"),
        .package(path: "../DesignSystem"),
        .package(path: "../Avatar"),
    ],
    targets: [
        .target(name: "CheckInDomain", dependencies: ["Contracts"]),
        .target(
            name: "CheckInUI",
            dependencies: [
                "CheckInDomain", "Contracts",
                .product(name: "DesignSystem", package: "DesignSystem"),
                .product(name: "DesignSystemUI", package: "DesignSystem"),
                .product(name: "AvatarArt", package: "Avatar"),
                .product(name: "AvatarUI", package: "Avatar"),
            ],
            resources: [.process("Resources/Localizable.xcstrings")]
        ),
        .testTarget(name: "CheckInDomainTests", dependencies: ["CheckInDomain", "Contracts"]),
        // The screen's non-visual parts, and its String Catalog read as a file; runs on Linux too.
        .testTarget(name: "CheckInUITests", dependencies: ["CheckInUI", "CheckInDomain", "Contracts"]),
    ]
)
