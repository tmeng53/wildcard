// swift-tools-version: 6.0
import PackageDescription

// Signing in and staying signed in. `AccountDomain` holds the session: signing in with a
// credential, handing out a current access token (refreshing it once, however many callers
// ask at the same time), restoring it at launch and signing out. It talks to the auth
// provider and the secure store only through its ports, so it is pure Swift and tests on
// Linux. `AccountUI` is the Apple side: Sign in with Apple, the Keychain store and the
// minimal sign-in entry.
let package = Package(
    name: "Account",
    defaultLocalization: "zh-Hans",
    platforms: [.iOS("26.0"), .macOS("26.0")],
    products: [
        .library(name: "AccountDomain", targets: ["AccountDomain"]),
        .library(name: "AccountUI", targets: ["AccountUI"]),
    ],
    dependencies: [.package(path: "../Contracts")],
    targets: [
        .target(name: "AccountDomain", dependencies: ["Contracts"]),
        .target(name: "AccountUI", dependencies: ["AccountDomain"]),
        .testTarget(name: "AccountDomainTests", dependencies: ["AccountDomain", "Contracts"]),
        // The nonce and the Keychain store; on Linux, where neither exists, it is empty.
        .testTarget(name: "AccountUITests", dependencies: ["AccountUI", "AccountDomain", "Contracts"]),
    ]
)
