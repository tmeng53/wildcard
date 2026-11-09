import Contracts
import Foundation

/// The server, as the 出赛表 needs it. The app passes the API adapter (`Backend`), or an
/// in-memory member for previews and UI tests. Every call fails with a `ScheduleError`;
/// `.notSent` means trying again later is safe.
public protocol ScheduleBackend: Sendable {
    /// Who the poster is for and which weeks they can look back on.
    func profile() async throws(ScheduleError) -> ScheduleProfile
    /// One week: its plan, how each day went and its titles.
    func week(starting weekStart: LocalDay) async throws(ScheduleError) -> WeekSheet
    /// Replaces a week's plan and answers with the plan saved. Safe to repeat.
    func savePlan(_ days: [PlanDay], weekStart: LocalDay) async throws(ScheduleError) -> [PlanDay]
    /// Replaces a week's 饮食小目标. Safe to repeat.
    func saveFuel(_ goals: [FuelGoal], weekStart: LocalDay) async throws(ScheduleError)
    /// The member's typical week (我的每周计划): seven days, Monday first, which every week not
    /// changed for itself follows.
    func template() async throws(ScheduleError) -> [PlanDay]
    /// Replaces the typical week; the weeks from next week on follow it. Safe to repeat.
    func saveTemplate(_ days: [PlanDay]) async throws(ScheduleError)
}

/// The member as the 出赛表 shows them.
public struct ScheduleProfile: Hashable, Sendable {
    /// Under their character, and on the poster beside the dates.
    public let nickname: String
    /// Their profile's time zone: their days, and when next week starts.
    public let timeZone: TimeZone
    /// The Monday of the week they joined: the earliest week to look back on.
    public let firstWeek: LocalDay
    /// The Monday of the week their squad was made, its W1; nil outside a squad and from older
    /// servers.
    public let squadFirstWeek: LocalDay?
    /// Their character's look, cheering in the poster's corner; nil until they have one.
    public let look: CharacterLook?

    public init(
        nickname: String, timeZone: TimeZone, firstWeek: LocalDay, squadFirstWeek: LocalDay? = nil,
        look: CharacterLook? = nil
    ) {
        (self.nickname, self.timeZone, self.firstWeek, self.look) = (nickname, timeZone, firstWeek.weekStart, look)
        self.squadFirstWeek = squadFirstWeek?.weekStart
    }

    /// The week's number on the poster and its chip: the squad's week, its first being W1, so
    /// the whole squad shows the same number (Tracy, 2026-11-09); the member's own count
    /// outside a squad.
    public func weekNumber(of weekStart: LocalDay) -> Int {
        weekStart.weekNumber(since: squadFirstWeek ?? firstWeek)
    }

    /// Whether chips for `weeks` (oldest first) start with 还未入队, greyed: they joined after
    /// their squad's W1 and the chips reach back to the week they joined.
    public func startsWithNotYetJoined(_ weeks: [LocalDay]) -> Bool {
        guard let squadFirstWeek, squadFirstWeek < firstWeek else { return false }
        return weeks.first == firstWeek
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
    /// A 饮食小目标 of the member's own must be one line of 1 to 8 characters.
    case invalidFuelGoal
    /// The server said no for a reason this build doesn't know. Trying again won't help.
    case refused
}
