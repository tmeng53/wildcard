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
        return health.today(day, in: timeZone, posted: store.postedWorkouts)
    }

    /// The workout the home's card offers: today's newest not posted or put away yet.
    var workoutToPost: ImportedWorkout? { todaysWorkouts.newestToPost(skipping: health?.putAway ?? []) }

    /// Takes the home card's workout off it; 打卡 › 训练 still offers it.
    func putAway(_ workout: ImportedWorkout) { health?.putAway(workout.id) }

    /// A new workout's reminder, tapped: its compose page with the workout picked, once Health
    /// was read again; the kinds to pick from once it is posted or not in Health any more. A post
    /// already being written stays.
    public func compose(_ workout: WorkoutSource) async {
        await health?.refresh()
        guard step == .scene else { return }
        if let found = todaysWorkouts.first(where: { $0.id == workout }), !found.isPosted {
            pick(.trained, workout: found.imported)
        } else {
            openCheckIn()
        }
    }

    /// Sends the posts made from a new workout's reminder that couldn't go out from there, from
    /// the app's own outbox. Taken only once the home is here, so none is dropped before it is.
    public func adoptQuickPosts(_ take: () async -> [PendingCheckIn]) async {
        guard store.home != nil else { return }
        await store.adopt(await take())
    }

    /// The compose page for a new post of `kind`; a 训练 from the home's card starts from `workout`.
    func newPost(_ kind: CheckInKind, from workout: ImportedWorkout?) -> ComposeModel {
        let given: [PreparedPhoto] = if case .provided(let photos) = photoSource { photos } else { [] }
        let model = ComposeModel(
            kind: kind, purpose: .new(shareSquad: shareSquad), photos: given.map(ComposedPhoto.new),
            postableDays: store.postableDays, suggestedActivity: suggestedActivity,
            recentActivities: recentActivities, healthWorkouts: kind == .trained ? todaysWorkouts : [],
            sharing: health?.sharing ?? HealthSharing(),
            save: { [weak self] model in
                await self?.post(model.draft, shared: model.isShared, on: model.day) ?? false
            },
            close: { [weak self] in self?.cancel() })
        if kind == .trained, let workout { model.pick(workout) }
        return model
    }
}
#endif
