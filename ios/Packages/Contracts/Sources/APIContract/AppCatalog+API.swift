import Contracts
import Foundation

extension AppCatalog {
    /// What this build reads of `GET /public/catalog`. A section, list or field it doesn't know is
    /// passed over, and a section the server didn't send (one from before it was added), or a
    /// dice section with no lines, is `fallback`'s, so the app never loses its sports or its dice.
    public init(_ wire: Components.Schemas.Catalog, otherwise fallback: AppCatalog) {
        let dice = wire.disclaimerDice?.lines.map(CatalogNames.init) ?? []
        self.init(
            sports: wire.sports.map(SportCatalog.init) ?? fallback.sports,
            diceLines: dice.isEmpty ? fallback.diceLines : dice,
            switches: wire.switches.map(Self.switches) ?? fallback.switches,
            art: wire.art.map(ArtManifest.init) ?? fallback.art,
            scenes: wire.scenes.map(Self.scenes) ?? fallback.scenes)
    }

    /// The scenes, leaving out one whose id can't be one.
    static func scenes(_ wire: Components.Schemas.ScenesCatalog) -> [CatalogScene] {
        wire.scenes.compactMap { scene in
            SceneID(rawValue: scene.id).map {
                CatalogScene(
                    id: $0, names: CatalogNames(scene.names),
                    colors: CatalogScene.Colors(
                        signature: scene.colors.signature, onSignature: scene.colors.onSignature,
                        wash: scene.colors.wash, text: scene.colors.text, floor: scene.colors.floor))
            }
        }
    }

    /// Each switch by id; a mode this build doesn't know, or a schedule whose days can't be read,
    /// reads as off.
    static func switches(_ wire: Components.Schemas.SwitchesCatalog) -> [String: CatalogSwitch] {
        var switches: [String: CatalogSwitch] = [:]
        for each in wire.switches {
            switch each.mode {
            case "on": switches[each.id] = .alwaysOn
            case "schedule":
                if let window = each.window, let start = MonthDay(window.start), let end = MonthDay(window.end) {
                    switches[each.id] = .schedule(start: start, end: end)
                } else {
                    switches[each.id] = .alwaysOff
                }
            default: switches[each.id] = .alwaysOff
            }
        }
        return switches
    }
}

extension ArtManifest {
    /// The `art` section of `GET /public/catalog`.
    public init(_ wire: Components.Schemas.ArtCatalog) {
        self.init(
            generation: wire.generation, baseURL: URL(string: wire.baseUrl),
            files: wire.files.map {
                File(path: $0.path, sha256: $0.sha256, size: $0.size, rigVersion: $0.rigVersion)
            })
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
