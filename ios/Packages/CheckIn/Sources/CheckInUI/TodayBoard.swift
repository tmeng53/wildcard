import CheckInDomain
import Contracts
import DesignSystem

/// What the 今天 screen's card shows about the squad and the member's day, read from
/// `TodayStore`'s home.
public struct TodayBoard: Hashable, Sendable {
    public var squadName: String
    public var scene: SceneTheme
    /// The ISO week of the year, as in 「第 42 周」.
    public var weekNumber: Int
    public var progress: SquadWeekProgress
    /// Members who trained today, for 「今天 3 人练了」.
    public var trainedToday: Int
    public var myStatus: TrainingStatus
    /// The sport a new 练了 starts with, until it is picked from the cover photo.
    public var lastActivity: Activity

    public init(
        squadName: String, scene: SceneTheme, weekNumber: Int, progress: SquadWeekProgress, trainedToday: Int,
        myStatus: TrainingStatus, lastActivity: Activity
    ) {
        self.squadName = squadName
        self.scene = scene
        self.weekNumber = weekNumber
        self.progress = progress
        self.trainedToday = trainedToday
        self.myStatus = myStatus
        self.lastActivity = lastActivity
    }
}
