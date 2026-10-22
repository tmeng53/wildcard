/// What squadmates call the member, under their character. One line of at most `maxLength`
/// characters, emoji welcome. The API also refuses links, which only it checks, so the rule
/// lives in one place.
public struct Nickname: Hashable, Sendable {
    /// Characters, counted as people see them. The API's limit; `APIContract`'s tests fail when
    /// the two differ.
    public static let maxLength = 12

    public let text: String

    public init(_ text: String) throws(ContractsError) {
        switch NameText.check(text, maxLength: Self.maxLength) {
        case .success(let trimmed): self.text = trimmed
        case .failure(.notOneLine): throw .multilineNickname
        case .failure(.length(let length)): throw .nicknameLength(length)
        case .failure(.invisible): throw .invisibleNickname
        }
    }
}

/// How a member's character looks and moves, by the ids of the character art: the persona,
/// the variant each slot wears (`body` always among them) and the swatch a slot is recolored
/// to, as `#RRGGBB`. The ids are data, so new art needs no change here; the API checks their
/// shape, and an app that doesn't know one draws the slot's default.
public struct CharacterLook: Hashable, Sendable {
    public var persona: String
    public var variants: [String: String]
    public var colors: [String: String]

    public init(persona: String, variants: [String: String], colors: [String: String] = [:]) {
        (self.persona, self.variants, self.colors) = (persona, variants, colors)
    }
}

/// The member's character: what squadmates call them and how it looks, made together in the
/// character editor. Not `Character`, which is Swift's.
public struct MemberCharacter: Hashable, Sendable {
    public var nickname: Nickname
    public var look: CharacterLook

    public init(nickname: Nickname, look: CharacterLook) {
        (self.nickname, self.look) = (nickname, look)
    }
}
