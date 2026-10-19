import AccountDomain
import Contracts
import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Supabase Auth's token API, as an `AuthProvider`. A Sign in with Apple identity token becomes
/// a session with the `id_token` grant; Supabase checks it against Apple's keys and the nonce,
/// and creates the member on their first sign-in.
public struct SupabaseAuth: AuthProvider {
    private let url: URL
    private let publishableKey: String
    private let http: URLSession

    /// - Parameters:
    ///   - url: the project's URL, such as `https://<ref>.supabase.co`.
    ///   - publishableKey: the project's publishable key, which only identifies the project. It
    ///     ships in the app and grants nothing on its own: the database is closed to it.
    public init(url: URL, publishableKey: String, http: URLSession = .shared) {
        self.url = url
        self.publishableKey = publishableKey
        self.http = http
    }

    public func signIn(with credential: Credential) async throws(AccountError) -> Session {
        let body: [String: String]
        let grant: String
        switch credential {
        case .apple(let identityToken, let nonce):
            grant = "id_token"
            body = ["provider": "apple", "id_token": identityToken, "nonce": nonce]
        #if DEBUG
        case .testMember(let email, let password):
            grant = "password"
            body = ["email": email, "password": password]
        #endif
        }
        switch try await token(grant: grant, body: body) {
        case .issued(let session): return session
        case .refused: throw .credentialRejected
        }
    }

    public func refresh(_ refreshToken: String) async throws(AccountError) -> Session {
        switch try await token(grant: "refresh_token", body: ["refresh_token": refreshToken]) {
        case .issued(let session): return session
        // Used up, revoked or expired: whichever, this session is over.
        case .refused: throw .signedOut
        }
    }

    public func signOut(_ session: Session) async throws(AccountError) {
        let status = try await logout(accessToken: session.accessToken)
        if (200..<300).contains(status) { return }
        guard status == 401 || status == 403 else { throw .unavailable }
        // Logout needs a live access token, and this one has expired (an idle app) or ended. The
        // refresh token tells which: if it's refused too, the session is already over; otherwise
        // sign out with the fresh token, so the session doesn't stay usable on the server.
        switch try await token(grant: "refresh_token", body: ["refresh_token": session.refreshToken]) {
        case .refused: return
        case .issued(let renewed):
            guard (200..<300).contains(try await logout(accessToken: renewed.accessToken)) else { throw .unavailable }
        }
    }

    // MARK: - Private

    private enum Outcome {
        case issued(Session)
        case refused
    }

    /// The fields of Supabase Auth's token response this adapter reads.
    private struct TokenResponse: Decodable {
        let accessToken: String
        let refreshToken: String
        /// Seconds since 1970.
        let expiresAt: Double
        let user: AuthUser
    }

    private struct AuthUser: Decodable {
        let id: MemberID
    }

    /// Ends this device's session (`local` scope; the member stays signed in elsewhere) and
    /// returns the HTTP status.
    private func logout(accessToken: String) async throws(AccountError) -> Int {
        var request = request(path: "logout", query: [URLQueryItem(name: "scope", value: "local")])
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        return try await send(request).1
    }

    private func token(grant: String, body: [String: String]) async throws(AccountError) -> Outcome {
        var request = request(path: "token", query: [URLQueryItem(name: "grant_type", value: grant)])
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        do {
            request.httpBody = try JSONEncoder().encode(body)
        } catch {
            throw .unavailable
        }
        let (data, status) = try await send(request)
        switch status {
        case 200..<300:
            do {
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                let response = try decoder.decode(TokenResponse.self, from: data)
                return .issued(
                    Session(
                        member: response.user.id, accessToken: response.accessToken,
                        refreshToken: response.refreshToken, expiresAt: Date(timeIntervalSince1970: response.expiresAt))
                )
            } catch {
                throw .unavailable
            }
        // Too many attempts is a reason to wait, not a verdict on the credential.
        case 429: throw .unavailable
        case 400..<500: return .refused
        default: throw .unavailable
        }
    }

    private func request(path: String, query: [URLQueryItem]) -> URLRequest {
        let endpoint = url.appending(path: "auth/v1/\(path)").appending(queryItems: query)
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue(publishableKey, forHTTPHeaderField: "apikey")
        return request
    }

    private func send(_ request: URLRequest) async throws(AccountError) -> (Data, Int) {
        do {
            let (data, response) = try await http.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw AccountError.unavailable }
            return (data, http.statusCode)
        } catch {
            throw .unavailable
        }
    }
}
