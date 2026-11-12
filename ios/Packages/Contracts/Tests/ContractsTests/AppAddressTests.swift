import Contracts
import Foundation
import Testing

/// The routes the server lets a button open, from `api/packages/app-routes/routes.json`.
private struct RoutesFile: Decodable {
    struct Route: Decodable {
        let pattern: String
        let sample: String
    }
    let version: Int
    let routes: [Route]
}

private func routes() throws -> [RoutesFile.Route] {
    let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().appending(path: "../../../../../api/packages/app-routes/routes.json")
    let file = try JSONDecoder().decode(RoutesFile.self, from: Data(contentsOf: url))
    #expect(file.version == 1)
    return file.routes
}

@Test func everyAddressTheServerListsOpensAPlace() throws {
    let routes = try routes()
    #expect(!routes.isEmpty)
    for route in routes {
        let place = try #require(AppDestination(address: route.sample), "\(route.pattern)")
        #expect(AppDestination(address: "wildcard://\(route.sample)") == place)
    }
}

@Test func readsTheLinkFormsAndRefusesOthers() throws {
    #expect(AppDestination(address: "WILDCARD://store/powder/") == .store("powder"))
    #expect(AppDestination(address: "wildcard://coach?from=card") == .coach)
    #expect(AppDestination(address: "me") == .profile)
    #expect(AppDestination(address: "recap/2026-11-02") == .recap(squad: nil, week: try LocalDay("2026-11-02")))
    #expect(AppDestination(address: "wildcard://check-in") == .checkIn)
    for unknown in ["", "coaches/xiaohun", "post/not-a-uuid", "recap/last-week", "store/powder/extra", "moon"] {
        #expect(AppDestination(address: unknown) == nil, "\(unknown)")
    }
}
