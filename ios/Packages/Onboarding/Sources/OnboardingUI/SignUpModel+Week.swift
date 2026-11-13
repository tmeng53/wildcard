#if os(iOS)
import Contracts
import OnboardingDomain

/// 关于你's sports and 本周目标's week.
extension SignUpModel {
    // MARK: 关于你

    /// Picks or takes off a sport. A pick changes the character into its kit; taking off the
    /// one it wears changes it into the one picked before, or back into its own clothes.
    func toggle(_ activity: Activity) {
        switch sports.toggle(activity) {
        case .picked: myCharacter?.dress(for: activity)
        case .removed(changed: true): myCharacter?.dress(for: sports.wearing)
        case .removed(changed: false): break
        }
    }

    // MARK: 本周目标

    func selectDay(_ index: Int) {
        week?.select(index)
    }

    /// Sets the selected day. A sport puts the character into its kit and plays its move, as
    /// picking it on 关于你 does; plain 训练 on a rest day makes it hop.
    func setDay(_ day: PlanDay) {
        let becameTraining = week?.set(day) == true
        if case .train(let activity?) = day { myCharacter?.dress(for: activity) } else if becameTraining { hops += 1 }
    }

    func finishWeek() {
        guard let days = week?.days else { return }
        perform { () async throws(SignUpError) in
            try await self.service.savePlan(days)
            self.pastWeek = true
            self.show(.afterWeek(madeTheSquad: self.madeTheSquad, asked: self.request != nil))
        }
    }

    /// 以后再说 on 本周目标: no plan this week; 本周 counts against nothing until one is set.
    func skipWeek() {
        week = nil
        pastWeek = true
        show(.afterWeek(madeTheSquad: madeTheSquad, asked: request != nil))
    }
}
#endif
