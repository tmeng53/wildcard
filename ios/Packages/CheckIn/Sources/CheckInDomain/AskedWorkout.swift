import Contracts
import HealthDomain

/// What a home screen widget's 打卡 on a Health workout opens: the 训练 page started from it while
/// it is still among today's and not posted, judged only from the server's home (the copy kept on
/// the phone may be from before a post); else, once the app knows all it will, the kinds, as the
/// widget's plain 打卡 does.
public enum AskedWorkout: Hashable, Sendable {
    case open(ImportedWorkout)
    /// The check-in kinds: the workout was posted or is gone, or the server couldn't be read.
    case kinds
    /// Not known yet: the server's home or Health is still being read.
    case wait

    /// - Parameters:
    ///   - todays: today's Health workouts marked against the server's home; nil until it is read.
    ///   - finally: whether the home and Health have been read as far as they will be.
    public static func resolve(_ source: WorkoutSource, among todays: [TodaysWorkout]?, finally: Bool) -> Self {
        if let found = todays?.first(where: { $0.id == source && !$0.isPosted }) { return .open(found.imported) }
        return finally ? .kinds : .wait
    }
}
