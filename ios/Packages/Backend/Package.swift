// swift-tools-version: 6.0
import PackageDescription

// The adapters that talk to our providers and our API. Foundation only, so it builds and tests
// on Linux, where its tests run against local Supabase and the built API
// (`scripts/verify.sh backend`).
// - `SupabaseAuth`, the `AuthProvider` behind `AccountSession`: the only code in the app that
//   knows Supabase Auth's HTTP API, so changing provider means replacing it.
// - `WildcardAPI`, the client of our own API: the client scripts/swift-openapi.sh generates
//   (`Generated/`, never edited by hand) behind calls that take and return `Contracts` types.
// - `APIDeviceRegistry` puts it behind the `DeviceRegistry` that push registration talks to.
// - `APICheckInBackend`, `DeviceOutbox` and `APIDisclaimerWriter`, the adapters behind
//   `CheckInDomain`'s ports: the home and 打卡 over the API, with a copy of the home and the
//   posts still to go out kept on the device.
// - `APISignUpService`, the adapter behind `OnboardingDomain`'s `SignUpService`: the squad, the
//   character and the first week's plan saved through the API.
// - `APIMeService`, the adapter behind `MeDomain`'s `MeService`: 我's overview, the daily push
//   switch and deleting the account.
// - `APIFeedSource`, the adapter behind `FeedDomain`'s `FeedSource`: 动态's posts with their
//   reactions, the squad's characters and the photos.
// - `APISquadSettingsService`, behind `SquadDomain`'s `SquadSettingsService`: 小队设置; and
//   `APIScenePickService`, behind `ScenePickDomain`'s `ScenePickService`: the 战报's scene pick.
// - `APIScheduleBackend`, the adapter behind `ScheduleDomain`'s `ScheduleBackend`: 出赛表's weekly
//   plans and 饮食小目标, the days checked in, the week's titles and the squad's count.
let package = Package(
    name: "Backend",
    platforms: [.iOS("26.0"), .macOS("26.0")],
    products: [.library(name: "Backend", targets: ["Backend"])],
    dependencies: [
        .package(path: "../Account"),
        .package(path: "../Avatar"),
        .package(path: "../CheckIn"),
        .package(path: "../Contracts"),
        .package(path: "../Feed"),
        .package(path: "../DesignSystem"),
        .package(path: "../Me"),
        .package(path: "../Notifications"),
        .package(path: "../Onboarding"),
        .package(path: "../ScenePick"),
        .package(path: "../Squad"),
        .package(path: "../Schedule"),
        .package(url: "https://github.com/apple/swift-http-types", from: "1.8.0"),
        .package(url: "https://github.com/apple/swift-openapi-runtime", from: "1.13.1"),
        .package(url: "https://github.com/apple/swift-openapi-urlsession", from: "1.2.0"),
    ],
    targets: [
        .target(
            name: "Backend",
            dependencies: [
                .product(name: "AccountDomain", package: "Account"),
                .product(name: "AvatarArt", package: "Avatar"), .product(name: "AvatarDomain", package: "Avatar"),
                .product(name: "CheckInDomain", package: "CheckIn"), "Contracts",
                .product(name: "APIContract", package: "Contracts"),
                .product(name: "FeedDomain", package: "Feed"),
                .product(name: "MeDomain", package: "Me"),
                .product(name: "NotificationsDomain", package: "Notifications"),
                .product(name: "OnboardingDomain", package: "Onboarding"),
                .product(name: "DesignSystem", package: "DesignSystem"),
                .product(name: "ScenePickDomain", package: "ScenePick"),
                .product(name: "SquadDomain", package: "Squad"),
                .product(name: "ScheduleDomain", package: "Schedule"),
                .product(name: "HTTPTypes", package: "swift-http-types"),
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
                .product(name: "OpenAPIURLSession", package: "swift-openapi-urlsession"),
            ]),
        .testTarget(
            name: "BackendTests",
            dependencies: [
                "Backend", .product(name: "AccountDomain", package: "Account"),
                .product(name: "AvatarArt", package: "Avatar"), .product(name: "AvatarDomain", package: "Avatar"),
                .product(name: "CheckInDomain", package: "CheckIn"), "Contracts",
                .product(name: "FeedDomain", package: "Feed"),
                .product(name: "MeDomain", package: "Me"),
                .product(name: "NotificationsDomain", package: "Notifications"),
                .product(name: "OnboardingDomain", package: "Onboarding"),
                .product(name: "DesignSystem", package: "DesignSystem"),
                .product(name: "ScenePickDomain", package: "ScenePick"),
                .product(name: "SquadDomain", package: "Squad"),
                .product(name: "ScheduleDomain", package: "Schedule"),
            ]),
    ]
)
