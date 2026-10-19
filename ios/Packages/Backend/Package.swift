// swift-tools-version: 6.0
import PackageDescription

// The adapters that talk to our providers and our API. Foundation only, so it builds and tests
// on Linux, where its tests run against local Supabase and the built API
// (`scripts/verify.sh backend`).
// - `SupabaseAuth`, the `AuthProvider` behind `AccountSession`: the only code in the app that
//   knows Supabase Auth's HTTP API, so changing provider means replacing it.
// - `WildcardAPI`, the client of our own API: the client scripts/swift-openapi.sh generates
//   (`Generated/`, never edited by hand) behind calls that take and return `Contracts` types.
let package = Package(
    name: "Backend",
    platforms: [.iOS("26.0"), .macOS("26.0")],
    products: [.library(name: "Backend", targets: ["Backend"])],
    dependencies: [
        .package(path: "../Account"),
        .package(path: "../Contracts"),
        .package(url: "https://github.com/apple/swift-http-types", from: "1.8.0"),
        .package(url: "https://github.com/apple/swift-openapi-runtime", from: "1.13.1"),
        .package(url: "https://github.com/apple/swift-openapi-urlsession", from: "1.2.0"),
    ],
    targets: [
        .target(
            name: "Backend",
            dependencies: [
                .product(name: "AccountDomain", package: "Account"), "Contracts",
                .product(name: "APIContract", package: "Contracts"),
                .product(name: "HTTPTypes", package: "swift-http-types"),
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
                .product(name: "OpenAPIURLSession", package: "swift-openapi-urlsession"),
            ]),
        .testTarget(
            name: "BackendTests",
            dependencies: ["Backend", .product(name: "AccountDomain", package: "Account"), "Contracts"]),
    ]
)
