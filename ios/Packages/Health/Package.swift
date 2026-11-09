// swift-tools-version: 6.0
import PackageDescription

// Apple Health, read only: the workouts a 训练 can be posted from. `HealthDomain` holds the
// workouts as the app imports them, what the member shares by default and which of today's are
// posted already, behind its `HealthLibrary` port; pure Swift, so it tests on Linux. `HealthUI`
// is the HealthKit adapter, the sample library previews and UI tests run on, and
// 设置 › Apple 健康. Provider-neutral on the way out: what leaves is `Contracts`' `Workout`, so a
// Fitbit or Garmin adapter later fills the same type.
let package = Package(
    name: "Health",
    defaultLocalization: "zh-Hans",
    platforms: [.iOS("26.0"), .macOS("26.0")],
    products: [
        .library(name: "HealthDomain", targets: ["HealthDomain"]),
        .library(name: "HealthUI", targets: ["HealthUI"]),
    ],
    dependencies: [.package(path: "../Contracts"), .package(path: "../DesignSystem"), .package(path: "../Sports")],
    targets: [
        .target(name: "HealthDomain", dependencies: [.product(name: "Contracts", package: "Contracts")]),
        .target(
            name: "HealthUI",
            dependencies: [
                "HealthDomain", .product(name: "Contracts", package: "Contracts"),
                .product(name: "DesignSystem", package: "DesignSystem"),
                .product(name: "DesignSystemUI", package: "DesignSystem"),
                .product(name: "SportsUI", package: "Sports"),
            ],
            resources: [.process("Resources/Localizable.xcstrings")]),
        .testTarget(
            name: "HealthDomainTests",
            dependencies: ["HealthDomain", .product(name: "Contracts", package: "Contracts")]),
    ]
)
