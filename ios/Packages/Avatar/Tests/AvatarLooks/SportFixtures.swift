import Contracts

extension Looks {
    /// Sports in the categories the API's list puts them in, for kit lookups: the kit file
    /// names categories, and the list says which category a sport is in.
    public static let sports: SportCatalog = {
        let categories: [(String, [Sport])] = [
            ("runWalk", ["run", "walk", "hike"]), ("strength", ["strength"]), ("cardio", ["spin"]),
            ("mindBody", ["yoga", "matPilates"]), ("water", ["swim", "surf"]), ("racket", ["tennis", "badminton"]),
            ("ball", ["basketball"]), ("outdoorWinter", ["climb", "ski"]), ("combat", ["boxing"]),
            ("dance", ["dance"]), ("everyday", ["dogWalk"]),
        ]
        let names = CatalogNames(simplifiedChinese: "", english: "", traditionalChinese: "")
        return SportCatalog(
            categories: categories.map { id, sports in
                SportCatalog.Category(
                    id: id, names: names,
                    entries: sports.map {
                        SportCatalog.Entry(sport: $0, names: names, icon: "figure.run", offered: true, category: id)
                    })
            }, signUpCommon: [], checkInQuick: [])
    }()
}
