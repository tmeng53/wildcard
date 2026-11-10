import Contracts
import HealthDomain

extension Home {
    /// The member's 训练 among the check-ins this home holds, which what is offered from Health
    /// is checked against: a session is posted once.
    public var postedTrainings: [PostedTraining] {
        checkIns.compactMap { checkIn -> PostedTraining? in
            guard checkIn.member == member, case .trained(let training) = checkIn.entry else { return nil }
            return PostedTraining(
                activity: training.activity, day: checkIn.day, madeAt: checkIn.createdAt, workout: training.workout)
        }
    }
}

extension TodayStore {
    /// The member's 训练, saved or still waiting to go out, each once: a post the server has
    /// saved may still be in the outbox for a moment.
    public var postedTrainings: [PostedTraining] {
        let saved = Set(savedHome?.checkIns.map(\.id) ?? [])
        return (savedHome?.postedTrainings ?? [])
            + pending.compactMap { post -> PostedTraining? in
                guard post.member == savedHome?.member, !saved.contains(post.id),
                    case .trained(let activity, _, let body) = post.draft
                else { return nil }
                return PostedTraining(activity: activity, day: post.day, madeAt: post.createdAt, workout: body.workout)
            }
    }

    /// `postedTrainings` once the server's home is in hand; nil before (or while it can't be
    /// reached). The copy kept on the phone is from the last load, which may be from before a
    /// post, so it can't say a workout is still to post: the home's card waits for this.
    public var postedTrainingsKnown: [PostedTraining]? {
        phase == .current ? postedTrainings : nil
    }
}
