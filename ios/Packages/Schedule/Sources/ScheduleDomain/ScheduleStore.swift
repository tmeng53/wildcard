import Contracts
import Foundation
import Observation

/// The 出赛表's data: the weeks the member can open, the one shown with its board, and every
/// change saved as it is made. Screens bind to it; it never reads the clock itself, so tests
/// pass one.
///
/// A change shows at once and is saved right after. Each week saves one thing at a time: a
/// change made while a save is on its way goes out once it answers, whichever week is shown by
/// then, so the server ends on the last change. When a save fails that part of the week (its
/// plan or its 饮食小目标) goes back to what the server has, and `failure` says why.
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
    /// Why a part of the last change didn't go through; nil once a change goes through whole.
    public private(set) var failure: ScheduleError?
    /// Weeks as the server holds them: as last sent, with every save it took folded in.
    private var sheets: [LocalDay: WeekSheet] = [:]
    /// Weeks with changes the server hasn't taken yet, as the member sees them.
    private var drafts: [LocalDay: WeekSheet] = [:]
    /// Weeks with a save on its way.
    private var saving: Set<LocalDay> = []
    /// Counts each week's changes, so a load that began before one never replaces it.
    private var changes: [LocalDay: Int] = [:]

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
        guard let shownWeek, var sheet = drafts[shownWeek] ?? sheets[shownWeek] else { return nil }
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
            board = (drafts[weekStart] ?? sheets[weekStart]).flatMap(makeBoard)
        }
        let changesBefore = changes[weekStart]
        do {
            let fresh = try await backend.week(starting: weekStart)
            // A change since it was asked for makes it stale, and while a save is on its way it
            // keeps the server's copy; the next load has it.
            guard changes[weekStart] == changesBefore, !saving.contains(weekStart) else { return }
            sheets[weekStart] = fresh
            // A change made while it loaded stays; it is on its way to the server.
            guard shownWeek == weekStart, drafts[weekStart] == nil else { return }
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

    /// Taps a day on the poster.
    @discardableResult
    public func tap(_ index: Int) async -> WeekBoard.TapOutcome {
        guard var board else { return .locked }
        let outcome = board.tap(index)
        self.board = board
        return outcome
    }

    /// Lets go of the selected day.
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

    /// Makes the selected day a rest day, any day but today, and saves it.
    public func rest() async {
        guard var board, board.offersRest else { return }
        board.rest()
        self.board = board
        await savePlan()
    }

    /// Takes the board's days into the week's draft and saves it.
    private func savePlan() async {
        guard let board, var draft = drafts[board.weekStart] ?? sheets[board.weekStart] else { return }
        draft.plan = board.days
        drafts[board.weekStart] = draft
        await save(board.weekStart)
    }

    // MARK: - 饮食小目标

    /// Whether the shown week's 饮食小目标 can change: this week's and later ones'.
    public var canEditFuel: Bool { board.map { $0.tense != .past } ?? false }

    /// Adds a goal to the shown week, or takes it off; a fourth is ignored. Saved at once.
    public func toggleFuel(_ goal: FuelGoal) async {
        guard canEditFuel, let week = shownWeek, var draft = drafts[week] ?? sheets[week] else { return }
        if let index = draft.fuel.firstIndex(of: goal) {
            draft.fuel.remove(at: index)
        } else if draft.fuel.count < FuelGoal.maxCount {
            draft.fuel.append(goal)
        } else {
            return
        }
        drafts[week] = draft
        await save(week)
    }

    /// Adds a goal in the member's own words; throws when it isn't one line of 1 to 8
    /// characters.
    public func addFuel(typed text: String) async throws(ScheduleError) {
        let goal = try FuelGoal.own(typed: text)
        guard shownWeek != nil, sheet?.fuel.contains(goal) == false else { return }
        await toggleFuel(goal)
    }

    // MARK: - Saving

    /// Sends the week's draft, one part at a time, until the server holds all of it; a save
    /// already on its way sends the rest once it answers. A part the server refuses goes back
    /// to the server's.
    private func save(_ week: LocalDay) async {
        changes[week, default: 0] += 1
        guard !saving.contains(week) else { return }
        saving.insert(week)
        defer { saving.remove(week) }
        var refused = false
        while let draft = drafts[week], let held = sheets[week] {
            if draft.plan != held.plan {
                do {
                    let plan = try await backend.savePlan(draft.plan, weekStart: week)
                    sheets[week]?.plan = plan
                    // The server's answer stands unless the member changed the plan meanwhile.
                    if drafts[week]?.plan == draft.plan {
                        drafts[week]?.plan = plan
                        if plan != draft.plan, board?.weekStart == week { board?.reset(to: plan) }
                    }
                } catch {
                    failure = error
                    refused = true
                    drafts[week]?.plan = held.plan
                    if board?.weekStart == week { board?.reset(to: held.plan) }
                }
            } else if draft.fuel != held.fuel {
                do {
                    try await backend.saveFuel(draft.fuel, weekStart: week)
                    sheets[week]?.fuel = draft.fuel
                } catch {
                    failure = error
                    refused = true
                    drafts[week]?.fuel = held.fuel
                }
            } else {
                drafts[week] = nil
                if !refused { failure = nil }
            }
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
