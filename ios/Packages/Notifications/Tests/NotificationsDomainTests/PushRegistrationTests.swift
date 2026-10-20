import NotificationsDomain
import Testing

@Test func aTokenIsLowercaseHexTwoDigitsAByte() {
    #expect(DeviceToken([0x00, 0x0a, 0xff, 0x10]).description == "000aff10")
    #expect(token.description == "0aff10" + String(repeating: "01", count: 29))
}

@Test func theFirstCheckInAsksForPermissionAndRegistersWhenAllowed() async {
    let system = FakeSystem(.notDetermined)
    let registration = PushRegistration(system: system, environment: .sandbox)

    await registration.checkedIn()
    #expect(await system.prompts == 1)
    #expect(await system.registrations == 1)

    // The member has answered, so later check-ins never ask again.
    await registration.checkedIn()
    #expect(await system.prompts == 1)
    #expect(await system.registrations == 1)
}

@Test func aMemberWhoSaysNoIsNeitherRegisteredNorAskedAgain() async {
    let system = FakeSystem(.notDetermined, answers: false)
    let registration = PushRegistration(system: system, environment: .sandbox)

    await registration.checkedIn()
    await registration.checkedIn()
    await registration.launched()
    #expect(await system.prompts == 1)
    #expect(await system.registrations == 0)
}

@Test func launchingNeverAsksAndRegistersOnlyAnAllowedPhone() async {
    let fresh = FakeSystem(.notDetermined)
    await PushRegistration(system: fresh, environment: .sandbox).launched()
    #expect(await fresh.prompts == 0)
    #expect(await fresh.registrations == 0)

    let allowed = FakeSystem(.allowed)
    await PushRegistration(system: allowed, environment: .sandbox).launched()
    #expect(await allowed.registrations == 1)

    let denied = FakeSystem(.denied)
    await PushRegistration(system: denied, environment: .sandbox).launched()
    #expect(await denied.registrations == 0)
}

@Test func aTokenWaitsForSomeoneToSignIn() async throws {
    let registration = PushRegistration(system: FakeSystem(.allowed), environment: .production)
    let registry = FakeRegistry()

    try await registration.received(token)
    try await registration.signedIn(registry)
    #expect(await registry.calls == [.register(PushDevice(token: token, environment: .production))])
}

@Test func signingInWithNoTokenYetRegistersOnceTheTokenComes() async throws {
    let registration = PushRegistration(system: FakeSystem(.allowed), environment: .sandbox)
    let registry = FakeRegistry()

    try await registration.signedIn(registry)
    #expect(await registry.calls == [])
    try await registration.received(token)
    #expect(await registry.calls == [.register(phone)])

    // Every launch hands the token over again, and it is registered again.
    try await registration.received(token)
    #expect(await registry.calls == [.register(phone), .register(phone)])
}

@Test func aFailedRegistrationIsMadeAgainWithTheNextToken() async throws {
    let registration = PushRegistration(system: FakeSystem(.allowed), environment: .sandbox)
    let registry = FakeRegistry(failing: .unavailable)
    try await registration.signedIn(registry)

    await #expect(throws: NotificationsError.unavailable) { try await registration.received(token) }
    await registry.recover()
    try await registration.received(token)
    #expect(await registry.calls == [.register(phone), .register(phone)])
}

@Test func signingOutRemovesThePhoneAndStopsRegisteringIt() async throws {
    let registration = PushRegistration(system: FakeSystem(.allowed), environment: .sandbox)
    let registry = FakeRegistry()
    try await registration.signedIn(registry)
    try await registration.received(token)

    try await registration.signingOut()
    try await registration.received(token)
    #expect(await registry.calls == [.register(phone), .remove(token)])

    // Signing out again, with nobody signed in, sends nothing.
    try await registration.signingOut()
    #expect(await registry.calls == [.register(phone), .remove(token)])
}

@Test func theNextMemberToSignInGetsThePhone() async throws {
    let registration = PushRegistration(system: FakeSystem(.allowed), environment: .sandbox)
    let first = FakeRegistry()
    let second = FakeRegistry()
    try await registration.received(token)
    try await registration.signedIn(first)
    try await registration.signingOut()

    try await registration.signedIn(second)
    #expect(await first.calls == [.register(phone), .remove(token)])
    #expect(await second.calls == [.register(phone)])
}
