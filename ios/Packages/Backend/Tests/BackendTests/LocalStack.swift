import AccountDomain
import Backend
import Contracts
import Foundation
import Testing

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// What the tests run against: local Supabase (`supabase start`) and, for the API client, the
// built API serving from it. `scripts/verify.sh backend` starts the API and passes all four.

private struct SignedUp: Decodable {
    struct User: Decodable { let id: MemberID }
    let user: User
}

struct LocalSupabase {
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

/// A member signed in the way the app signs in: `AccountSession` over `SupabaseAuth`, with the
/// API client asking the session for its token.
struct SignedInMember {
    let id: MemberID
    let account: AccountSession
    let api: WildcardAPI
}

struct LocalStack {
    let supabase: LocalSupabase
    let apiURL: URL
    let databaseURL: String

    init() throws {
        supabase = try LocalSupabase()
        let environment = ProcessInfo.processInfo.environment
        apiURL = try #require(
            environment["WILDCARD_API_URL"].flatMap(URL.init(string:)), "run through `scripts/verify.sh backend`")
        databaseURL = try #require(environment["DATABASE_URL"])
    }

    func signedInMember() async throws -> SignedInMember {
        let member = try await supabase.signUp()
        let account = AccountSession(provider: supabase.auth, store: MemorySessionStore(), now: { Date() })
        _ = try await account.restore()
        _ = try await account.signIn(with: .testMember(email: member.email, password: member.password))
        return SignedInMember(id: member.id, account: account, api: WildcardAPI(url: apiURL, account: account))
    }

    /// A squad of these members. Squads have no routes yet, so this writes the rows directly,
    /// as `scripts/api-journeys.sh` does.
    func squad(of members: SignedInMember...) throws -> SquadID {
        let squad = SquadID(UUID())
        var sql = "insert into public.squads (id, name) values ('\(squad)', 'backend tests');"
        for member in members {
            sql += "insert into public.squad_members (squad_id, member_id) values ('\(squad)', '\(member.id)');"
        }
        let psql = Process()
        psql.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        psql.arguments = ["psql", "-q", databaseURL, "-v", "ON_ERROR_STOP=1", "-c", sql]
        try psql.run()
        psql.waitUntilExit()
        try #require(psql.terminationStatus == 0, "psql couldn't write the squad")
        return squad
    }
}

/// The session kept in memory, where the app keeps it in the Keychain.
actor MemorySessionStore: SessionStore {
    private var session: Session?

    func load() async throws(AccountError) -> Session? { session }
    func save(_ session: Session) async throws(AccountError) { self.session = session }
    func clear() async throws(AccountError) { session = nil }
}
