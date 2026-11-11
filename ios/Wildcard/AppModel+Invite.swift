import Backend
import Contracts
import Foundation
import OnboardingUI

/// Invite links, and sign-up for a member in no squad.
extension AppModel {
    /// `takesInvite`: the sign-up starts from the invite link that opened the app, if one is
    /// waiting, and uses it up; a resumed sign-up is already in its squad and leaves it.
    func newSignUp(hasAgreedToAI: Bool, takesInvite: Bool = true) -> SignUpModel {
        let model = SignUpModel(
            service: APISignUpService(api: api), nickname: "", now: Date(), hasAgreedToAI: hasAgreedToAI,
            health: Self.health, location: Self.location)
        if takesInvite, let code = invite {
            invite = nil
            model.open(invite: code)
        }
        return model
    }

    /// Sign-up for a member in no squad. One who was in a squad keeps everything else (Tracy,
    /// 2026-11-11), so only 加入小队, told first if the captain removed them; not knowing, or never
    /// having made a character, signs up from the start.
    func squadless(continuing signUp: SignUpModel?, name: String?) async -> SignUpModel {
        // Consent is the account's: a member who agreed before, and left their squad since,
        // isn't asked again. Not knowing asks, and agreeing again is safe.
        let agreed = (try? await api.hasAgreedToAI()) ?? false
        let model = (agreed ? nil : signUp) ?? newSignUp(hasAgreedToAI: agreed)
        let last = try? await api.lastSquad()
        if let last, await model.rejoin() {
            if last.wasRemoved, RemovalNotice.isNew(last.id) { removedFromName = last.name }
        } else {
            model.signedIn(name: name)
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
