// swift-tools-version: 6.0
import PackageDescription

// The check-in rules: which day a check-in counts for, what may be posted or deleted,
// and the weekly and lifetime counts. `CheckInDomain` is pure Swift on top of
// `Contracts`, so it builds and tests on Linux. The screens come later as `CheckInUI`.
let package = Package(
    name: "CheckIn",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "CheckInDomain", targets: ["CheckInDomain"])],
    dependencies: [.package(path: "../Contracts")],
    targets: [
        .target(name: "CheckInDomain", dependencies: ["Contracts"]),
        .testTarget(name: "CheckInDomainTests", dependencies: ["CheckInDomain", "Contracts"]),
    ]
)
