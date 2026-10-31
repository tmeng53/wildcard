import Foundation

/// The sports list every picker shows: categories in order, each sport's names, icon and
/// category, and the short lists some screens show first. Data the API serves, so a new sport,
/// name, icon or order needs no app release; the app keeps the last list it read.
public struct SportCatalog: Hashable, Sendable {
    public struct Entry: Hashable, Sendable {
        public let sport: Sport
        public let names: CatalogNames
        /// The name on a card or poster row, for a sport whose name is too long there.
        public let shortNames: CatalogNames?
        /// An SF Symbol name.
        public let icon: String
        /// False for a sport the pickers no longer offer; check-ins that name it still show it.
        public let offered: Bool
        /// The id of the category it is in.
        public let category: String

        public init(
            sport: Sport, names: CatalogNames, shortNames: CatalogNames? = nil, icon: String, offered: Bool,
            category: String
        ) {
            (self.sport, self.names, self.shortNames, self.icon, self.offered, self.category) = (
                sport, names, shortNames, icon, offered, category
            )
        }
    }

    /// One of the picker's tabs.
    public struct Category: Hashable, Sendable, Identifiable {
        public let id: String
        public let names: CatalogNames
        /// Its sports in order, the ones no longer offered included.
        public let entries: [Entry]

        public init(id: String, names: CatalogNames, entries: [Entry]) {
            (self.id, self.names, self.entries) = (id, names, entries)
        }

        /// The sports a picker shows under this tab.
        public var offered: [Sport] { entries.filter(\.offered).map(\.sport) }
    }

    /// In the picker's order.
    public let categories: [Category]
    /// Sign-up's 最常见 grid.
    public let signUpCommon: [Sport]
    /// A 练了's quick picks, before the whole list.
    public let checkInQuick: [Sport]
    private let entries: [Sport: Entry]

    public init(categories: [Category], signUpCommon: [Sport], checkInQuick: [Sport]) {
        self.categories = categories
        var entries: [Sport: Entry] = [:]
        for entry in categories.flatMap(\.entries) where entries[entry.sport] == nil { entries[entry.sport] = entry }
        self.entries = entries
        // A short list names only listed sports the pickers offer.
        let offered = { (list: [Sport]) in list.filter { entries[$0]?.offered == true } }
        (self.signUpCommon, self.checkInQuick) = (offered(signUpCommon), offered(checkInQuick))
    }

    /// No sports at all.
    public static let empty = SportCatalog(categories: [], signUpCommon: [], checkInQuick: [])

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
