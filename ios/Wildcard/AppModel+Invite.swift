import Backend
import Contracts
import Foundation
import OnboardingUI

/// Invite links.
extension AppModel {
    /// `takesInvite`: the sign-up starts from the invite link that opened the app, if one is
    /// waiting, and uses it up; a resumed sign-up is already in its squad and leaves it.
    func newSignUp(hasAgreedToAI: Bool, takesInvite: Bool = true) -> SignUpModel {
        let model = SignUpModel(
            service: APISignUpService(api: api), nickname: "", now: Date(), hasAgreedToAI: hasAgreedToAI,
            health: Self.health)
        if takesInvite, let code = invite {
            invite = nil
            model.open(invite: code)
        }
        return model
    }

    /// An invite link (wildcardsquad.com/join/<code>) opened the app: sign-up's 你的小队 starts on
    /// 加入小队 with its code, now, or once sign-up opens if the app is still starting. A member
    /// already in a squad just gets the app (one squad each), and the link is forgotten.
    func open(invite code: InviteCode) {
        switch screen {
        case .starting: invite = code
        case .signUp(let model): model.open(invite: code)
        case .tabs: invite = nil
        }
    }
}
