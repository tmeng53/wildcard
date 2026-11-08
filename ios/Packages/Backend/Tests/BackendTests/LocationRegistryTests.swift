import Foundation
import LocationDomain
import Testing

@testable import Backend

// The member's place against the built API, as `LocationSharing` sends it once location is
// allowed. What the server keeps (only the cell, the latest) is the weather module's own tests'.

@Test func aSignedInMemberSavesTheirPlaceAndForgetsIt() async throws {
    let stack = try LocalStack()
    let member = try await stack.signedInMember()
    let registry = APILocationRegistry(api: member.api)
    try await registry.save(Coordinates(latitude: 40.7, longitude: -74))
    // Every move sends again, and forgetting twice is fine.
    try await registry.save(Coordinates(latitude: 25, longitude: 121.6))
    try await registry.forget()
    try await registry.forget()
}

@Test func aSessionThatIsOverIsSignedOutForLocation() async throws {
    let stack = try LocalStack()
    let member = try await stack.signedInMember()
    try await member.account.signOut()
    await #expect(throws: LocationError.signedOut) {
        try await APILocationRegistry(api: member.api).save(Coordinates(latitude: 40.7, longitude: -74))
    }
}
