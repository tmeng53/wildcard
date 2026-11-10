#if os(iOS)
import CheckInDomain
import Contracts
import DesignSystem
import HealthDomain

/// Apple Health on 今天: the home's card and a new 训练's chips.
extension TodayModel {
    /// Today's workouts in Health, newest first, with those posted already marked; empty when
    /// Health isn't connected.
    var todaysWorkouts: [TodaysWorkout] {
        guard let health, health.isConnected, let day = store.day else { return [] }
        return health.today(day, in: timeZone, posted: store.postedTrainings)
    }

    /// The workout the home's card offers: today's newest not posted yet (a 训练 of its sport covers
    /// it, see `PostedTraining`) or put away. None until the server's home is in hand, since the
    /// copy kept on the phone may be from before a post.
    var workoutToPost: ImportedWorkout? {
        guard let health, health.isConnected, let day = store.day, let posted = store.postedTrainingsKnown else {
            return nil
        }
        return health.today(day, in: timeZone, posted: posted).newestToPost(skipping: health.putAway)
    }

    /// Takes the home card's workout off it; 打卡 › 训练 still offers it.
    func putAway(_ workout: ImportedWorkout) { health?.putAway(workout.id) }

    /// The compose page for a new post of `kind`; a 训练 from the home's card starts from `workout`.
    func newPost(_ kind: CheckInKind, from workout: ImportedWorkout?) -> ComposeModel {
        let given: [PreparedPhoto] = if case .provided(let photos) = photoSource { photos } else { [] }
        let model = ComposeModel(
            kind: kind, purpose: .new(shareSquad: shareSquad), photos: given.map(ComposedPhoto.new),
            postableDays: store.postableDays, suggestedActivity: suggestedActivity,
            recentActivities: recentActivities, healthWorkouts: kind == .trained ? todaysWorkouts : [],
            sharing: health?.sharing ?? HealthSharing(),
            save: { [weak self] model in
                await self?.post(model.draft, inFeed: model.inFeed, on: model.day) ?? false
            },
            close: { [weak self] in self?.cancel() })
        if kind == .trained, let workout { model.pick(workout) }
        return model
    }
}
#endif
