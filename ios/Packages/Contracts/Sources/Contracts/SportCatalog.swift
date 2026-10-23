import Foundation

/// The sports list every picker shows: categories in order, each sport's names, icon and
/// category, and the short lists some screens show first. Data the API serves, so a new sport,
/// name, icon or order needs no app release; the app keeps the last list it read.
public struct SportCatalog: Hashable, Sendable {
    /// A name in each of the app's languages.
    public struct Names: Hashable, Sendable {
        public let simplifiedChinese: String
        public let english: String
        public let traditionalChinese: String

        public init(simplifiedChinese: String, english: String, traditionalChinese: String) {
            (self.simplifiedChinese, self.english, self.traditionalChinese) = (
                simplifiedChinese, english, traditionalChinese
            )
        }

        /// Each language's name, for search.
        public var all: [String] { [simplifiedChinese, english, traditionalChinese] }
    }

    public struct Entry: Hashable, Sendable {
        public let sport: Sport
        public let names: Names
        /// An SF Symbol name.
        public let icon: String
        /// False for a sport the pickers no longer offer; check-ins that name it still show it.
        public let offered: Bool
        /// The id of the category it is in.
        public let category: String

        public init(sport: Sport, names: Names, icon: String, offered: Bool, category: String) {
            (self.sport, self.names, self.icon, self.offered, self.category) = (sport, names, icon, offered, category)
        }
    }

    /// One of the picker's tabs.
    public struct Category: Hashable, Sendable, Identifiable {
        public let id: String
        public let names: Names
        /// Its sports in order, the ones no longer offered included.
        public let entries: [Entry]

        public init(id: String, names: Names, entries: [Entry]) {
            (self.id, self.names, self.entries) = (id, names, entries)
        }

        /// The sports a picker shows under this tab.
        public var offered: [Sport] { entries.filter(\.offered).map(\.sport) }
    }

    /// In the picker's order.
    public let categories: [Category]
    /// Sign-up's 最常见 grid.
    public let signUpCommon: [Sport]
    /// Sign-up's 更多 pills.
    public let signUpMore: [Sport]
    /// A 练了's quick picks, before the whole list.
    public let checkInQuick: [Sport]
    private let entries: [Sport: Entry]

    public init(categories: [Category], signUpCommon: [Sport], signUpMore: [Sport], checkInQuick: [Sport]) {
        self.categories = categories
        var entries: [Sport: Entry] = [:]
        for entry in categories.flatMap(\.entries) where entries[entry.sport] == nil { entries[entry.sport] = entry }
        self.entries = entries
        // A short list names only listed sports the pickers offer.
        let offered = { (list: [Sport]) in list.filter { entries[$0]?.offered == true } }
        (self.signUpCommon, self.signUpMore, self.checkInQuick) =
            (offered(signUpCommon), offered(signUpMore), offered(checkInQuick))
    }

    /// No sports at all.
    public static let empty = SportCatalog(categories: [], signUpCommon: [], signUpMore: [], checkInQuick: [])

    /// The sport's names, icon and category; nil for an id this list doesn't have (one the
    /// server added after this list was read).
    public func entry(for sport: Sport) -> Entry? { entries[sport] }

    /// Every sport the pickers offer, in list order.
    public var offered: [Sport] { categories.flatMap(\.offered) }

    /// The offered sports whose name in any language, or id, contains `query`, in list order.
    /// An empty query matches none, so a search field shows its usual list instead.
    public func matching(_ query: String) -> [Sport] {
        let needle = query.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return [] }
        return categories.flatMap(\.entries).filter { entry in
            entry.offered
                && (entry.names.all + [entry.sport.rawValue]).contains { $0.localizedCaseInsensitiveContains(needle) }
        }
        .map(\.sport)
    }
}
