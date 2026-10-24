import Contracts

extension AppCatalog {
    /// What this build reads of `GET /public/catalog`. A section, list or field it doesn't know is
    /// passed over, and a dice line without its words in a language is still shown in the others.
    public init(_ wire: Components.Schemas.Catalog) {
        self.init(sports: SportCatalog(wire.sports), diceLines: wire.disclaimerDice.lines.map(CatalogNames.init))
    }
}

extension SportCatalog {
    /// The `sports` section of `GET /public/catalog`. A sport whose id can't be one is left out,
    /// so one bad row can't take the whole list away.
    public init(_ wire: Components.Schemas.SportsCatalog) {
        self.init(
            categories: wire.categories.map { category in
                Category(
                    id: category.id, names: CatalogNames(category.names),
                    entries: category.sports.compactMap { sport in
                        Sport(rawValue: sport.id).map {
                            Entry(
                                sport: $0, names: CatalogNames(sport.names),
                                shortNames: sport.shortNames.map(CatalogNames.init),
                                icon: sport.icon, offered: sport.offered, category: category.id)
                        }
                    })
            },
            signUpCommon: wire.picks.signUpCommon.compactMap(Sport.init(rawValue:)),
            checkInQuick: wire.picks.checkInQuick.compactMap(Sport.init(rawValue:)))
    }
}

extension CatalogNames {
    init(_ wire: Components.Schemas.CatalogNames) {
        self.init(simplifiedChinese: wire.zhHans, english: wire.en, traditionalChinese: wire.zhHant)
    }
}
