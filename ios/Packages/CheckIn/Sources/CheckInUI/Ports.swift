import CheckInDomain
import Contracts
import DesignSystem

/// What the 今天 screen shows about the squad and the member's day.
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

/// Where check-ins go and the board comes from. The app passes an adapter: the API client
/// once it lands, `InMemoryCheckInService` until then.
public protocol CheckInService: Sendable {
    func board() async throws(CheckInError) -> TodayBoard
    /// Posts the draft and returns the board with it counted.
    func post(_ draft: CheckInDraft) async throws(CheckInError) -> TodayBoard
}

/// What the 免责声明 writer came back with.
public enum DisclaimerSuggestions: Hashable, Sendable {
    /// Up to three lines to pick from, each at most `Disclaimer.maxLength`.
    case drafts([String])
    /// The reason touched something the writer won't joke about (self-harm among them); the
    /// author sees a care line instead, and nobody else sees anything.
    case blocked
}

/// Turns the member's reason into 免责声明 lines. The AI writer is an adapter behind this; a
/// writer that fails returns dice lines instead, so the member never sees an error.
public protocol DisclaimerWriter: Sendable {
    func suggestions(for reason: String) async -> DisclaimerSuggestions
}
