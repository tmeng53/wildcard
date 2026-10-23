#if canImport(Security) && canImport(CryptoKit)
import AccountDomain
import Contracts
import Foundation
import Testing

@testable import AccountUI

@Test func theAppleRequestCarriesTheNoncesSHA256() {
    // printf wildcard | shasum -a 256
    #expect(
        AppleNonce(raw: "wildcard").hashed == "ed3c7bc96fed7441c591e20c2ceebaf1b7166df1d707c975d177246ad791bf9c")
}

@Test func everyNonceIsNew() {
    let nonces = Set((0..<100).map { _ in AppleNonce.random().raw })
    #expect(nonces.count == 100)
    #expect(nonces.allSatisfy { $0.count == 64 })
}

@Test func theKeychainKeepsReplacesAndForgetsTheSession() async throws {
    let store = KeychainSessionStore(service: "com.wildcardsquad.wildcard.tests.\(UUID())")
    let member = MemberID(UUID())
    let first = Session(
        member: member, accessToken: "a1", refreshToken: "r1", expiresAt: Date(timeIntervalSince1970: 1_792_371_600))
    let second = Session(
        member: member, accessToken: "a2", refreshToken: "r2", expiresAt: Date(timeIntervalSince1970: 1_792_375_200))

    #expect(try await store.load() == nil)
    try await store.save(first)
    #expect(try await store.load() == first)
    try await store.save(second)
    #expect(try await store.load() == second)
    try await store.clear()
    #expect(try await store.load() == nil)
    try await store.clear()
}
#endif
