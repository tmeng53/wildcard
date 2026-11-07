import AvatarDomain
import Contracts
import Foundation

/// The names art carries (`avatar/names.json`), in each of the app's languages, so a piece or
/// store added through the admin tools is named without an app release. The bundled file names
/// every store this build ships with (its words are data only, never code); an uploaded one stands
/// in front of it id by id, so it may name only what it adds or changes. A variant named here
/// stands in front of the String Catalog's name for the same id.
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
        /// The colour of that tag, so a kind of limit can wear its own; nil for the limited colour.
        public let limitedColor: RGBAColor?

        public init(
            name: CatalogNames, local: CatalogNames, sports: CatalogNames? = nil, tagline: CatalogNames? = nil,
            unlock: CatalogNames? = nil, limited: CatalogNames? = nil, limitedColor: RGBAColor? = nil
        ) {
            (self.name, self.local, self.sports) = (name, local, sports)
            (self.tagline, self.unlock, self.limited) = (tagline, unlock, limited)
            self.limitedColor = limitedColor
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

    /// `uploaded`'s names in front of these, id by id.
    public func overlaid(by uploaded: ArtNames) -> ArtNames {
        ArtNames(
            variants: variants.merging(uploaded.variants) { _, new in new },
            stores: stores.merging(uploaded.stores) { _, new in new })
    }

    /// The only `version` of `names.json` this build reads.
    public static let currentVersion = 1

    /// `{"version": 1, "variants": {"trot-bib": {"zhHans": "烤火鸡号码布", "en": "Turkey Bib",
    /// "zhHant": "烤火雞號碼布"}}, "stores": {"trot": {"name": {…}, "local": {…}, "sports": {…},
    /// "tagline": {…}, "unlock": {…}, "limited": {…}, "limitedColor": "#c8553d"}}}`; a store needs `name` and
    /// `local`, and a colour that isn't `#rrggbb` is left out.
    public static func decode(_ data: Data) throws(AvatarError) -> ArtNames {
        let file: File = try decodeJSON(data, version: currentVersion, shape: File.shape)
        return ArtNames(
            variants: (file.variants ?? [:]).mapValues(\.names),
            stores: (file.stores ?? [:]).mapValues {
                Store(
                    name: $0.name.names, local: $0.local.names, sports: $0.sports?.names,
                    tagline: $0.tagline?.names, unlock: $0.unlock?.names, limited: $0.limited?.names,
                    limitedColor: $0.limitedColor.flatMap(RGBAColor.init(hex:)))
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
        let limitedColor: String?
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
    /// The bundled names with the uploaded ones in front, id by id; a file that can't be read
    /// names nothing. Read once
    /// per launch, as the scene pictures are, so a view body never reads the disk; a newer
    /// download names from the next launch.
    public static func names() -> ArtNames { uploadedNames }

    private static let uploadedNames: ArtNames = {
        let bundled = (try? ArtNames.decode(Data(contentsOf: folder.appending(path: "names.json")))) ?? .none
        guard let url = ArtTree.downloadedFile("names.json", in: tree),
            let uploaded = try? ArtNames.decode(Data(contentsOf: url))
        else { return bundled }
        return bundled.overlaid(by: uploaded)
    }()
}
