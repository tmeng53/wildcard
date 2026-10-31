import Contracts

extension AppCatalog {
    /// What this build reads of `GET /public/catalog`. A section, list or field it doesn't know is
    /// passed over, and a section the server didn't send (one from before it was added), or a
    /// dice section with no lines, is `fallback`'s, so the app never loses its sports or its dice.
    public init(_ wire: Components.Schemas.Catalog, otherwise fallback: AppCatalog) {
        let dice = wire.disclaimerDice?.lines.map(CatalogNames.init) ?? []
        self.init(
            sports: wire.sports.map(SportCatalog.init) ?? fallback.sports,
            diceLines: dice.isEmpty ? fallback.diceLines : dice)
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
