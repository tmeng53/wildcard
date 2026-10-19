// swift-tools-version: 6.0
import PackageDescription

// The character: layered SVG parts on a rig, moved by keyframe clips. `AvatarDomain` is
// pure Swift (parsing, sampling, posing), so it builds and tests on Linux. `AvatarArt`
// bundles the placeholder character's files and its preset colors, taken from the design
// system's palette. `AvatarUI` draws and plays a character.
let package = Package(
    name: "Avatar",
    platforms: [.iOS("26.0"), .macOS("26.0")],
    products: [
        .library(name: "AvatarDomain", targets: ["AvatarDomain"]),
        .library(name: "AvatarArt", targets: ["AvatarArt"]),
        .library(name: "AvatarUI", targets: ["AvatarUI"]),
    ],
    dependencies: [.package(path: "../DesignSystem")],
    targets: [
        .target(name: "AvatarDomain"),
        .target(
            name: "AvatarArt",
            dependencies: ["AvatarDomain", .product(name: "DesignSystem", package: "DesignSystem")],
            resources: [.copy("Placeholder")]),
        .target(name: "AvatarUI", dependencies: ["AvatarDomain", "AvatarArt"]),
        // The looks the tests and previews share; no product, so only this package's tests see it.
        .target(name: "AvatarLooks", dependencies: ["AvatarArt", "AvatarDomain"], path: "Tests/AvatarLooks"),
        .testTarget(name: "AvatarDomainTests", dependencies: ["AvatarDomain"]),
        .testTarget(name: "AvatarArtTests", dependencies: ["AvatarArt", "AvatarDomain", "AvatarLooks"]),
        .testTarget(name: "AvatarUITests", dependencies: ["AvatarUI", "AvatarArt", "AvatarDomain", "AvatarLooks"]),
    ]
)
