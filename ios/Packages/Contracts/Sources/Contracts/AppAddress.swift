import Foundation

/// Every place a link may open has an address (Tracy, 2026-11-12: where a button goes is data, so
/// it changes without a release): a path such as `store/powder` or `post/<id>`, alone or after
/// `wildcard://`. A notice's button, a coach card's button, a push or a link from anywhere names a
/// place by its address, and `MainTabs.open(_:)` opens it. The server keeps the same list
/// (`api/packages/app-routes`); a test checks this build reads every address it lists.
extension AppDestination {
    /// The scheme of a link into the app.
    public static let scheme = "wildcard"

    /// The place at `address`, with or without `wildcard://`; nil for one this build doesn't know,
    /// which shows no button and opens nothing.
    public init?(address: String) {
        var path = Substring(address)
        let prefix = "\(Self.scheme)://"
        if path.lowercased().hasPrefix(prefix) { path = path.dropFirst(prefix.count) }
        path = path.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
        while path.hasSuffix("/") { path = path.dropLast() }
        let parts = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        switch parts.count {
        case 1:
            guard let place = Self.places[parts[0]] else { return nil }
            self = place
        case 2:
            guard let place = Self.place(parts[0], parts[1]) else { return nil }
            self = place
        default:
            return nil
        }
    }

    /// Its address, without the scheme; nil for a place only a notice opens (a pat, a note, a
    /// letter), which has none.
    public var address: String? {
        if let word = Self.places.first(where: { $0.value == self })?.key { return word }
        switch self {
        case .store(let store): return "store/\(store)"
        case .wardrobe(let piece?): return "wardrobe/\(piece)"
        case .post(let id): return "post/\(id)"
        case .recap(nil, let week): return "recap/\(week)"
        default: return nil
        }
    }

    /// Its link, `wildcard://<address>`; nil without an address.
    public var link: URL? { address.flatMap { URL(string: "\(Self.scheme)://\($0)") } }

    /// The places named by a word alone.
    private static let places: [String: AppDestination] = [
        "stores": .stores, "notices": .notices, "schedule": .schedule, "squad": .squad, "coaches": .coaches,
        "feed": .feed, "today": .today, "me": .profile, "wardrobe": .wardrobe(piece: nil), "badges": .badges,
        "coach": .coach, "check-in": .checkIn, "settings": .settings, "feedback": .feedback,
        "my-posts": .myPosts,
    ]

    /// A place named by a word and an id.
    private static func place(_ word: String, _ id: String) -> AppDestination? {
        guard !id.isEmpty else { return nil }
        switch word {
        case "store": return .store(id)
        case "wardrobe": return .wardrobe(piece: id)
        case "post": return UUID(uuidString: id).map { .post(CheckInID($0)) }
        case "recap": return (try? LocalDay(id)).map { .recap(squad: nil, week: $0) }
        default: return nil
        }
    }
}
