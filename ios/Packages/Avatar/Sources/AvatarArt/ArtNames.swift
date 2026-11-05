import AvatarDomain
import Contracts
import Foundation
import Synchronization

/// The names uploaded art carries (`avatar/names.json`), in each of the app's languages, so a
/// piece or store added through the admin tools is named without an app release. Nothing is
/// bundled: the app's own art is named in the String Catalog, and a name here stands in front
/// of the catalog's for the same id.
public struct ArtNames: Hashable, Sendable {
    /// A store's words, as 商店街 shows them.
    public struct Store: Hashable, Sendable {
        /// The sign's name (`TURKEY TROT`).
        public let name: CatalogNames
        /// Its name in the reader's language (火鸡全开).
        public let local: CatalogNames
        /// Which sports open it, in words.
        public let sports: CatalogNames?
        public let tagline: CatalogNames?
        /// How it opens (跑步 3 次解锁).
        public let unlock: CatalogNames?
        /// The tag a limited store wears (感恩节限定).
        public let limited: CatalogNames?

        public init(
            name: CatalogNames, local: CatalogNames, sports: CatalogNames? = nil, tagline: CatalogNames? = nil,
            unlock: CatalogNames? = nil, limited: CatalogNames? = nil
        ) {
            (self.name, self.local, self.sports) = (name, local, sports)
            (self.tagline, self.unlock, self.limited) = (tagline, unlock, limited)
        }
    }

    /// Each variant's name by its id (`trot-bib`), or by `<slot>/<id>` for a face part, since a
    /// mouth and a body can share an id.
    public let variants: [String: CatalogNames]
    public let stores: [String: Store]

    public init(variants: [String: CatalogNames] = [:], stores: [String: Store] = [:]) {
        (self.variants, self.stores) = (variants, stores)
    }

    public static let none = ArtNames()

    /// The name of `variant` in `slot`, if the uploaded names have one.
    public func variant(_ variant: String, in slot: Slot) -> CatalogNames? {
        variants["\(slot)/\(variant)"] ?? variants[variant]
    }

    /// The only `version` of `names.json` this build reads.
    public static let currentVersion = 1

    /// `{"version": 1, "variants": {"trot-bib": {"zhHans": "烤火鸡号码布", "en": "Turkey Bib",
    /// "zhHant": "烤火雞號碼布"}}, "stores": {"trot": {"name": {…}, "local": {…}, "sports": {…},
    /// "tagline": {…}, "unlock": {…}, "limited": {…}}}}`; a store needs `name` and `local`.
    public static func decode(_ data: Data) throws(AvatarError) -> ArtNames {
        let file: File = try decodeJSON(data, version: currentVersion, shape: File.shape)
        return ArtNames(
            variants: (file.variants ?? [:]).mapValues(\.names),
            stores: (file.stores ?? [:]).mapValues {
                Store(
                    name: $0.name.names, local: $0.local.names, sports: $0.sports?.names,
                    tagline: $0.tagline?.names, unlock: $0.unlock?.names, limited: $0.limited?.names)
            })
    }

    private struct File: Decodable {
        // Keyed by id, so any key goes.
        static let shape = JSONShape.object(["version": .value, "variants": .value, "stores": .value])

        let variants: [String: ArtWords]?
        let stores: [String: StoreFile]?
    }

    private struct StoreFile: Decodable {
        let name: ArtWords
        let local: ArtWords
        let sports: ArtWords?
        let tagline: ArtWords?
        let unlock: ArtWords?
        let limited: ArtWords?
    }
}

/// A name in each of the app's languages, as `names.json` writes it.
private struct ArtWords: Decodable {
    let zhHans: String
    let english: String
    let zhHant: String

    private enum CodingKeys: String, CodingKey {
        case zhHans, zhHant
        case english = "en"
    }

    var names: CatalogNames {
        CatalogNames(simplifiedChinese: zhHans, english: english, traditionalChinese: zhHant)
    }
}

extension PlaceholderCharacter {
    /// The uploaded names, read again only when the downloaded file changes; none when nothing
    /// was uploaded or the file can't be read.
    public static func names() -> ArtNames {
        let url = ArtTree.url("names.json", in: tree, bundled: folder)
        let stamp =
            (try? FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false)))?[
                .modificationDate] as? Date
        if let cached = namesCache.withLock({ $0 }), cached.url == url, cached.stamp == stamp { return cached.names }
        let names = stamp == nil ? ArtNames.none : (try? ArtNames.decode(Data(contentsOf: url))) ?? .none
        namesCache.withLock { $0 = (url, stamp, names) }
        return names
    }

    private static let namesCache = Mutex<(url: URL, stamp: Date?, names: ArtNames)?>(nil)
}
