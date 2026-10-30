/// Everything the catalog (`GET /public/catalog`) holds that this build reads: data the app shows
/// that lives in the database, so it changes without an app release.
public struct AppCatalog: Hashable, Sendable {
    /// Every sport the pickers show.
    public let sports: SportCatalog
    /// The ready-made 请假条 lines rolled when the AI can't write.
    public let diceLines: [CatalogNames]

    public init(sports: SportCatalog, diceLines: [CatalogNames]) {
        (self.sports, self.diceLines) = (sports, diceLines)
    }

    /// Nothing at all.
    public static let empty = AppCatalog(sports: .empty, diceLines: [])
}
