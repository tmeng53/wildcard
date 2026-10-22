// swift-tools-version: 6.0
import PackageDescription

// The character editor: the screen that dresses a character and names it, in sign-up and
// later in 我. `CharacterEditorDomain` holds the draft (picks, colors, undo, shuffle; the
// nickname rule is `Contracts`' `Nickname`, the API's) and is pure Swift on top of the Avatar package, so it tests on Linux.
// `CharacterEditorUI` is the screen.
let package = Package(
    name: "CharacterEditor",
    defaultLocalization: "zh-Hans",
    platforms: [.iOS("26.0"), .macOS("26.0")],
    products: [
        .library(name: "CharacterEditorDomain", targets: ["CharacterEditorDomain"]),
        .library(name: "CharacterEditorUI", targets: ["CharacterEditorUI"]),
    ],
    dependencies: [.package(path: "../Avatar"), .package(path: "../Contracts"), .package(path: "../DesignSystem")],
    targets: [
        .target(
            name: "CharacterEditorDomain",
            dependencies: [
                .product(name: "AvatarDomain", package: "Avatar"), .product(name: "AvatarArt", package: "Avatar"),
                .product(name: "Contracts", package: "Contracts"),
            ]),
        .target(
            name: "CharacterEditorUI",
            dependencies: [
                "CharacterEditorDomain",
                .product(name: "AvatarDomain", package: "Avatar"), .product(name: "AvatarArt", package: "Avatar"),
                .product(name: "AvatarUI", package: "Avatar"),
                .product(name: "DesignSystem", package: "DesignSystem"),
                .product(name: "DesignSystemUI", package: "DesignSystem"),
            ],
            resources: [.process("Resources/Localizable.xcstrings")]),
        .testTarget(
            name: "CharacterEditorDomainTests",
            dependencies: [
                "CharacterEditorDomain", .product(name: "AvatarDomain", package: "Avatar"),
                .product(name: "AvatarArt", package: "Avatar"),
            ]),
        // The catalog the screen reads from the bundled art; the screen itself needs a simulator.
        .testTarget(
            name: "CharacterEditorUITests",
            dependencies: [
                "CharacterEditorUI", "CharacterEditorDomain", .product(name: "AvatarDomain", package: "Avatar"),
                .product(name: "AvatarArt", package: "Avatar"),
            ]),
    ]
)
