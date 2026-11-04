/// Everything the catalog (`GET /public/catalog`) holds that this build reads: data the app shows
/// that lives in the database, so it changes without an app release.
public struct AppCatalog: Hashable, Sendable {
    /// Every sport the pickers show.
    public let sports: SportCatalog
    /// The ready-made 请假条 lines rolled when the AI can't write.
    public let diceLines: [CatalogNames]
    /// The global switches limited stores follow, by id.
    public let switches: [String: CatalogSwitch]

    public init(sports: SportCatalog, diceLines: [CatalogNames], switches: [String: CatalogSwitch] = [:]) {
        (self.sports, self.diceLines, self.switches) = (sports, diceLines, switches)
    }

    /// Nothing at all.
    public static let empty = AppCatalog(sports: .empty, diceLines: [])
}
