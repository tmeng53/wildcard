import Contracts

extension SportCatalog {
    /// The `sports` section of `GET /public/catalog`. A sport whose id can't be one is left out,
    /// so one bad row can't take the whole list away.
    public init(_ wire: Components.Schemas.SportsCatalog) {
        self.init(
            categories: wire.categories.map { category in
                Category(
                    id: category.id, names: Names(category.names),
                    entries: category.sports.compactMap { sport in
                        Sport(rawValue: sport.id).map {
                            Entry(
                                sport: $0, names: Names(sport.names), shortNames: sport.shortNames.map(Names.init),
                                icon: sport.icon, offered: sport.offered, category: category.id)
                        }
                    })
            },
            signUpCommon: wire.picks.signUpCommon.compactMap(Sport.init(rawValue:)),
            checkInQuick: wire.picks.checkInQuick.compactMap(Sport.init(rawValue:)))
    }
}

extension SportCatalog.Names {
    init(_ wire: Components.Schemas.CatalogNames) {
        self.init(simplifiedChinese: wire.zhHans, english: wire.en, traditionalChinese: wire.zhHant)
    }
}
