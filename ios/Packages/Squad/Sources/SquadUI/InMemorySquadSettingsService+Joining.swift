import Contracts
import DesignSystemUI
import Foundation
import SquadDomain

extension InMemorySquadSettingsService {
    public func answer(_ request: JoinRequestID, in squad: SquadID, approve: Bool) async throws(SquadError) {
        if failsSaving { throw .unavailable }
        guard let asked = current.joining?.requests.first(where: { $0.id == request }) else { throw .outdated }
        current.joining?.requests.removeAll { $0.id == request }
        guard approve else { return }
        guard current.squad.members.count < SquadSize.memberLimit else { throw .outdated }
        current.squad = current.squad.with(members: current.squad.members + [asked.member])
        if let character = asked.character { current.characters[asked.member] = character }
    }

    public func setJoinApproval(of squad: SquadID, required: Bool) async throws(SquadError) -> Bool {
        if failsSaving { throw .unavailable }
        guard current.joining != nil else { throw .outdated }
        current.joining?.required = required
        return required
    }

    /// 小橘 asking to join, with a note (备注), as the approved design shows it.
    static func askedJoining(at now: Date) -> SquadJoining {
        let character = (try? Nickname(String(copyKey: "小橘", bundle: Bundle.module))).map {
            MemberCharacter(
                nickname: $0,
                look: CharacterLook(
                    persona: "shy", variants: ["body": "calico", "top": "warmup-hoodie", "bottom": "warmup-shorts"]))
        }
        let request = WaitingJoinRequest(
            id: JoinRequestID(UUID(uuidString: "b0000000-0000-4000-8000-000000000001") ?? UUID()),
            member: MemberID(UUID(uuidString: "a0000000-0000-4000-8000-000000000009") ?? UUID()),
            character: character, note: String(copyKey: "我是小橘，阿杰拉我来的", bundle: Bundle.module),
            askedAt: now.addingTimeInterval(-600))
        return SquadJoining(required: true, requests: [request])
    }
}
