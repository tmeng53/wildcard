import APIContract
import AccountDomain
import Foundation
import HTTPTypes
import OpenAPIRuntime

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Sends the member's access token, and once more with a renewed one when the API refuses it:
/// the API can refuse a token before its expiry (signed out elsewhere, a rotated key). When it
/// refuses the renewed one too, `refused` ends the session, so the account and the calls agree
/// the member is signed out.
struct BearerToken: ClientMiddleware {
    let accessToken: WildcardAPI.AccessToken
    /// Called with the renewed token the API refused too.
    let refused: @Sendable (_ token: String) async -> Void

    static let publicOperations: Set<String> = [Operations.GetCatalog.id]

    func intercept(
        _ request: HTTPRequest, body: HTTPBody?, baseURL: URL, operationID: String,
        next: @Sendable (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
    ) async throws -> (HTTPResponse, HTTPBody?) {
        // Routes anyone may call send no token, so they work signed out, as sign-up's are.
        if Self.publicOperations.contains(operationID) { return try await next(request, body, baseURL) }
        // Read once, so the retry can send it again: request bodies are a check-in or a profile.
        var sent: Data?
        if let body { sent = try await Data(collecting: body, upTo: 1024 * 1024) }
        func send(_ token: String) async throws -> (HTTPResponse, HTTPBody?) {
            var request = request
            request.headerFields[.authorization] = "Bearer \(token)"
            return try await next(request, sent.map(HTTPBody.init), baseURL)
        }
        let token = try await current(rejected: nil)
        let answer = try await send(token)
        guard answer.0.status == .unauthorized else { return answer }
        let renewed = try await current(rejected: token)
        let retried = try await send(renewed)
        if retried.0.status == .unauthorized { await refused(renewed) }
        return retried
    }

    private func current(rejected: String?) async throws(APIError) -> String {
        do {
            return try await accessToken(rejected)
        } catch {
            throw .account(error)
        }
    }
}

/// Sends a read once more when the connection it went out on had already dropped. iOS keeps
/// connections open between requests, and one the network closed meanwhile (the app was in the
/// background, the phone moved from Wi-Fi to cellular) fails the next request at once with
/// `networkConnectionLost`; a fresh connection then works. Only reads are sent again, since
/// they change nothing; a write that failed this way is the caller's to retry.
struct ResendDroppedRead: ClientMiddleware {
    func intercept(
        _ request: HTTPRequest, body: HTTPBody?, baseURL: URL, operationID: String,
        next: @Sendable (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
    ) async throws -> (HTTPResponse, HTTPBody?) {
        do {
            return try await next(request, body, baseURL)
        } catch {
            guard request.method == .get, Self.isDropped(error) else { throw error }
            return try await next(request, body, baseURL)
        }
    }

    /// Whether the call failed because its connection was already gone.
    static func isDropped(_ error: any Error) -> Bool {
        let cause = (error as? ClientError)?.underlyingError ?? error
        return (cause as? URLError)?.code == .networkConnectionLost
    }
}

/// The language the app speaks now, as a tag (`zh-Hans`, `en`).
public typealias LanguageTag = @Sendable () -> String

/// Asks for the API's words in the language the app speaks now, which a pick in the app can
/// change after the system's own header was set.
struct AcceptLanguage: ClientMiddleware {
    let language: LanguageTag

    func intercept(
        _ request: HTTPRequest, body: HTTPBody?, baseURL: URL, operationID: String,
        next: @Sendable (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
    ) async throws -> (HTTPResponse, HTTPBody?) {
        var request = request
        request.headerFields[.acceptLanguage] = language()
        return try await next(request, body, baseURL)
    }
}

/// Turns the API's failures, RFC 9457 problems with a stable `reason`, into `APIError`s, so the
/// calls only read the answers they asked for.
struct Problems: ClientMiddleware {
    func intercept(
        _ request: HTTPRequest, body: HTTPBody?, baseURL: URL, operationID: String,
        next: @Sendable (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
    ) async throws -> (HTTPResponse, HTTPBody?) {
        let (response, responseBody) = try await next(request, body, baseURL)
        switch response.status.kind {
        case .successful: return (response, responseBody)
        case .serverError: throw APIError.unavailable
        default: break
        }
        // After a renewed token was refused too, the session is over.
        if response.status == .unauthorized { throw APIError.account(.signedOut) }
        guard
            let responseBody, let data = try? await Data(collecting: responseBody, upTo: 64 * 1024),
            let problem = try? JSONDecoder().decode(Components.Schemas.Problem.self, from: data)
        else { throw APIError.unreadableResponse }
        throw APIError.refused(Refusal(reason: problem.reason))
    }
}
