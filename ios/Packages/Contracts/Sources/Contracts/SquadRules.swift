/// A squad's name, as its creator types it: one line of at most `maxLength` characters. The
/// API's rule, so the 建一个小队 field can count and refuse before anything is sent.
public struct SquadName: Hashable, Sendable {
    /// Characters, counted as people see them. The API's limit; `APIContract`'s tests fail when
    /// the two differ.
    public static let maxLength = 20

    public let text: String

    public init(_ text: String) throws(ContractsError) {
        switch NameText.check(text, maxLength: Self.maxLength) {
        case .success(let trimmed): self.text = trimmed
        case .failure(.notOneLine): throw .multilineSquadName
        case .failure(.length(let length)): throw .squadNameLength(length)
        case .failure(.invisible): throw .invisibleSquadName
        }
    }
}

/// A squad's invite code, such as `K7M2QX9P`: 8 digits and capitals without the ones people
/// confuse (0 and O, 1, I and L). Read as forgivingly as the API reads it, since people type
/// it: lower case is upper case, and spaces and dashes are left out.
public struct InviteCode: Hashable, Sendable, CustomStringConvertible {
    public static let length = 8
    /// The API's alphabet (`INVITE_CODE_ALPHABET` in the squads module).
    public static let alphabet: Set<Character> = Set("23456789ABCDEFGHJKMNPQRSTUVWXYZ")

    public let text: String

    public init(_ typed: String) throws(ContractsError) {
        let code = Self.normalized(typed)
        guard code.count == Self.length, code.allSatisfy(Self.alphabet.contains) else {
            throw .invalidInviteCode(typed)
        }
        text = code
    }

    /// What the API reads from `typed`: upper case, without spaces or dashes. For showing a
    /// code as it is being typed, one box per letter.
    public static func normalized(_ typed: String) -> String {
        String(typed.uppercased().filter { !$0.isWhitespace && $0 != "-" })
    }

    public var description: String { text }
}

/// How many members a squad holds: 1 to `memberLimit`. The API's `SQUAD_MEMBER_LIMIT`.
public enum SquadSize {
    public static let memberLimit = 8
}
