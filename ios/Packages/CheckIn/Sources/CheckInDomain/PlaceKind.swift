import Contracts

/// What kind of place a tagged one is, as Apple Maps files it, and the SF Symbol that shows it
/// (Tracy, 2026-11-12: the type's icon, never a brand's logo). Maps' categories come as
/// `MKPOICategoryFitnessCenter`; a place keeps the short `fitnessCenter`.
public enum PlaceKind: Equatable, Sendable {
    case gym
    case food
    case cafe
    case market
    case shop
    case park
    case beach
    case sport(String)
    case other

    /// The kind of a tagged place, from its category; `.other` when Maps gave none or one this
    /// build doesn't know.
    public init(category: String?) {
        switch category {
        case "fitnessCenter": self = .gym
        case "restaurant", "bakery", "brewery", "winery", "distillery": self = .food
        case "cafe": self = .cafe
        case "foodMarket": self = .market
        case "store": self = .shop
        case "park", "nationalPark", "campground", "hiking": self = .park
        case "beach", "surfing": self = .beach
        case "stadium", "swimming", "tennis", "golf", "miniGolf", "soccer", "basketball", "baseball", "volleyball",
            "rockClimbing", "skiing", "skating", "skatePark", "bowling", "kayaking":
            self = .sport(category ?? "")
        default: self = .other
        }
    }

    /// The SF Symbol drawn for it, on the map's ticket, its row and the post's tag.
    public var symbol: String {
        switch self {
        case .gym: "dumbbell.fill"
        case .food: "fork.knife"
        case .cafe: "cup.and.saucer.fill"
        case .market: "cart.fill"
        case .shop: "bag.fill"
        case .park: "tree.fill"
        case .beach: "beach.umbrella.fill"
        case .sport(let category): Self.sportSymbols[category] ?? "sportscourt.fill"
        case .other: "mappin"
        }
    }

    private static let sportSymbols = [
        "swimming": "figure.pool.swim", "tennis": "figure.tennis", "golf": "figure.golf",
        "miniGolf": "figure.golf", "soccer": "figure.soccer", "basketball": "figure.basketball",
        "baseball": "figure.baseball", "volleyball": "figure.volleyball", "rockClimbing": "figure.climbing",
        "skiing": "figure.skiing.downhill", "skating": "figure.skating", "skatePark": "figure.skateboarding",
        "bowling": "figure.bowling", "kayaking": "figure.outdoor.rowing",
    ]

    /// A category as a place keeps it: Maps' `MKPOICategoryFitnessCenter` becomes `fitnessCenter`.
    public static func category(fromMaps raw: String) -> String {
        let prefix = "MKPOICategory"
        guard raw.hasPrefix(prefix), raw.count > prefix.count else { return raw }
        let rest = raw.dropFirst(prefix.count)
        return rest.prefix(1).lowercased() + rest.dropFirst()
    }
}

extension Place {
    public var kind: PlaceKind { PlaceKind(category: category) }
}
