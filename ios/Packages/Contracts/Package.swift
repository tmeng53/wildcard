// swift-tools-version: 6.0
import PackageDescription

// Types every capability shares, and the API's wire types.
// - `Contracts`: ids, the member's local day, the check-in as the app holds it. Pure Swift with
//   no dependencies, so `Domain` targets build on it on Linux.
// - `APIContract`: the Swift that scripts/swift-openapi.sh generates from the API's OpenAPI
//   document (`Generated/`, never edited by hand), and the mapping between it and `Contracts`.
//   Only adapters that talk to the API import it.
let package = Package(
    name: "Contracts",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "Contracts", targets: ["Contracts"]),
        .library(name: "APIContract", targets: ["APIContract"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-openapi-runtime", from: "1.13.1")
    ],
    targets: [
        .target(name: "Contracts"),
        .target(
            name: "APIContract",
            dependencies: ["Contracts", .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime")]),
        .testTarget(name: "ContractsTests", dependencies: ["Contracts"]),
        .testTarget(
            name: "APIContractTests",
            dependencies: [
                "APIContract", "Contracts", .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
            ]),
    ]
)
