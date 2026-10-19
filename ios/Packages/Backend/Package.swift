// swift-tools-version: 6.0
import PackageDescription

// The adapters that talk to our providers. `SupabaseAuth` is the `AuthProvider` behind
// `AccountSession`: it is the only code in the app that knows Supabase Auth's HTTP API, so
// changing provider means replacing it. Foundation only, so it builds and tests on Linux, where
// its tests run against local Supabase (`scripts/verify.sh backend`).
let package = Package(
    name: "Backend",
    platforms: [.iOS("26.0"), .macOS("26.0")],
    products: [.library(name: "Backend", targets: ["Backend"])],
    dependencies: [
        .package(path: "../Account"),
        .package(path: "../Contracts"),
    ],
    targets: [
        .target(
            name: "Backend",
            dependencies: [.product(name: "AccountDomain", package: "Account"), "Contracts"]),
        .testTarget(
            name: "BackendTests",
            dependencies: ["Backend", .product(name: "AccountDomain", package: "Account"), "Contracts"]),
    ]
)
