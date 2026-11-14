/// The place a member tagged a 训练 or a meal with (Tracy, 2026-11-12): one they picked in Apple
/// Maps, never where the phone was. The squad sees its name and opens it in Maps; the coach reads
/// only its name.
public struct Place: Hashable, Sendable {
    /// Characters, counted as people see them; the API's limit.
    public static let maxNameLength = 100

    public let name: String
    /// Apple Maps' identifier for the place, when Maps gave one.
    public let appleID: String?
    /// Apple Maps' point-of-interest category, such as `fitnessCenter`; nil when Maps gave none.
    public let category: String?
    public let latitude: Double
    public let longitude: Double

    /// Trims the name; an id or category the API wouldn't take is left out rather than losing
    /// the place.
    public init(
        name: String, appleID: String? = nil, category: String? = nil, latitude: Double, longitude: Double
    ) throws(ContractsError) {
        switch NameText.check(name, maxLength: Self.maxNameLength) {
        case .success(let trimmed): self.name = trimmed
        case .failure(.length(let length)): throw .placeName(length)
        case .failure(.notOneLine), .failure(.invisible): throw .placeName(name.count)
        }
        guard (-90...90).contains(latitude), (-180...180).contains(longitude) else {
            throw .placeCoordinate(latitude: latitude, longitude: longitude)
        }
        self.appleID = appleID.flatMap { (1...200).contains($0.count) ? $0 : nil }
        self.category = category.flatMap { Self.isCategory($0) ? $0 : nil }
        (self.latitude, self.longitude) = (latitude, longitude)
    }

    /// The API's shape for a category: 1 to 60 ASCII letters.
    private static func isCategory(_ text: String) -> Bool {
        (1...60).contains(text.unicodeScalars.count)
            && text.unicodeScalars.allSatisfy { ("a"..."z").contains($0) || ("A"..."Z").contains($0) }
    }
}

/// The member's own note on a place they saved (收藏的备注): one line of at most `maxLength`
/// characters. The API's rule, so the field can count and refuse before anything is sent.
public struct SavedPlaceNote: Hashable, Sendable {
    /// Characters, counted as people see them. The API's limit; `APIContract`'s tests fail when
    /// the two differ.
    public static let maxLength = 60

    public let text: String

    public init(_ text: String) throws(ContractsError) {
        switch NameText.check(text, maxLength: Self.maxLength) {
        case .success(let trimmed): self.text = trimmed
        case .failure(.notOneLine): throw .multilineSavedPlaceNote
        case .failure(.length(let length)): throw .savedPlaceNoteLength(length)
        case .failure(.invisible): throw .invisibleSavedPlaceNote
        }
    }
}
