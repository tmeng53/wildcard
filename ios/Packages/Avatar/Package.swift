// swift-tools-version: 6.0
import PackageDescription

// The character: layered SVG parts on a rig, moved by keyframe clips. `AvatarDomain` is
// pure Swift (parsing, sampling, posing), so it builds and tests on Linux. `AvatarArt`
// bundles the placeholder character's files. `AvatarUI` draws and plays a character.
let package = Package(
    name: "Avatar",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "AvatarDomain", targets: ["AvatarDomain"]),
        .library(name: "AvatarArt", targets: ["AvatarArt"]),
        .library(name: "AvatarUI", targets: ["AvatarUI"]),
    ],
    targets: [
        .target(name: "AvatarDomain"),
        .target(name: "AvatarArt", dependencies: ["AvatarDomain"], resources: [.copy("Placeholder")]),
        .target(name: "AvatarUI", dependencies: ["AvatarDomain", "AvatarArt"]),
        .testTarget(name: "AvatarDomainTests", dependencies: ["AvatarDomain"]),
        .testTarget(name: "AvatarArtTests", dependencies: ["AvatarArt", "AvatarDomain"]),
        .testTarget(name: "AvatarUITests", dependencies: ["AvatarUI", "AvatarArt", "AvatarDomain"]),
    ]
)
