import Contracts

extension SquadToday {
    /// The squad's today with one more check-in of the signed-in member's counted, the way the
    /// server will count it: the first 练了 of a day adds a trained day to their week and the squad's, a 请假条
    /// marks a day not yet trained, a meal only shows as their latest. The home shows a post at
    /// once with this, before the server answers or while it waits to go out.
    public func countingMine(_ checkIn: CheckIn) -> SquadToday {
        let kind: Kind =
            switch checkIn.entry {
            case .trained: .trained
            case .disclaimer: .disclaimer
            case .healthyMeal: .healthyMeal
            case .cheatMeal: .cheatMeal
            }
        return counting(kind, by: checkIn.member, on: checkIn.day, at: checkIn.createdAt)
    }

    /// The same for a post still waiting to go out.
    public func countingMine(_ post: PendingCheckIn) -> SquadToday {
        let kind: Kind =
            switch post.draft {
            case .trained: .trained
            case .disclaimer: .disclaimer
            case .healthyMeal: .healthyMeal
            case .cheatMeal: .cheatMeal
            }
        return counting(kind, by: post.member, on: post.day, at: post.createdAt)
    }

    private enum Kind { case trained, disclaimer, healthyMeal, cheatMeal }

    private func counting(_ kind: Kind, by author: MemberID, on day: LocalDay, at moment: Timestamp) -> SquadToday {
        guard let index = members.firstIndex(where: { $0.member == author }), members[index].day == day else {
            return self
        }
        var counted = self
        var member = members[index]
        switch kind {
        case .trained: counted.countTraining(of: &member, on: day)
        case .disclaimer: counted.countDisclaimer(of: &member)
        case .healthyMeal: member.latestMeal = .healthyMeal
        case .cheatMeal: member.latestMeal = .cheatMeal
        }
        let isFirst = member.firstCheckInAt == nil
        if isFirst { member.firstCheckInAt = moment }
        counted.members[index] = member
        if isFirst {
            // Those who checked in come first, by their first check-in.
            counted.members.remove(at: index)
            let after = counted.members.lastIndex { $0.firstCheckInAt != nil }.map { $0 + 1 } ?? 0
            counted.members.insert(member, at: after)
        }
        counted.today.everyoneTrained =
            counted.today.trained > 0
            && counted.members.allSatisfy { $0.training == .trained || $0.plannedRest }
        return counted
    }

    /// A 练了: the member's first today adds a trained day to their week and the squad's.
    private mutating func countTraining(of member: inout SquadmateToday, on day: LocalDay) {
        guard member.training != .trained else { return }
        if member.training == .disclaimer { today.disclaimer -= 1 }
        if member.plannedRest && member.training == .notCheckedIn { today.resting -= 1 }
        member.training = .trained
        today.trained += 1
        squadWeek.trainedDays += 1
        myWeek.lifetimeTrainedDays += 1
        if (myWeek.firstDay...myWeek.lastDay).contains(day) { myWeek.week.trainedDays += 1 }
    }

    /// A 请假条, on a day not yet checked in.
    private mutating func countDisclaimer(of member: inout SquadmateToday) {
        guard member.training == .notCheckedIn else { return }
        if member.plannedRest { today.resting -= 1 }
        member.training = .disclaimer
        today.disclaimer += 1
    }
}
