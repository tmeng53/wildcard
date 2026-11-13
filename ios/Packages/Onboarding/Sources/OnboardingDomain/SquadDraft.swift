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
    /// 小队目标 for a squad being made: each member's 训练 a week, 人均 N 次. The captain
    /// changes it later on 小队.
    public var daysPerMember = SquadWeeklyGoal.defaultDaysPerMember

    /// 比赛时区 for a squad being made, an IANA name: the clock its 战报 freezes on, Sunday 8pm,
    /// and its coach's daily 战术板 keeps. Each member's own day keeps their phone's.
    public var timeZone: String

    /// `invite`: the code an invite link carried, if sign-up opened from one. `suggestedName`:
    /// what 建一个小队 starts from, such as 「Tracy 的小队」. `timeZone`: the phone's, which a new
    /// squad keeps unless the creator picks another.
    public init(invite: InviteCode?, suggestedName: String, timeZone: String) {
        choice = invite == nil ? .create : .join
        typedCode = invite?.text ?? ""
        typedName = suggestedName
        self.timeZone = timeZone
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

    /// 备注 as typed, to the captain of a squad whose joining needs their OK; `note` reads it.
    public var typedNote = ""

    /// The 备注 to send: nil when left empty, or when it is one the API won't take, which
    /// `noteIsValid` says.
    public var note: JoinNote? {
        typedNote.isEmpty ? nil : try? JoinNote(typedNote)
    }

    /// Whether 申请加入 can go with the 备注 as typed: empty, or one line the API takes.
    public var noteIsValid: Bool { typedNote.isEmpty || note != nil }
}

/// The squad an invite code belongs to, as 加入小队 shows it before joining.
public struct SquadPreview: Hashable, Sendable {
    public let code: InviteCode
    public let name: String
    public let memberCount: Int
    /// The squad has its 8 members and can't take more.
    public let isFull: Bool
    /// Joining asks its captain first (入队需要审核): 加入小队 becomes 申请加入, with a 备注.
    public let needsApproval: Bool
    /// The members' characters, the earliest to join first, for their heads under the name.
    /// Members who haven't made theirs yet are left out.
    public let looks: [CharacterLook]

    public init(
        code: InviteCode, name: String, memberCount: Int, isFull: Bool, needsApproval: Bool,
        looks: [CharacterLook]
    ) {
        (self.code, self.name, self.memberCount, self.isFull) = (code, name, memberCount, isFull)
        (self.needsApproval, self.looks) = (needsApproval, looks)
    }
}
