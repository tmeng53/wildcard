import Foundation
import HTTPTypes
import OpenAPIRuntime
import Testing

@testable import Backend

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// A request whose kept-alive connection the network had closed fails at once; a read goes out
// once more on a fresh one, so the screen never shows 网络开小差了 for it.

/// Counts the sends and fails the first ones with `failures`.
private actor Network {
    private(set) var sends = 0
    private var failures: [URLError.Code]

    init(failing failures: [URLError.Code]) { self.failures = failures }

    func send() throws -> (HTTPResponse, HTTPBody?) {
        sends += 1
        if !failures.isEmpty { throw URLError(failures.removeFirst()) }
        return (HTTPResponse(status: .ok), nil)
    }
}

private func send(_ method: HTTPRequest.Method, over network: Network) async throws -> HTTPResponse {
    let request = HTTPRequest(method: method, scheme: "https", authority: "api.test", path: "/me")
    let (response, _) = try await ResendDroppedRead().intercept(
        request, body: nil, baseURL: URL(fileURLWithPath: "/"), operationID: "getMe"
    ) { _, _, _ in try await network.send() }
    return response
}

@Test func aReadOnADroppedConnectionGoesOutOnceMore() async throws {
    let network = Network(failing: [.networkConnectionLost])
    #expect(try await send(.get, over: network).status == .ok)
    #expect(await network.sends == 2)
}

@Test func aReadIsSentAgainOnlyOnce() async {
    let network = Network(failing: [.networkConnectionLost, .networkConnectionLost])
    await #expect(throws: URLError.self) { try await send(.get, over: network) }
    #expect(await network.sends == 2)
}

@Test func aWriteOrAnotherFailureIsNotSentAgain() async {
    let write = Network(failing: [.networkConnectionLost])
    await #expect(throws: URLError.self) { try await send(.put, over: write) }
    #expect(await write.sends == 1)

    let offline = Network(failing: [.notConnectedToInternet])
    await #expect(throws: URLError.self) { try await send(.get, over: offline) }
    #expect(await offline.sends == 1)
}
