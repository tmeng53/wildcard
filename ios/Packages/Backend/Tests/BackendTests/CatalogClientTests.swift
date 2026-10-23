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

@Test func aListReadEarlierIsShownAtTheNextLaunch() throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: "wildcard-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    // As `refreshSports` keeps it, from a server that has since added a sport and a section.
    let kept = #"""
        {"version": 1, "etag": "\"abc\"", "catalog": {"version": 1, "scenes": {},
          "sports": {"categories": [{"id": "racket", "names": {"zhHans": "球拍", "en": "Racket", "zhHant": "球拍"},
            "sports": [{"id": "padel", "names": {"zhHans": "板式网球", "en": "Padel", "zhHant": "板式網球"},
              "icon": "figure.tennis", "offered": true}]}],
            "picks": {"signUpCommon": [], "signUpMore": [], "checkInQuick": ["padel"]}}}}
        """#
    try Data(kept.utf8).write(to: directory.appending(path: "catalog.json"))
    let stack = try LocalStack()
    let api = WildcardAPI(
        url: stack.apiURL,
        account: AccountSession(provider: stack.supabase.auth, store: MemorySessionStore(), now: { Date() }))
    let sports = CatalogClient(api: api, directory: directory).keptSports()
    #expect(sports.entry(for: "padel")?.names.english == "Padel")
    #expect(sports.checkInQuick == ["padel"])
}
