// swift-tools-version: 6.0
import PackageDescription

// Roughly where the phone is, so the squad's coach knows the member's weather (Tracy,
// 2026-11-08). `LocationDomain` decides when to ask and what to send: the approximate location
// iOS gives, sent when it moved or a day passed and forgotten on the server once the member stops
// allowing it, with the city iOS names there so the coach can say where they are (Tracy,
// 2026-11-12), behind its `LocationReader` and `LocationRegistry` ports; pure Swift, so it tests
// on Linux. `LocationUI` is the Core Location and MapKit adapter, asking only for approximate
// location.
let package = Package(
    name: "Location",
    platforms: [.iOS("26.0"), .macOS("26.0")],
    products: [
        .library(name: "LocationDomain", targets: ["LocationDomain"]),
        .library(name: "LocationUI", targets: ["LocationUI"]),
    ],
    dependencies: [.package(path: "../Contracts")],
    targets: [
        .target(name: "LocationDomain", dependencies: [.product(name: "Contracts", package: "Contracts")]),
        .target(
            name: "LocationUI",
            dependencies: ["LocationDomain", .product(name: "Contracts", package: "Contracts")]
        ),
        .testTarget(
            name: "LocationDomainTests",
            dependencies: ["LocationDomain", .product(name: "Contracts", package: "Contracts")]
        ),
    ]
)
