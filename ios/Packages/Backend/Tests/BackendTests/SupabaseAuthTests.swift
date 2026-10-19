import AccountDomain
import Backend
import Contracts
import Foundation
import Testing

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// Against local Supabase (`supabase start`), never a stand-in: `scripts/verify.sh backend`
// passes its URL and publishable key. Sign in with Apple itself needs a token only Apple can
// sign, so these sign in a test member with a password; the id_token grant is checked as far as
// a token we can make goes.

private struct SignedUp: Decodable {
    struct User: Decodable { let id: MemberID }
    let user: User
}

private struct LocalSupabase {
    let url: URL
    let publishableKey: String

    init() throws {
        let environment = ProcessInfo.processInfo.environment
        url = try #require(environment["SUPABASE_URL"].flatMap(URL.init(string:)), "run `supabase start`")
        publishableKey = try #require(environment["SUPABASE_PUBLISHABLE_KEY"])
    }

    var auth: SupabaseAuth { SupabaseAuth(url: url, publishableKey: publishableKey) }

    /// A new member with an email and password, signed up through Supabase Auth.
    func signUp() async throws -> (email: String, password: String, id: MemberID) {
        let email = "\(UUID().uuidString.lowercased())@example.com"
        let password = UUID().uuidString
        var request = URLRequest(url: url.appending(path: "auth/v1/signup"))
        request.httpMethod = "POST"
        request.setValue(publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["email": email, "password": password])
        let (data, _) = try await URLSession.shared.data(for: request)
        return (email, password, try JSONDecoder().decode(SignedUp.self, from: data).user.id)
    }
}

@Test func aMemberSignsInAndTheTokenLastsAnHour() async throws {
    let supabase = try LocalSupabase()
    let member = try await supabase.signUp()
    let session = try await supabase.auth.signIn(with: .testMember(email: member.email, password: member.password))
    #expect(session.member == member.id)
    #expect(abs(session.expiresAt.timeIntervalSinceNow - 3600) < 60)
}

@Test func aWrongPasswordIsRejected() async throws {
    let supabase = try LocalSupabase()
    let member = try await supabase.signUp()
    await #expect(throws: AccountError.credentialRejected) {
        try await supabase.auth.signIn(with: .testMember(email: member.email, password: "wrong"))
    }
}

@Test func anAppleTokenSupabaseCantVerifyIsRejected() async throws {
    let supabase = try LocalSupabase()
    await #expect(throws: AccountError.credentialRejected) {
        try await supabase.auth.signIn(with: .apple(identityToken: "not.a.token", nonce: "nonce"))
    }
}

@Test func refreshingIssuesANewSessionForTheSameMember() async throws {
    let supabase = try LocalSupabase()
    let member = try await supabase.signUp()
    let first = try await supabase.auth.signIn(with: .testMember(email: member.email, password: member.password))
    let renewed = try await supabase.auth.refresh(first.refreshToken)
    #expect(renewed.member == member.id)
    #expect(renewed.refreshToken != first.refreshToken)
}

@Test func afterSigningOutTheSessionCantBeRenewed() async throws {
    let supabase = try LocalSupabase()
    let member = try await supabase.signUp()
    let session = try await supabase.auth.signIn(with: .testMember(email: member.email, password: member.password))
    try await supabase.auth.signOut(session)
    await #expect(throws: AccountError.signedOut) { try await supabase.auth.refresh(session.refreshToken) }
    // Signing out a session that already ended is fine too.
    try await supabase.auth.signOut(session)
}

@Test func signingOutWithAnExpiredAccessTokenStillEndsTheSession() async throws {
    let supabase = try LocalSupabase()
    let member = try await supabase.signUp()
    let session = try await supabase.auth.signIn(with: .testMember(email: member.email, password: member.password))
    // Supabase refuses a stale access token at logout the way it refuses an expired one.
    let stale = Session(
        member: session.member, accessToken: "expired", refreshToken: session.refreshToken,
        expiresAt: session.expiresAt)
    try await supabase.auth.signOut(stale)
    await #expect(throws: AccountError.signedOut) { try await supabase.auth.refresh(session.refreshToken) }
}

@Test func anUnknownRefreshTokenSignsOut() async throws {
    let supabase = try LocalSupabase()
    await #expect(throws: AccountError.signedOut) { try await supabase.auth.refresh("unknown") }
}

@Test func anUnreachableServerIsUnavailable() async throws {
    // Nothing listens on port 9 (discard) on the test machine.
    let auth = SupabaseAuth(url: try #require(URL(string: "http://127.0.0.1:9")), publishableKey: "key")
    await #expect(throws: AccountError.unavailable) { try await auth.refresh("anything") }
}
