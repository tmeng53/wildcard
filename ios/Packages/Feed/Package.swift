// swift-tools-version: 6.0
import PackageDescription

// The 动态 tab: the squad's check-ins, newest first, with teammates' reactions and the replies
// on a 请假条. `FeedDomain` holds what the screen reads and the rules of responding (one
// reaction and one reply per teammate, none on your own post, which move the author's
// character plays) and loads through its `FeedSource` port. It is pure Swift, so it builds and
// tests on Linux.
let package = Package(
    name: "Feed",
    platforms: [.iOS("26.0"), .macOS("26.0")],
    products: [
        .library(name: "FeedDomain", targets: ["FeedDomain"])
    ],
    dependencies: [
        .package(path: "../Contracts")
    ],
    targets: [
        .target(name: "FeedDomain", dependencies: ["Contracts"]),
        .testTarget(name: "FeedDomainTests", dependencies: ["FeedDomain", "Contracts"]),
    ]
)
