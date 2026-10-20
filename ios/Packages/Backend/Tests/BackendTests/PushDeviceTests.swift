import AccountDomain
import Foundation
import NotificationsDomain
import Testing

@testable import Backend

// Registering this phone for pushes against the built API, as `PushRegistration` does once a
// member is signed in. These prove the API takes what the client sends; which member a phone
// belongs to is checked by the push module's own tests (`api/packages/push`).

private func newToken() -> DeviceToken {
    DeviceToken((0..<32).map { _ in UInt8.random(in: 0...255) })
}

@Test func aSignedInMemberRegistersThisPhoneAndRemovesItOnSigningOut() async throws {
    let stack = try LocalStack()
    let member = try await stack.signedInMember()
    let phone = PushDevice(token: newToken(), environment: .sandbox)

    try await member.api.register(phone)
    // Every launch registers again.
    try await member.api.register(phone)
    try await member.api.removeDevice(phone.token)
    // Removing again, as a sign-out retried after a dropped connection, is fine too.
    try await member.api.removeDevice(phone.token)
}

@Test func somethingThatIsNotAnAPNsTokenIsRefused() async throws {
    let stack = try LocalStack()
    let member = try await stack.signedInMember()
    do {
        try await member.api.register(PushDevice(token: DeviceToken([0x01]), environment: .sandbox))
        Issue.record("a one-byte token was registered")
    } catch {
        guard case .refused(.invalid) = error else {
            Issue.record("unexpected \(error)")
            return
        }
    }
}

@Test func pushRegistrationSendsTheTokenThroughTheAPI() async throws {
    let stack = try LocalStack()
    let member = try await stack.signedInMember()
    let registration = PushRegistration(system: AllowedPush(), environment: .sandbox)

    try await registration.received(newToken())
    try await registration.signedIn(APIDeviceRegistry(api: member.api))
    try await registration.signingOut()
}

@Test func aSessionThatIsOverIsSignedOutForPushRegistration() async throws {
    let stack = try LocalStack()
    let member = try await stack.signedInMember()
    try await member.account.signOut()
    let registry = APIDeviceRegistry(api: member.api)

    await #expect(throws: NotificationsError.signedOut) {
        try await registry.register(PushDevice(token: newToken(), environment: .sandbox))
    }
}

@Test func anUnreachableAPIIsUnavailableForPushRegistration() async throws {
    let api = WildcardAPI(url: try #require(URL(string: "http://127.0.0.1:9"))) { _ async throws(AccountError) in
        "token"
    }
    await #expect(throws: NotificationsError.unavailable) {
        try await APIDeviceRegistry(api: api).register(PushDevice(token: newToken(), environment: .sandbox))
    }
}

/// A phone that already allows notifications.
private struct AllowedPush: PushSystem {
    func authorization() async -> PushAuthorization { .allowed }
    func requestAuthorization() async -> Bool { true }
    func registerForRemoteNotifications() async {}
}
