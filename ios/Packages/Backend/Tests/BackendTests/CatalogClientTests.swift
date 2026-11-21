import AccountDomain
import Contracts
import Foundation
import Testing

@testable import Backend

// The catalog the API serves, read the way the app reads it: signed out, before sign-up, from
// the built API against local Supabase, with the copy kept in a file on disk.

@Test func theBuildShipsTheWholeSportsList() throws {
    let sports = CatalogClient.bundled.sports
    // However many the list holds today: every category has sports, and none is listed twice.
    let entries = sports.categories.flatMap(\.entries)
    #expect(!sports.categories.isEmpty && sports.categories.allSatisfy { !$0.entries.isEmpty })
    #expect(Set(entries.map(\.sport)).count == entries.count)
    #expect(
        sports.entry(for: "strength")?.names
            == .init(simplifiedChinese: "力量训练", english: "Strength", traditionalChinese: "重訓"))
    #expect(sports.entry(for: "roadCycling")?.icon == "figure.outdoor.cycle")
    #expect(sports.entry(for: "roadCycling")?.category == "cardio")
    #expect(sports.color(of: "ski") == "#2F86C4")
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
    let kept = CatalogClient(api: api, directory: directory).kept()
    #expect(kept.sports == CatalogClient.bundled.sports)
    #expect(kept.starterStock == CatalogClient.bundled.starterStock)
    // Asked again with the kept ETag: 304, still nothing new.
    #expect(await client.refresh() == nil)
}

@Test func aCatalogReadEarlierIsShownAtTheNextLaunch() throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: "wildcard-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    // As `refresh` keeps it, from a server that has since added a sport and a section.
    let kept = #"""
        {"version": 1, "etag": "\"abc\"", "catalog": {"version": 1, "stickers": {},
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
}

@Test func aCopyKeptBeforeCategoryColoursKeepsItsSports() throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: "wildcard-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    // Read from a server from before the catalog had category colours.
    let kept = #"""
        {"version": 1, "etag": "\"abc\"", "catalog": {"version": 1,
          "sports": {"categories": [{"id": "racket", "names": {"zhHans": "球拍", "en": "Racket", "zhHant": "球拍"},
            "sports": [{"id": "padel", "names": {"zhHans": "板式网球", "en": "Padel", "zhHant": "板式網球"},
              "icon": "figure.tennis", "offered": true}]}],
            "picks": {"signUpCommon": [], "checkInQuick": []}}}}
        """#
    try Data(kept.utf8).write(to: directory.appending(path: "catalog.json"))
    let stack = try LocalStack()
    let api = WildcardAPI(
        url: stack.apiURL,
        account: AccountSession(provider: stack.supabase.auth, store: MemorySessionStore(), now: { Date() }))
    let catalog = CatalogClient(api: api, directory: directory).kept()
    #expect(catalog.sports.entry(for: "padel")?.names.english == "Padel")
    // Kept from before category colours: its sports wear the gym's steel.
    #expect(catalog.sports.color(of: "padel") == nil)
}

@Test func theCopyPutIsKeptForTheExtensions() throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: "SharedCopy/\(UUID().uuidString)")
    let shared = SharedCopy(directory: directory)
    #expect(shared.read() == nil)
    let copy = AppCopy(entries: ["练了": AppCopy.Words(simplifiedChinese: "训练", english: "Trained")])
    shared.save(copy)
    #expect(SharedCopy(directory: directory).read() == copy)
}

@Test func aCatalogWhoseOnlyChangeIsItsCopyIsShownSoItsCopyIsKept() {
    let bundled = CatalogClient.bundled
    let copy = AppCopy(entries: ["练了": AppCopy.Words(simplifiedChinese: "训练")])
    let recopied = AppCatalog(
        sports: bundled.sports, starterStock: bundled.starterStock, art: bundled.art,
        scenes: bundled.scenes, switches: bundled.switches, copy: copy)
    #expect(CatalogClient.shows(recopied, differentlyFrom: bundled))
    #expect(!CatalogClient.shows(bundled, differentlyFrom: bundled))
}
