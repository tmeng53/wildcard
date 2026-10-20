import Foundation
import NotificationsDomain

extension PushEnvironment {
    /// Which APNs servers this build's tokens are for. The simulator's are sandbox. On a phone,
    /// the provisioning profile's `aps-environment` says: a build Xcode installs carries a
    /// development profile, TestFlight and the App Store none at all, so no profile means
    /// production.
    public static var current: PushEnvironment {
        #if targetEnvironment(simulator)
        .sandbox
        #else
        PushEnvironment(
            provisioningProfile: Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision")
                .flatMap { try? Data(contentsOf: $0) })
        #endif
    }

    /// From an `embedded.mobileprovision`: a signed envelope around a plain property list.
    init(provisioningProfile profile: Data?) {
        guard let profile,
            let start = profile.range(of: Data("<?xml".utf8)),
            let end = profile.range(of: Data("</plist>".utf8), in: start.lowerBound..<profile.endIndex),
            let plist = try? PropertyListSerialization.propertyList(
                from: profile[start.lowerBound..<end.upperBound], format: nil) as? [String: Any],
            let entitlements = plist["Entitlements"] as? [String: Any]
        else {
            self = .production
            return
        }
        self = entitlements["aps-environment"] as? String == "development" ? .sandbox : .production
    }
}
