/// The city the phone's approximate location is in, as iOS names it in the app's language (多伦多,
/// Toronto), which the member's coach is told with their weather. A name iOS gives that the API
/// wouldn't take (blank, too long, on more than one line) is no name.
public struct CityName: Hashable, Sendable, Codable {
    /// Characters, counted as people see them.
    public static let maxLength = 60

    public let name: String

    /// Nil when `raw` isn't a name the API takes.
    public init?(_ raw: String) {
        guard case .success(let trimmed) = NameText.check(raw, maxLength: Self.maxLength) else { return nil }
        name = trimmed
    }
}
