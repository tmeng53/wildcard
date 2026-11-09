#if os(iOS)
import Contracts
import OnboardingDomain

/// 关于你: the birthday, if the member gives it, and the sports they usually do.
extension SignUpModel {
    /// 下一步: saves the birthday if the member turned a card, then on to the next step this phone
    /// can do (连上 Apple 健康, 打开大概位置 or 本周目标).
    func finishSports() {
        let next = SignUpStep.sports.next(hasHealth: hasHealth, hasLocation: hasLocation) ?? .week
        guard birthday.isTouched, let picked = birthday.birthday(today: today) else {
            show(next)
            return
        }
        perform { () async throws(SignUpError) in
            try await self.service.save(birthday: picked)
            self.show(next)
        }
    }

    /// 以后再说: on with no sports, so training days name none, and no birthday.
    func skipSports() {
        birthday = BirthdayDraft()
        if sports.wearing != nil { myCharacter?.dress(for: nil) }
        sports = SportPicks()
        show(SignUpStep.sports.next(hasHealth: hasHealth, hasLocation: hasLocation) ?? .week)
    }

    /// Whether 下一步 can go: a sport picked, or a birthday given.
    var canFinishSports: Bool {
        !sports.picked.isEmpty || (birthday.isTouched && birthday.birthday(today: today) != nil)
    }
}
#endif
