#if os(iOS)
import Contracts
import Foundation
import SwiftUI

extension Sport {
    /// String Catalog key for the name people see.
    public var nameKey: String { "sport.\(rawValue)" }

    public var name: Text { Text(LocalizedStringKey(nameKey), bundle: .module) }

    /// Sports whose name is too long for a poster row and have a short one in the catalog
    /// (`sportCard.<id>`); the rest use their name.
    static let shortOnCards: Set<Sport> = [
        .strength, .baseballSoftball, .reformerPilates, .mountainBiking, .roadCycling, .bikeCommute,
        .walkCommute, .strollerWalk, .tableTennis, .kickboxing, .martialArts,
    ]

    /// The name on a card or poster, where a long one would clip.
    public var cardName: Text {
        Self.shortOnCards.contains(self) ? Text(LocalizedStringKey("sportCard.\(rawValue)"), bundle: .module) : name
    }

    /// The localized name as a string, for search.
    public var localizedName: String { Bundle.module.localizedString(forKey: nameKey, value: nil, table: nil) }

    /// The SF Symbol drawn beside the name.
    public var symbol: String {
        switch self {
        case .run, .trailRun: "figure.run"
        case .walk, .walkCommute: "figure.walk"
        case .hike: "figure.hiking"
        case .strength, .kettlebell: "figure.strengthtraining.traditional"
        case .crossfit: "figure.cross.training"
        case .hyrox, .hiit: "figure.highintensity.intervaltraining"
        case .spin: "figure.indoor.cycle"
        case .elliptical: "figure.elliptical"
        case .rowing, .kayak: "figure.rower"
        case .jumpRope: "figure.jumprope"
        case .aerobics: "figure.step.training"
        case .yoga: "figure.yoga"
        case .matPilates, .reformerPilates: "figure.pilates"
        case .barre: "figure.barre"
        case .stretching: "figure.flexibility"
        case .swim: "figure.pool.swim"
        case .surf, .paddleboard: "figure.surfing"
        case .tennis: "figure.tennis"
        case .badminton: "figure.badminton"
        case .pickleball: "figure.pickleball"
        case .tableTennis: "figure.table.tennis"
        case .squash: "figure.squash"
        case .basketball: "figure.basketball"
        case .soccer: "figure.indoor.soccer"
        case .volleyball: "figure.volleyball"
        case .golf: "figure.golf"
        case .baseballSoftball: "figure.baseball"
        case .ultimate: "figure.disc.sports"
        case .roadCycling, .bikeCommute: "figure.outdoor.cycle"
        case .mountainBiking: "bicycle"
        case .climb: "figure.climbing"
        case .ski: "figure.skiing.downhill"
        case .snowboard: "figure.snowboarding"
        case .skate: "figure.skating"
        case .boxing: "figure.boxing"
        case .kickboxing: "figure.kickboxing"
        case .jiuJitsu: "figure.wrestling"
        case .martialArts: "figure.martial.arts"
        case .dance: "figure.dance"
        case .dogWalk: "dog.fill"
        case .deepClean: "bubbles.and.sparkles.fill"
        case .moving: "shippingbox.fill"
        case .strollerWalk: "stroller.fill"
        case .gardening: "leaf.fill"
        }
    }

    /// The sports a 练了 offers before the full list, most common first.
    public static let quickPicks: [Sport] = [.run, .strength, .yoga, .swim, .spin, .hike, .tennis]

    /// The sports whose name, as people see it or as its id, contains `query`; every sport in
    /// list order. An empty query matches none, so a search field shows its usual list instead.
    public static func matching(_ query: String) -> [Sport] {
        let needle = query.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return [] }
        return allCases.filter {
            $0.localizedName.localizedCaseInsensitiveContains(needle)
                || $0.rawValue.localizedCaseInsensitiveContains(needle)
        }
    }
}

extension SportCategory {
    public var nameKey: String { "sportCategory.\(rawValue)" }

    public var name: Text { Text(LocalizedStringKey(nameKey), bundle: .module) }
}

extension Activity {
    public var name: Text {
        switch self {
        case .sport(let sport): sport.name
        case .custom(let custom): Text(verbatim: custom.name)
        }
    }

    /// The name for a card or poster row: short where the full name is long.
    public var cardName: Text {
        switch self {
        case .sport(let sport): sport.cardName
        case .custom(let custom): Text(verbatim: custom.name)
        }
    }

    public var symbol: String {
        switch self {
        case .sport(let sport): sport.symbol
        case .custom: "figure.mixed.cardio"
        }
    }

    /// The name as plain text, for lines that join several.
    public var localizedName: String {
        switch self {
        case .sport(let sport): sport.localizedName
        case .custom(let custom): custom.name
        }
    }

    /// A stable key for identifiers and `ForEach`.
    public var key: String {
        switch self {
        case .sport(let sport): sport.rawValue
        case .custom(let custom): "custom.\(custom.name)"
        }
    }
}
#endif
