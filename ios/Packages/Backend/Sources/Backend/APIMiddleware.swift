import APIContract
import AccountDomain
import Foundation
import HTTPTypes
import OpenAPIRuntime

/// Sends the member's access token, and once more with a renewed one when the API refuses it:
/// the API can refuse a token before its expiry (signed out elsewhere, a rotated key).
struct BearerToken: ClientMiddleware {
    let accessToken: WildcardAPI.AccessToken

    func intercept(
        _ request: HTTPRequest, body: HTTPBody?, baseURL: URL, operationID: String,
        next: @Sendable (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
    ) async throws -> (HTTPResponse, HTTPBody?) {
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
        return try await send(try await current(rejected: token))
    }

    private func current(rejected: String?) async throws(APIError) -> String {
        do {
            return try await accessToken(rejected)
        } catch {
            throw .account(error)
        }
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
