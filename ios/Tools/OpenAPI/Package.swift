// swift-tools-version: 6.0
import PackageDescription

// Pins Apple's Swift OpenAPI Generator for `scripts/swift-openapi.sh`, which turns the API's
// OpenAPI document into the Swift in `ios/Packages/Contracts/Sources/APIContract/Generated`.
// Only that script builds this package; the app never depends on it.
let package = Package(
    name: "OpenAPITools",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/apple/swift-openapi-generator", exact: "1.14.1")
    ]
)
