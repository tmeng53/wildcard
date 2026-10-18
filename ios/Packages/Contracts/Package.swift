// swift-tools-version: 6.0
import PackageDescription

// Types every capability shares: ids, the member's local day, and the check-in
// as it is stored and sent. Pure Swift with no dependencies, so it builds on Linux.
let package = Package(
    name: "Contracts",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "Contracts", targets: ["Contracts"])],
    targets: [
        .target(name: "Contracts"),
        .testTarget(name: "ContractsTests", dependencies: ["Contracts"]),
    ]
)
