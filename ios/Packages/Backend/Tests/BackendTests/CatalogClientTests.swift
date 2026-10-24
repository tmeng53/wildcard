import AccountDomain
import Contracts
import Foundation
import Testing

@testable import Backend

// The catalog the API serves, read the way the app reads it: signed out, before sign-up, from
// the built API against local Supabase, with the copy kept in a file on disk.

@Test func theBuildShipsTheWholeSportsList() throws {
    let sports = CatalogClient.bundled.sports
    #expect(sports.categories.count == 12)
    #expect(sports.categories.flatMap(\.entries).count == 52)
    #expect(
        sports.entry(for: "strength")?.names
            == .init(simplifiedChinese: "力量训练", english: "Strength", traditionalChinese: "重訓"))
    #expect(sports.entry(for: "roadCycling")?.icon == "figure.outdoor.cycle")
    #expect(sports.entry(for: "roadCycling")?.category == "cycling")
    #expect(sports.signUpCommon == ["swim", "run", "strength", "tennis", "climb", "yoga"])
    #expect(sports.checkInQuick == ["run", "strength", "yoga", "swim", "spin", "hike", "tennis"])
}

@Test func theBuildShipsTheDiceLines() throws {
    let lines = CatalogClient.bundled.diceLines
    #expect(lines.count == 8)
    #expect(
        lines.first
            == .init(
                simplifiedChinese: "昨天的腿还没回来", english: "My legs haven't come back from yesterday",
                traditionalChinese: "昨天的腿還沒回來"))
}

/// A dice line goes into the field as is, so in every language it must fit a 请假条.
@Test func everyShippedDiceLineFitsADisclaimer() throws {
    for line in CatalogClient.bundled.diceLines.flatMap(\.all) {
        #expect(line.count <= Disclaimer.maxLength, "\(line) is \(line.count) characters")
    }
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

@Test func theCatalogIsReadSignedOutAndKeptOnTheDevice() async throws {
    let stack = try LocalStack()
    let signedOut = AccountSession(provider: stack.supabase.auth, store: MemorySessionStore(), now: { Date() })
    _ = try await signedOut.restore()
    let api = WildcardAPI(url: stack.apiURL, account: signedOut)
    let directory = FileManager.default.temporaryDirectory.appending(path: "wildcard-tests-\(UUID().uuidString)")
    let client = CatalogClient(api: api, directory: directory)

    // Before the first read: the catalog this build ships with.
    #expect(client.kept() == CatalogClient.bundled)
    // The API's catalog is the one the build ships with (its test keeps them the same), so the
    // first read changes nothing to show, and keeps it.
    #expect(await client.refresh() == nil)
    #expect(FileManager.default.fileExists(atPath: directory.appending(path: "catalog.json").path))
    #expect(CatalogClient(api: api, directory: directory).kept() == CatalogClient.bundled)
    // Asked again with the kept ETag: 304, still nothing new.
    #expect(await client.refresh() == nil)
}

@Test func aCatalogReadEarlierIsShownAtTheNextLaunch() throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: "wildcard-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    // As `refresh` keeps it, from a server that has since added a sport, a dice line and a section.
    let kept = #"""
        {"version": 1, "etag": "\"abc\"", "catalog": {"version": 1, "scenes": {},
          "sports": {"categories": [{"id": "racket", "names": {"zhHans": "球拍", "en": "Racket", "zhHant": "球拍"},
            "sports": [{"id": "padel", "names": {"zhHans": "板式网球", "en": "Padel", "zhHant": "板式網球"},
              "icon": "figure.tennis", "offered": true}]}],
            "picks": {"signUpCommon": [], "checkInQuick": ["padel"]}},
          "disclaimerDice": {"lines": [{"zhHans": "腿说休息", "en": "Legs said rest", "zhHant": "腿說休息"}]}}}
        """#
    try Data(kept.utf8).write(to: directory.appending(path: "catalog.json"))
    let stack = try LocalStack()
    let api = WildcardAPI(
        url: stack.apiURL,
        account: AccountSession(provider: stack.supabase.auth, store: MemorySessionStore(), now: { Date() }))
    let catalog = CatalogClient(api: api, directory: directory).kept()
    #expect(catalog.sports.entry(for: "padel")?.names.english == "Padel")
    #expect(catalog.sports.checkInQuick == ["padel"])
    #expect(catalog.diceLines.map(\.english) == ["Legs said rest"])
}

@Test func aCopyThisBuildCantReadGivesWayToTheShippedCatalog() throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: "wildcard-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    // Kept by an older build, from before the catalog had its dice lines.
    let kept = #"""
        {"version": 1, "etag": "\"abc\"", "catalog": {"version": 1,
          "sports": {"categories": [], "picks": {"signUpCommon": [], "checkInQuick": []}}}}
        """#
    try Data(kept.utf8).write(to: directory.appending(path: "catalog.json"))
    let stack = try LocalStack()
    let api = WildcardAPI(
        url: stack.apiURL,
        account: AccountSession(provider: stack.supabase.auth, store: MemorySessionStore(), now: { Date() }))
    #expect(CatalogClient(api: api, directory: directory).kept() == CatalogClient.bundled)
}
