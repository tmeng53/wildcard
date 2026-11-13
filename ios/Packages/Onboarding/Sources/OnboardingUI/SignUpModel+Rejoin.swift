#if os(iOS)
import OnboardingDomain

/// A member back in no squad: the character they saved, and only 加入小队 left to do.
extension SignUpModel {
    /// A member who was in a squad and is in none now: 加入小队 alone, as the character they saved;
    /// false if they never made one (or it can't be read), for sign-up from the start.
    public func rejoin() async -> Bool {
        guard let made = try? await service.character() else { return false }
        isRejoining = true
        (character, nickname) = (made, made.nickname.text)
        if squad.typedName.isEmpty { squad.typedName = Self.suggestedName(for: nickname) }
        let cast = CastMember(outfit: made.outfit, persona: made.persona)
        myCharacter = cast
        // A character stays still beside a title, as it does after 角色和昵称.
        await cast.load(idle: false)
        show(.squad)
        return true
    }

    var afterSquad: SignUpStep {
        .afterSquad(rejoining: isRejoining || pastWeek, madeTheSquad: madeTheSquad, asked: request != nil)
    }
}
#endif
