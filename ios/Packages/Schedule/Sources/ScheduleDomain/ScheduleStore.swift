import Contracts
import Foundation
import Observation

/// The 出赛表's data: the weeks the member can open, the one shown with its board, and every
/// change saved as it is made. Screens bind to it; it never reads the clock itself, so tests
/// pass one.
///
/// A change shows at once and is saved right after; one made while a save is on its way goes
/// out once that save answers, so the server ends on the last change. When a save fails the
/// week goes back to what the server has, and `failure` says why.
@MainActor @Observable
public final class ScheduleStore {
    /// Where loading stands.
    public enum Phase: Equatable, Sendable {
        case loading
        /// The weeks shown are the server's.
        case ready
        /// The server couldn't be reached; whatever was loaded before still shows.
        case offline
        case signedOut
    }

    /// How many weeks back the chips reach at most, however long ago the member joined.
    public static let maxPastWeeks = 8
    /// How many sports the picks under the poster offer before 更多.
    public static let suggestedSportCount = 5

    public private(set) var phase = Phase.loading
    public private(set) var profile: ScheduleProfile?
    /// The Monday of the week shown.
    public private(set) var shownWeek: LocalDay?
    /// The shown week's plan as it is being edited.
    public private(set) var board: WeekBoard?
    /// Every day the member ever trained, once loaded.
    public private(set) var lifetimeTrainedDays: Int?
    /// Why the last save didn't go through; nil once one does.
    public private(set) var failure: ScheduleError?
    /// Weeks as the server last sent them, with every plan save it answered folded in; the
    /// plan being edited lives on `board` until its save goes through. The 饮食小目标 show here at
    /// once, before their save answers.
    private var sheets: [LocalDay: WeekSheet] = [:]
    /// Each week's 饮食小目标 as the server holds them, for a failed save to go back to.
    private var savedFuel: [LocalDay: [FuelGoal]] = [:]
    /// Weeks with a change waiting while a save of theirs is on its way.
    private var planSaves: [LocalDay: SaveState] = [:]

    private enum SaveState {
        case running
        case runningWithMore
    }

    private let backend: any ScheduleBackend
    private let now: @Sendable () -> Date

    public init(backend: any ScheduleBackend, now: @escaping @Sendable () -> Date) {
        self.backend = backend
        self.now = now
    }

    // MARK: - Reading

    /// The member's day now, in their profile's time zone, with the 3am grace.
    public var today: LocalDay? {
        profile.map { LocalDay(at: now(), in: $0.timeZone) }
    }

    /// The weeks the chips offer, oldest first: back to the week the member joined (at most
    /// `maxPastWeeks`), this week, then next week.
    public var weeks: [LocalDay] {
        guard let profile, let today else { return [] }
        let thisWeek = today.weekStart
        let back = (1...Self.maxPastWeeks).map { thisWeek.adding(days: -7 * $0) }.filter { $0 >= profile.firstWeek }
        return back.reversed() + [thisWeek, thisWeek.adding(days: 7)]
    }

    /// The week shown, with the board's days; nil until it has loaded.
    public var sheet: WeekSheet? {
        guard let shownWeek, var sheet = sheets[shownWeek] else { return nil }
        if let board { sheet.plan = board.days }
        return sheet
    }

    /// The sports the picks under the poster offer: the shown week's, then this week's, then
    /// a few common ones, without repeats.
    public var suggestedActivities: [Activity] {
        var seen: [Activity] = []
        let thisWeek = today.flatMap { sheets[$0.weekStart]?.plan } ?? []
        for day in (board?.days ?? []) + thisWeek {
            if case .train(let activity?) = day, !seen.contains(activity) { seen.append(activity) }
        }
        for sport in [Sport.run, .strength, .yoga, .swim, .tennis] where !seen.contains(.sport(sport)) {
            seen.append(.sport(sport))
        }
        return Array(seen.prefix(Self.suggestedSportCount))
    }

    /// From now until next week starts, at midnight on the member's Monday.
    public var untilNextWeek: Countdown? {
        guard let profile, let today else { return nil }
        return Countdown(from: now(), until: today.weekStart.adding(days: 7), in: profile.timeZone)
    }

    // MARK: - Loading

    /// Loads who the member is, their lifetime count and this week, and shows this week.
    public func load() async {
        do {
            profile = try await backend.profile()
            phase = .ready
        } catch .signedOut {
            phase = .signedOut
            return
        } catch {
            phase = .offline
            return
        }
        let start = shownWeek ?? today?.weekStart
        if let start { await show(start) }
        lifetimeTrainedDays = try? await backend.trainedDays()
    }

    /// Shows a week: the copy loaded before at once, then the server's.
    public func show(_ weekStart: LocalDay) async {
        if shownWeek != weekStart {
            shownWeek = weekStart
            board = sheets[weekStart].flatMap(makeBoard)
        }
        do {
            let fresh = try await backend.week(starting: weekStart)
            sheets[weekStart] = fresh
            savedFuel[weekStart] = fresh.fuel
            // A change made while it loaded stays; it is on its way to the server.
            guard shownWeek == weekStart, planSaves[weekStart] == nil else { return }
            board = makeBoard(fresh)
            phase = .ready
        } catch .signedOut {
            phase = .signedOut
        } catch {
            phase = .offline
        }
    }

    private func makeBoard(_ sheet: WeekSheet) -> WeekBoard? {
        today.map { WeekBoard(weekStart: sheet.weekStart, days: sheet.plan, today: $0) }
    }

    // MARK: - Planning

    /// Taps a day on the poster; a swap is saved.
    @discardableResult
    public func tap(_ index: Int) async -> WeekBoard.TapOutcome {
        guard var board else { return .locked }
        let outcome = board.tap(index)
        self.board = board
        if outcome == .swapped { await savePlan() }
        return outcome
    }

    /// Lets go of the selected or lifted day.
    public func release() {
        board?.release()
    }

    /// Makes the selected day a training day of `activity`, and saves it.
    public func pick(_ activity: Activity) async {
        guard var board, case .selected = board.focus else { return }
        board.pick(activity)
        self.board = board
        await savePlan()
    }

    /// Makes the selected day a rest day, in a week that hasn't started, and saves it.
    public func rest() async {
        guard var board, board.offersRest, case .selected = board.focus else { return }
        board.rest()
        self.board = board
        await savePlan()
    }

    /// Saves the board's days; while a save of the week is on its way, the next goes out once
    /// it answers, with the days as they are then.
    private func savePlan() async {
        guard let week = board?.weekStart, let sheet = sheets[week] else { return }
        if planSaves[week] != nil {
            planSaves[week] = .runningWithMore
            return
        }
        planSaves[week] = .running
        defer { planSaves[week] = nil }
        var sending = board?.days ?? sheet.plan
        while true {
            do {
                let plan = try await backend.savePlan(sending, weekStart: week)
                sheets[week]?.plan = plan
                failure = nil
            } catch {
                failure = error
                // Back to the last plan the server took; nothing else on the week moves.
                if board?.weekStart == week, let held = sheets[week]?.plan { board?.reset(to: held) }
                return
            }
            guard planSaves[week] == .runningWithMore, let days = board?.days, board?.weekStart == week else {
                return
            }
            planSaves[week] = .running
            sending = days
        }
    }

    // MARK: - 饮食小目标

    /// Whether the shown week's 饮食小目标 can change: only before the week starts.
    public var canEditFuel: Bool { board?.tense == .upcoming }

    /// Adds a goal to the shown week, or takes it off; a fourth is ignored. Saved at once.
    public func toggleFuel(_ goal: FuelGoal) async {
        guard canEditFuel, let week = shownWeek, var sheet = sheets[week] else { return }
        if let index = sheet.fuel.firstIndex(of: goal) {
            sheet.fuel.remove(at: index)
        } else if sheet.fuel.count < FuelGoal.maxCount {
            sheet.fuel.append(goal)
        } else {
            return
        }
        await saveFuel(sheet)
    }

    /// Adds a goal in the member's own words; throws when it isn't one line of 1 to 8
    /// characters.
    public func addFuel(typed text: String) async throws(ScheduleError) {
        let goal = try FuelGoal.own(typed: text)
        guard let week = shownWeek, sheets[week]?.fuel.contains(goal) == false else { return }
        await toggleFuel(goal)
    }

    private func saveFuel(_ sheet: WeekSheet) async {
        let week = sheet.weekStart
        sheets[week]?.fuel = sheet.fuel
        do {
            try await backend.saveFuel(sheet.fuel, weekStart: week)
            savedFuel[week] = sheet.fuel
            failure = nil
        } catch {
            failure = error
            sheets[week]?.fuel = savedFuel[week] ?? []
        }
    }
}

/// The time left until a moment, as the countdown card shows it.
public struct Countdown: Hashable, Sendable {
    public let days: Int
    public let hours: Int
    public let minutes: Int
    public let seconds: Int

    /// Until midnight at the start of `day` on the wall clock of `timeZone`; zero once it has
    /// passed.
    public init(from moment: Date, until day: LocalDay, in timeZone: TimeZone) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let start = calendar.date(from: DateComponents(year: day.year, month: day.month, day: day.day)) ?? moment
        let left = max(Int(start.timeIntervalSince(moment)), 0)
        days = left / 86_400
        hours = left % 86_400 / 3_600
        minutes = left % 3_600 / 60
        seconds = left % 60
    }
}
