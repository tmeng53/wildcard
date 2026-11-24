import APIContract
import Contracts
import Foundation

// 举报 and 拉黑 (App Review 1.2).
extension WildcardAPI {
    /// What a member reports, as the API names it.
    public enum Reported: Sendable {
        case checkIn
        case comment(CommentID)
        case coachReply(CoachID, squad: SquadID)
        case coachAnswer(answering: CommentID, squad: SquadID)
    }

    /// A member the signed-in member blocked, as 设置 › 已拉黑 lists them.
    public struct Blocked: Sendable {
        public let member: MemberID
        public let character: MemberCharacter?
        public let since: Date
    }

    /// Reports a post, a comment under it or the coach's line there; the server hides it from the
    /// member at once and keeps the first report of the same thing.
    public func report(_ reported: Reported, on checkIn: CheckInID) async throws(APIError) {
        let (kind, item, squad): (Components.Schemas.ReportDraft.KindPayload, String?, SquadID?) =
            switch reported {
            case .checkIn: (.checkIn, nil, nil)
            case .comment(let comment): (.comment, comment.description, nil)
            case .coachReply(let coach, let squad): (.coachReply, coach.rawValue, squad)
            case .coachAnswer(let comment, let squad): (.coachAnswer, comment.description, squad)
            }
        let draft = Components.Schemas.ReportDraft(
            version: ._1, id: UUID().uuidString.lowercased(), kind: kind, checkIn: checkIn.description, item: item,
            squad: squad?.description)
        try await call {
            switch try await client.report(body: .json(draft)) {
            case .created, .ok: return
            default: throw APIError.unreadableResponse
            }
        }
    }

    /// Blocks a member both ways. Safe to repeat.
    public func block(_ member: MemberID) async throws(APIError) {
        try await call { _ = try await client.blockMember(path: .init(memberId: member.description)).noContent }
    }

    /// Unblocks a member; one not blocked is fine too.
    public func unblock(_ member: MemberID) async throws(APIError) {
        try await call { _ = try await client.unblockMember(path: .init(memberId: member.description)).noContent }
    }

    /// Whom the member blocked, newest first.
    public func blocked() async throws(APIError) -> [Blocked] {
        let list = try await call { try await client.listMyBlocks().ok.body.json }
        return try read { () throws(ContractsError) in
            try list.blocked.map { wire throws(ContractsError) in
                let character: MemberCharacter? =
                    if let nickname = wire.nickname, let look = wire.look {
                        MemberCharacter(nickname: try Nickname(nickname), look: CharacterLook(look))
                    } else {
                        nil
                    }
                guard let id = UUID(uuidString: wire.member) else { throw .invalidID(wire.member) }
                return Blocked(member: MemberID(id), character: character, since: wire.since)
            }
        }
    }
}
