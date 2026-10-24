// swift-tools-version: 6.0
import PackageDescription

// Sign-up: the open screen, then 角色和昵称, 小队, 平时练什么？, 定个本周目标 and 上场, the
// entrance into the squad. `OnboardingDomain` holds the flow and each step's draft (the squad
// choice, the sports picked, the week, the welcome lines and who cheers when, and the open
// screen's finish-line sprint); it is pure Swift
// with the backend behind its `SignUpService` port, so it tests on Linux. `OnboardingUI` is the
// screens; step 1 is the character editor itself, and 上场 plays on home's own scene and spots
// (`CheckIn`).
let package = Package(
    name: "Onboarding",
    defaultLocalization: "zh-Hans",
    platforms: [.iOS("26.0"), .macOS("26.0")],
    products: [
        .library(name: "OnboardingDomain", targets: ["OnboardingDomain"]),
        .library(name: "OnboardingUI", targets: ["OnboardingUI"]),
    ],
    dependencies: [
        .package(path: "../Avatar"),
        .package(path: "../CharacterEditor"),
        .package(path: "../CheckIn"),
        .package(path: "../Contracts"),
        .package(path: "../DesignSystem"),
        .package(path: "../Sports"),
    ],
    targets: [
        .target(
            name: "OnboardingDomain",
            dependencies: [
                .product(name: "AvatarArt", package: "Avatar"), .product(name: "AvatarDomain", package: "Avatar"),
                .product(name: "Contracts", package: "Contracts"),
            ]),
        .target(
            name: "OnboardingUI",
            dependencies: [
                "OnboardingDomain",
                .product(name: "AvatarArt", package: "Avatar"), .product(name: "AvatarDomain", package: "Avatar"),
                .product(name: "AvatarUI", package: "Avatar"),
                .product(name: "CharacterEditorDomain", package: "CharacterEditor"),
                .product(name: "CharacterEditorUI", package: "CharacterEditor"),
                .product(name: "CheckInDomain", package: "CheckIn"), .product(name: "CheckInUI", package: "CheckIn"),
                .product(name: "Contracts", package: "Contracts"),
                .product(name: "DesignSystem", package: "DesignSystem"),
                .product(name: "DesignSystemUI", package: "DesignSystem"),
                .product(name: "SportsUI", package: "Sports"),
            ],
            resources: [.process("Resources/Localizable.xcstrings")]),
        .testTarget(
            name: "OnboardingDomainTests",
            dependencies: [
                "OnboardingDomain", .product(name: "AvatarArt", package: "Avatar"),
                .product(name: "AvatarDomain", package: "Avatar"), .product(name: "Contracts", package: "Contracts"),
            ]),
        // The screens' String Catalog read as a file, and the in-memory backend; runs on Linux too.
        .testTarget(
            name: "OnboardingUITests",
            dependencies: [
                "OnboardingUI", "OnboardingDomain", .product(name: "AvatarArt", package: "Avatar"),
                .product(name: "Contracts", package: "Contracts"),
            ]),
    ]
)
