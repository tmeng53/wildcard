import Foundation
import NotificationsDomain
import Testing

@testable import NotificationsUI

/// A provisioning profile as Apple ships it: signature bytes around the property list.
private func profile(apsEnvironment: String?) -> Data {
    let entitlement = apsEnvironment.map { "<key>aps-environment</key><string>\($0)</string>" } ?? ""
    let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict>
        <key>Name</key><string>Wildcard Development</string>
        <key>Entitlements</key><dict>\(entitlement)<key>get-task-allow</key><true/></dict>
        </dict></plist>
        """
    return Data([0x30, 0x82, 0x3f, 0x00, 0x06, 0x09]) + Data(plist.utf8) + Data([0xa0, 0x82, 0x0e, 0x3c])
}

@Test func aDevelopmentProfileGetsSandboxTokens() {
    #expect(PushEnvironment(provisioningProfile: profile(apsEnvironment: "development")) == .sandbox)
}

@Test func anAdHocProfileGetsProductionTokens() {
    #expect(PushEnvironment(provisioningProfile: profile(apsEnvironment: "production")) == .production)
}

@Test func noProfileAsInTestFlightAndTheAppStoreIsProduction() {
    #expect(PushEnvironment(provisioningProfile: nil) == .production)
    #expect(PushEnvironment(provisioningProfile: Data("not a profile".utf8)) == .production)
    #expect(PushEnvironment(provisioningProfile: profile(apsEnvironment: nil)) == .production)
}
