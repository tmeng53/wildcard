import Contracts
import Testing

@Test func sportIdsAreCamelCaseLettersAndDigits() {
    #expect(Sport(rawValue: "run")?.rawValue == "run")
    #expect(Sport(rawValue: "trailRun")?.rawValue == "trailRun")
    #expect(Sport(rawValue: "k2") != nil)
    #expect(Sport(rawValue: "custom") == nil)
    #expect(Sport(rawValue: "Run") == nil)
    #expect(Sport(rawValue: "trail run") == nil)
    #expect(Sport(rawValue: "跑步") == nil)
    #expect(Sport(rawValue: "") == nil)
    #expect(Sport(rawValue: String(repeating: "a", count: 41)) == nil)
}

private func names(_ simplifiedChinese: String, _ english: String, _ traditionalChinese: String) -> SportCatalog.Names {
    SportCatalog.Names(simplifiedChinese: simplifiedChinese, english: english, traditionalChinese: traditionalChinese)
}

private let catalog = SportCatalog(
    categories: [
        SportCatalog.Category(
            id: "runWalk", names: names("跑走", "Run and walk", "跑步健走"),
            entries: [
                SportCatalog.Entry(
                    sport: "run", names: names("跑步", "Run", "跑步"), icon: "figure.run", offered: true,
                    category: "runWalk"),
                SportCatalog.Entry(
                    sport: "racewalk", names: names("竞走", "Racewalk", "競走"), icon: "figure.walk", offered: false,
                    category: "runWalk"),
            ]),
        SportCatalog.Category(
            id: "racket", names: names("球拍", "Racket", "球拍"),
            entries: [
                SportCatalog.Entry(
                    sport: "tableTennis", names: names("乒乓球", "Table tennis", "桌球"), icon: "figure.table.tennis",
                    offered: true, category: "racket")
            ]),
    ],
    signUpCommon: ["run", "racewalk", "quidditch"], checkInQuick: [])

@Test func findsEachSportsEntryAndOffersOnlyThoseStillOffered() {
    #expect(catalog.entry(for: "racewalk")?.names.english == "Racewalk")
    #expect(catalog.entry(for: "quidditch") == nil)
    #expect(catalog.offered == ["run", "tableTennis"])
    #expect(catalog.categories[0].offered == ["run"])
    // A short list keeps only sports the pickers offer.
    #expect(catalog.signUpCommon == ["run"])
}

@Test func searchesEveryLanguageAndTheId() {
    #expect(catalog.matching("乒乓") == ["tableTennis"])
    #expect(catalog.matching("桌球") == ["tableTennis"])
    #expect(catalog.matching("TABLE") == ["tableTennis"])
    #expect(catalog.matching("跑") == ["run"])
    // Not a sport the pickers offer any more.
    #expect(catalog.matching("竞走") == [])
    #expect(catalog.matching("  ") == [])
}
