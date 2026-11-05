/// Everything the catalog (`GET /public/catalog`) holds that this build reads: data the app shows
/// that lives in the database, so it changes without an app release.
public struct AppCatalog: Hashable, Sendable {
    /// Every sport the pickers show.
    public let sports: SportCatalog
    /// The ready-made 请假条 lines rolled when the AI can't write.
    public let diceLines: [CatalogNames]
    /// The 商店街 of a member who hasn't trained yet, for an editor opened before the member's own
    /// street is read (signing up, the sample squad): the free stores and their starters. A store
    /// or piece on a switch is left out, since only the server says whether a switch is on.
    public let starterStock: StreetStock

    public init(sports: SportCatalog, diceLines: [CatalogNames], starterStock: StreetStock = .empty) {
        (self.sports, self.diceLines, self.starterStock) = (sports, diceLines, starterStock)
    }

    /// Nothing at all.
    public static let empty = AppCatalog(sports: .empty, diceLines: [])
}
