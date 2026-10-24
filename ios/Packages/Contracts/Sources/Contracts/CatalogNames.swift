/// A name or a line in each of the app's languages, as the catalog serves it (a sport, a 请假条
/// dice line), so the words change without an app release.
public struct CatalogNames: Hashable, Sendable {
    public let simplifiedChinese: String
    public let english: String
    public let traditionalChinese: String

    public init(simplifiedChinese: String, english: String, traditionalChinese: String) {
        (self.simplifiedChinese, self.english, self.traditionalChinese) = (
            simplifiedChinese, english, traditionalChinese
        )
    }

    /// Each language's words, for search.
    public var all: [String] { [simplifiedChinese, english, traditionalChinese] }
}
