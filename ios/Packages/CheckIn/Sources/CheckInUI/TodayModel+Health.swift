#if os(iOS)
import CheckInDomain
import Contracts
import DesignSystem
import HealthDomain

/// Apple Health on 今天: the home's card, a new 训练's chips and the 打卡 a widget opens.
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

    /// Opens the check-in kinds, as the 打卡 button does: the 6pm push's 我去发一个 and a widget's
    /// plain 打卡 land here.
    public func openCheckIn() {
        if step == .scene { isBurstOpen = true }
    }

    /// A home screen widget's 打卡: the 训练 page started from `source`, as the home's card starts
    /// it, so nothing goes out until the member sends it. A workout Health synced since the app
    /// last read it, or one tapped before the home loaded on a cold launch, opens once they are
    /// read; one posted or gone by then opens the kinds, as the widget's plain 打卡 does.
    public func openCheckIn(posting source: WorkoutSource) async {
        askedToPost = source
        if openAskedWorkout(finally: false) { return }
        await health?.refresh()
        // Before the home is read, `load()` finishes it.
        openAskedWorkout(finally: store.day != nil)
    }

    /// Opens the page for the workout a widget asked for once it is among today's, or, `finally`,
    /// the kinds without it. Only from the scene: a page already open stays as it is.
    @discardableResult
    func openAskedWorkout(finally: Bool) -> Bool {
        guard let source = askedToPost, store.day != nil else { return false }
        let offered = todaysWorkouts.first { $0.id == source && !$0.isPosted }?.imported
        guard offered != nil || finally else { return false }
        askedToPost = nil
        guard step == .scene else { return true }
        if let offered {
            isBurstOpen = false
            pick(.trained, workout: offered)
        } else {
            openCheckIn()
        }
        return true
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
