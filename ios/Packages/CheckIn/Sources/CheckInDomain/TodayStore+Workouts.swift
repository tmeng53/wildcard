import Contracts

extension TodayStore {
    /// The workouts the member posted, saved or still waiting to go out: a workout is posted
    /// once, so 打卡 shows these as posted and the home's card leaves them out.
    public var postedWorkouts: Set<WorkoutSource> {
        (savedHome?.postedWorkouts ?? []).union(pending.compactMap { $0.draft.workout?.source })
    }
}

extension Home {
    /// The workouts the member posted, among the check-ins this home holds: a workout is posted
    /// once, so whatever offers one to post leaves these out.
    public var postedWorkouts: Set<WorkoutSource> {
        Set(
            checkIns.compactMap { checkIn -> WorkoutSource? in
                guard checkIn.member == member, case .trained(let training) = checkIn.entry else { return nil }
                return training.workout?.source
            })
    }
}

extension TodayStore {
    /// `postedWorkouts` once the server's home is in hand; nil before (or while it can't be
    /// reached). The copy kept on the phone is from the last load, which may be from before a
    /// post, so it can't say a workout is still to post: the home's card waits for this.
    public var postedWorkoutsKnown: Set<WorkoutSource>? {
        phase == .current ? postedWorkouts : nil
    }
}
