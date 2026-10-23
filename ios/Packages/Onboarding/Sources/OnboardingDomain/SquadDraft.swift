import Contracts

/// 你的小队: join a friend's squad by its invite code, or make one. An invite link opens sign-up
/// on 加入小队 with its code filled in.
public struct SquadDraft: Hashable, Sendable {
    public enum Choice: Hashable, Sendable {
        case join
        case create
    }

    public var choice: Choice
    /// The code as typed: kept as is, so a half-typed code shows; `code` reads it.
    public var typedCode: String
    /// The name as typed; `name` reads it.
    public var typedName: String

    /// `invite`: the code an invite link carried, if sign-up opened from one. `suggestedName`:
    /// what 建一个小队 starts from, such as 「Tracy 的小队」.
    public init(invite: InviteCode?, suggestedName: String) {
        choice = invite == nil ? .create : .join
        typedCode = invite?.text ?? ""
        typedName = suggestedName
    }

    /// The code once it is a whole one, to look up.
    public var code: InviteCode? { try? InviteCode(typedCode) }

    /// The code's letters as the boxes show them: upper case, without spaces or dashes, at most
    /// `InviteCode.length`.
    public var codeLetters: [Character] {
        Array(InviteCode.normalized(typedCode).prefix(InviteCode.length))
    }

    /// The name once it is one the API takes.
    public var name: SquadName? { try? SquadName(typedName) }
}

/// The squad an invite code belongs to, as 加入小队 shows it before joining.
public struct SquadPreview: Hashable, Sendable {
    public let code: InviteCode
    public let name: String
    public let memberCount: Int
    /// The squad has its 8 members and can't take more.
    public let isFull: Bool
    /// The members' characters, the earliest to join first, for their heads under the name.
    /// Members who haven't made theirs yet are left out.
    public let looks: [CharacterLook]

    public init(code: InviteCode, name: String, memberCount: Int, isFull: Bool, looks: [CharacterLook]) {
        (self.code, self.name, self.memberCount, self.isFull, self.looks) = (code, name, memberCount, isFull, looks)
    }
}
