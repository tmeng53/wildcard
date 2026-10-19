import AccountDomain
import Backend
import Contracts
import Foundation
import Testing

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// What the tests run against: local Supabase (`supabase start`) and, for the API client, the
// built API serving from it. `scripts/verify.sh backend` starts the API and passes all three.

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

    init() throws {
        supabase = try LocalSupabase()
        let environment = ProcessInfo.processInfo.environment
        apiURL = try #require(
            environment["WILDCARD_API_URL"].flatMap(URL.init(string:)), "run through `scripts/verify.sh backend`")
    }

    func signedInMember() async throws -> SignedInMember {
        let member = try await supabase.signUp()
        let account = AccountSession(provider: supabase.auth, store: MemorySessionStore(), now: { Date() })
        _ = try await account.restore()
        _ = try await account.signIn(with: .testMember(email: member.email, password: member.password))
        return SignedInMember(id: member.id, account: account, api: WildcardAPI(url: apiURL, account: account))
    }

    /// A squad of these members: the first creates it through the API and the rest accept its
    /// invite, as `scripts/api-journeys.sh` does. The client has no squad calls yet.
    func squad(of creator: SignedInMember, _ others: SignedInMember...) async throws -> SquadID {
        let squad = SquadID(UUID())
        let created: CreatedSquad = try await send(
            "PUT", "squads/\(squad)", as: creator, body: #"{"version":1,"name":"backend tests"}"#)
        for member in others {
            let _: JoinedSquad = try await send(
                "POST", "squad-invites/\(created.inviteCode)/accept", as: member, body: nil)
        }
        return squad
    }

    private func send<Answer: Decodable>(
        _ method: String, _ path: String, as member: SignedInMember, body: String?
    ) async throws -> Answer {
        var request = URLRequest(url: apiURL.appending(path: path))
        request.httpMethod = method
        request.setValue("Bearer \(try await member.account.accessToken())", forHTTPHeaderField: "Authorization")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = Data(body.utf8)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        try #require(
            (response as? HTTPURLResponse)?.statusCode == 201,
            "\(method) \(path): \(String(bytes: data, encoding: .utf8) ?? "")")
        return try JSONDecoder().decode(Answer.self, from: data)
    }
}

private struct CreatedSquad: Decodable { let inviteCode: String }
private struct JoinedSquad: Decodable {}

/// The session kept in memory, where the app keeps it in the Keychain.
actor MemorySessionStore: SessionStore {
    private var session: Session?

    func load() async throws(AccountError) -> Session? { session }
    func save(_ session: Session) async throws(AccountError) { self.session = session }
    func clear() async throws(AccountError) { session = nil }
}
