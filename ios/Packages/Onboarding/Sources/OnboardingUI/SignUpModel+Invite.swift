#if os(iOS)
import Contracts
import OnboardingDomain

extension SignUpModel {
    /// An invite link opened before the member joined or made a squad: 你的小队 shows 加入小队
    /// with its code in and the squad it finds. Once they are in one, the link changes nothing.
    public func open(invite: InviteCode) {
        guard joinedSquad == nil else { return }
        choose(.join)
        typeCode(invite.text)
    }
}
#endif
