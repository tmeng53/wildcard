#if os(iOS)
import AvatarArt
import AvatarDomain
import Contracts
import OnboardingDomain

/// 申请加入 and 等队长同意: joining a squad whose captain lets members in (Tracy, 2026-11-12).
extension SignUpModel {
    /// The squad found asks its captain first: 加入小队 is 申请加入, with a 备注.
    var asksCaptain: Bool {
        guard squad.choice == .join, case .found(let found) = preview else { return false }
        return found.needsApproval
    }

    func typeNote(_ text: String) {
        squad.typedNote = text
        failure = nil
    }

    /// The member asked: 等队长同意 shows the squad, its heads and its captain.
    func asked(_ request: JoinRequest) async {
        let heads = request.looks.map { CastMember(outfit: Outfit($0), persona: Persona($0)) }
        let captain = request.captain.map { CastMember(outfit: Outfit($0.look), persona: Persona($0.look)) }
        for head in heads + [captain].compactMap(\.self) { await head.load(idle: false) }
        (self.request, requestHeads, captainHead) = (request, heads, captain)
    }

    /// A member in no squad whose request still waits, or whose no they haven't seen yet, as the
    /// app opens: 等队长同意 or 申请没有通过 alone, as the character they saved; false if they never
    /// made one, for sign-up from the start.
    public func wait(on request: JoinRequest) async -> Bool {
        guard await rejoin() else { return false }
        await asked(request)
        show(.waiting)
        return true
    }

    /// Reads the request again, while 等队长同意 shows: once the captain let the member in, on to
    /// 上场 with the squad; a no shows 申请没有通过. Nothing changes when it can't be read.
    public func checkRequest() async {
        guard step == .waiting, let asked = request, asked.status != .declined else { return }
        // A yes already read waits only for the squad to be read.
        let read = asked.status == .approved ? asked : try? await service.joinRequest()
        guard let fresh = read, fresh.id == asked.id, step == .waiting else { return }
        switch fresh.status {
        case .waiting:
            return
        case .approved:
            request = nil
            // In the squad now: 上场 with its teammates, as joining one goes. Read again next time
            // if the squad can't be read yet.
            let inSquad = await resume(in: fresh.squad, madeIt: false, rejoining: true)
            if !inSquad { request = fresh }
        case .declined:
            request = fresh
        case .over:
            // Withdrawn or cancelled elsewhere, such as on another phone: choose again.
            chooseAgain()
        }
    }

    /// 撤回申请: the request is withdrawn, and the member chooses a squad again.
    func withdrawRequest() {
        perform { () async throws(SignUpError) in
            try await self.service.withdrawJoinRequest()
            self.chooseAgain()
        }
    }

    /// 重新选小队, after a no: back to 加入小队 or 建一个小队, keeping everything else.
    func chooseAgain() {
        (request, requestHeads, captainHead) = (nil, [], nil)
        squad.typedNote = ""
        failure = nil
        show(.squad, forward: false)
    }
}
#endif
