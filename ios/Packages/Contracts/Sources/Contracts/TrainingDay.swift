/// One 练了 on the member's training record (训练记录 on 我): its day, sport and minutes, without
/// its words or photos.
public struct TrainingDay: Hashable, Sendable {
    public var id: CheckInID
    /// The day it counts for.
    public var day: LocalDay
    public var activity: Activity
    /// How long it took, when the member said.
    public var minutes: Int?

    public init(id: CheckInID, day: LocalDay, activity: Activity, minutes: Int?) {
        (self.id, self.day, self.activity, self.minutes) = (id, day, activity, minutes)
    }
}
