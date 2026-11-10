import Contracts
import HealthDomain

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

extension Home {
    /// The member's 训练 on `day` posted by hand, without a workout from Health: each counts
    /// as posting one of that day's Health workouts of its sport.
    public func trainedByHand(on day: LocalDay) -> [HandPostedTraining] {
        checkIns.compactMap { checkIn -> HandPostedTraining? in
            guard checkIn.member == member, checkIn.day == day, case .trained(let training) = checkIn.entry,
                training.workout == nil
            else { return nil }
            return HandPostedTraining(activity: training.activity, madeAt: checkIn.createdAt)
        }
    }
}

extension TodayStore {
    /// The member's 训练 on `day` posted by hand, saved or still waiting to go out, each once:
    /// a post the server has saved may still be in the outbox for a moment.
    public func trainedByHand(on day: LocalDay) -> [HandPostedTraining] {
        let saved = Set(savedHome?.checkIns.map(\.id) ?? [])
        return (savedHome?.trainedByHand(on: day) ?? [])
            + pending.compactMap { post -> HandPostedTraining? in
                guard post.member == savedHome?.member, post.day == day, !saved.contains(post.id),
                    case .trained(let activity, _, let body) = post.draft, body.workout == nil
                else { return nil }
                return HandPostedTraining(activity: activity, madeAt: post.createdAt)
            }
    }
}
