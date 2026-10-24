import Contracts
import Foundation

/// The server, as the 出赛表 needs it. The app passes the API adapter (`Backend`), or an
/// in-memory member for previews and UI tests. Every call fails with a `ScheduleError`;
/// `.notSent` means trying again later is safe.
public protocol ScheduleBackend: Sendable {
    /// Who the poster is for and which weeks they can look back on.
    func profile() async throws(ScheduleError) -> ScheduleProfile
    /// One week: its plan, how each day went, its titles and the squad's count.
    func week(starting weekStart: LocalDay) async throws(ScheduleError) -> WeekSheet
    /// Replaces a week's plan and answers with the plan saved. Safe to repeat.
    func savePlan(_ days: [PlanDay], weekStart: LocalDay) async throws(ScheduleError) -> [PlanDay]
    /// Replaces a week's 饮食小目标. Safe to repeat.
    func saveFuel(_ goals: [FuelGoal], weekStart: LocalDay) async throws(ScheduleError)
    /// Every day the member ever trained (一共练了 N 天).
    func trainedDays() async throws(ScheduleError) -> Int
}

/// The member as the 出赛表 shows them.
public struct ScheduleProfile: Hashable, Sendable {
    /// Under their character, and on the poster beside the dates.
    public let nickname: String
    /// Their profile's time zone: their days, and when next week starts.
    public let timeZone: TimeZone
    /// The Monday of the week they joined: the earliest week to look back on.
    public let firstWeek: LocalDay
    /// Their character's look, cheering in the poster's corner; nil until they have one.
    public let look: CharacterLook?

    public init(nickname: String, timeZone: TimeZone, firstWeek: LocalDay, look: CharacterLook? = nil) {
        (self.nickname, self.timeZone, self.firstWeek, self.look) = (nickname, timeZone, firstWeek.weekStart, look)
    }
}

/// Why loading or saving the 出赛表 didn't work. Each case is something the screen can act on,
/// always in friendly words.
public enum ScheduleError: Error, Equatable, Sendable {
    /// The server couldn't be reached; nothing changed, and trying again is safe.
    case notSent
    /// The member isn't signed in any more.
    case signedOut
    /// The week is over, so its plan stays as it was.
    case weekOver
    /// A day that has started can't change any more.
    case dayStarted
    /// This week keeps its number of rest days; they only move.
    case restDaysFixed
    /// A 饮食小目标 of the member's own must be one line of 1 to 8 characters.
    case invalidFuelGoal
    /// The server said no for a reason this build doesn't know. Trying again won't help.
    case refused
}
