import Contracts

extension SquadToday {
    /// The squad's today with one more check-in of the signed-in member's counted, the way the
    /// server will count it: the first 练了 of a day adds a trained day to their week and the squad's, a 请假条
    /// marks a day not yet trained, a meal only shows as their latest. The home shows a post at
    /// once with this, before the server answers or while it waits to go out. One not shared to
    /// this squad counts only in the member's own row and week: teammates never see it.
    public func countingMine(_ checkIn: CheckIn) -> SquadToday {
        let kind: Kind =
            switch checkIn.entry {
            case .trained: .trained
            case .disclaimer: .disclaimer
            case .healthyMeal: .healthyMeal
            case .cheatMeal: .cheatMeal
            }
        return counting(
            kind, by: checkIn.member, on: checkIn.day, at: checkIn.createdAt,
            counts: checkIn.audience.squads.contains(squad) ? .squadAndMine : .mine)
    }

    /// The member's own row with a check-in the server has already counted, in their week and,
    /// if it was shared here, the squad's: one not shared to this squad is left out of the
    /// squad's today, but on their own phone their character still shows what they did. Shown
    /// oldest first, the row ends on the latest meal.
    public func showingMine(_ checkIn: CheckIn) -> SquadToday {
        let kind: Kind =
            switch checkIn.entry {
            case .trained: .trained
            case .disclaimer: .disclaimer
            case .healthyMeal: .healthyMeal
            case .cheatMeal: .cheatMeal
            }
        return counting(kind, by: checkIn.member, on: checkIn.day, at: checkIn.createdAt, counts: .none)
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
        return counting(
            kind, by: post.member, on: post.day, at: post.createdAt,
            counts: post.audience.squads.contains(squad) ? .squadAndMine : .mine)
    }

    private enum Kind { case trained, disclaimer, healthyMeal, cheatMeal }

    /// Which counts a check-in adds to, besides the member's own row.
    private enum Counts {
        /// Shared to this squad: the squad's today and week, and the member's week.
        case squadAndMine
        /// Not shared here: only the member's week.
        case mine
        /// Already counted where it counts.
        case none
    }

    private func counting(
        _ kind: Kind, by author: MemberID, on day: LocalDay, at moment: Timestamp, counts: Counts
    ) -> SquadToday {
        guard let index = members.firstIndex(where: { $0.member == author }), members[index].day == day else {
            return self
        }
        var counted = self
        var member = members[index]
        switch kind {
        case .trained: counted.countTraining(of: &member, on: day, counts: counts)
        case .disclaimer: counted.countDisclaimer(of: &member, counts: counts)
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
        // The squad sees only what was shared to it.
        guard counts == .squadAndMine else { return counted }
        counted.today.everyoneTrained =
            counted.today.trained > 0
            && counted.members.allSatisfy { $0.training == .trained || $0.plannedRest }
        return counted
    }

    /// A 练了: the member's first today adds a trained day to their week and the squad's.
    private mutating func countTraining(of member: inout SquadmateToday, on day: LocalDay, counts: Counts) {
        guard member.training != .trained else { return }
        let before = member.training
        member.training = .trained
        guard counts != .none else { return }
        if (myWeek.firstDay...myWeek.lastDay).contains(day) { myWeek.week.trainedDays += 1 }
        guard counts == .squadAndMine else { return }
        if before == .disclaimer { today.disclaimer -= 1 }
        if member.plannedRest && before == .notCheckedIn { today.resting -= 1 }
        today.trained += 1
        squadWeek.trainedDays += 1
    }

    /// A 请假条, on a day not yet checked in.
    private mutating func countDisclaimer(of member: inout SquadmateToday, counts: Counts) {
        guard member.training == .notCheckedIn else { return }
        member.training = .disclaimer
        guard counts == .squadAndMine else { return }
        if member.plannedRest { today.resting -= 1 }
        today.disclaimer += 1
    }
}
