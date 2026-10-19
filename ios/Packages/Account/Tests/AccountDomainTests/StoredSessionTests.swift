import AccountDomain
import Foundation
import Testing

@Test func aSessionIsStoredAsVersionedJSON() throws {
    let json = try #require(String(bytes: try StoredSession.encode(session("stored")), encoding: .utf8))
    #expect(
        json == """
            {"accessToken":"access-stored","expiresAt":1792371600,\
            "member":"01020304-0506-0708-090a-0b0c0d0e0f10","refreshToken":"refresh-stored","version":1}
            """)
    #expect(try StoredSession.decode(Data(json.utf8)) == session("stored"))
}

@Test func anotherVersionIsRefused() {
    let json = """
        {"accessToken":"a","expiresAt":1,"member":"01020304-0506-0708-090a-0b0c0d0e0f10","refreshToken":"r","version":2}
        """
    #expect(throws: AccountError.unsupportedVersion(2)) { try StoredSession.decode(Data(json.utf8)) }
}

@Test func jsonWithoutAVersionIsRefused() {
    #expect(throws: AccountError.storeCorrupted) { try StoredSession.decode(Data("{}".utf8)) }
}
