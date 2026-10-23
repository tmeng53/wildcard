import AccountDomain
import Contracts
import Foundation
import Testing

@testable import Backend

// The catalog the API serves, read the way the app reads it: signed out, before sign-up, from
// the built API against local Supabase, with the copy kept in a file on disk.

@Test func theBuildShipsTheWholeSportsList() throws {
    let sports = CatalogClient.bundledSports
    #expect(sports.categories.count == 12)
    #expect(sports.categories.flatMap(\.entries).count == 52)
    #expect(
        sports.entry(for: "strength")?.names
            == .init(simplifiedChinese: "力量训练", english: "Strength training", traditionalChinese: "重訓"))
    #expect(sports.entry(for: "roadCycling")?.icon == "figure.outdoor.cycle")
    #expect(sports.entry(for: "roadCycling")?.category == "cycling")
    #expect(sports.signUpCommon == ["swim", "run", "strength", "tennis", "climb", "yoga"])
    #expect(sports.checkInQuick == ["run", "strength", "yoga", "swim", "spin", "hike", "tennis"])
}

/// SwiftLint's banned-terms rule can't read the shipped list, so this covers its names.
@Test func theShippedListAvoidsBannedTerms() throws {
    let url = try #require(Bundle.module.url(forResource: "catalog", withExtension: "json"))
    let text = try String(contentsOf: url, encoding: .utf8).lowercased()
    // Escaped, so the lint rule does not flag the test itself.
    for term in ["\u{5965}\u{8FD0}", "\u{6F}lympic"] {
        #expect(!text.contains(term), "the shipped sports list uses a banned term")
    }
}

@Test func theSportsListIsReadSignedOutAndKeptOnTheDevice() async throws {
    let stack = try LocalStack()
    let signedOut = AccountSession(provider: stack.supabase.auth, store: MemorySessionStore(), now: { Date() })
    _ = try await signedOut.restore()
    let api = WildcardAPI(url: stack.apiURL, account: signedOut)
    let directory = FileManager.default.temporaryDirectory.appending(path: "wildcard-tests-\(UUID().uuidString)")
    let client = CatalogClient(api: api, directory: directory)

    // Before the first read: the list this build ships with.
    #expect(client.keptSports() == CatalogClient.bundledSports)
    // The API's list is the one the build ships with (its test keeps them the same), so the
    // first read changes nothing to show, and keeps it.
    #expect(await client.refreshSports() == nil)
    #expect(FileManager.default.fileExists(atPath: directory.appending(path: "catalog.json").path))
    #expect(CatalogClient(api: api, directory: directory).keptSports() == CatalogClient.bundledSports)
    // Asked again with the kept ETag: 304, still nothing new.
    #expect(await client.refreshSports() == nil)
}
