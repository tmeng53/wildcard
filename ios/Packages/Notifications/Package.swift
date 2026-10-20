// swift-tools-version: 6.0
import PackageDescription

// Push notifications on this phone. `NotificationsDomain` decides when to ask for permission
// (after the member's first check-in, never at sign-up) and hands the phone's device token to
// the API once someone is signed in. It reaches iOS and the API only through its ports, so it
// is pure Swift and tests on Linux. `NotificationsUI` is the Apple side: the permission prompt,
// APNs registration, which APNs servers this build's tokens are for, and taps on a
// notification.
let package = Package(
    name: "Notifications",
    platforms: [.iOS("26.0"), .macOS("26.0")],
    products: [
        .library(name: "NotificationsDomain", targets: ["NotificationsDomain"]),
        .library(name: "NotificationsUI", targets: ["NotificationsUI"]),
    ],
    targets: [
        .target(name: "NotificationsDomain"),
        .target(name: "NotificationsUI", dependencies: ["NotificationsDomain"]),
        .testTarget(name: "NotificationsDomainTests", dependencies: ["NotificationsDomain"]),
        // Reading the provisioning profile; the iOS-only parts are covered by the app's build.
        .testTarget(name: "NotificationsUITests", dependencies: ["NotificationsUI", "NotificationsDomain"]),
    ]
)
