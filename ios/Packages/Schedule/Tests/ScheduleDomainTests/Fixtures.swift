import Contracts
import Foundation

@testable import ScheduleDomain

enum Fixtures {
    static func day(_ text: String) -> LocalDay {
        guard let day = try? LocalDay(text) else { fatalError("\(text) is not a day") }
        return day
    }

    /// Run, tennis, rest, strength, run, rest, tennis.
    static let plan: [PlanDay] = [
        .train(.sport(.run)), .train(.sport(.tennis)), .rest, .train(.sport(.strength)), .train(.sport(.run)), .rest,
        .train(.sport(.tennis)),
    ]

    static let losAngeles = TimeZone(identifier: "America/Los_Angeles") ?? .gmt

    /// Noon on `day` in Los Angeles.
    static func noon(_ text: String) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = losAngeles
        let day = day(text)
        return calendar.date(from: DateComponents(year: day.year, month: day.month, day: day.day, hour: 12)) ?? .now
    }
}

/// A server in memory that answers what each test sets, and records saves.
actor FakeBackend: ScheduleBackend {
    var profileResult: Result<ScheduleProfile, ScheduleError>
    var sheets: [LocalDay: WeekSheet] = [:]
    var saveError: ScheduleError?
    private(set) var savedPlans: [[PlanDay]] = []
    private(set) var savedFuel: [[FuelGoal]] = []
    /// While set, a save waits until `finishSave()`.
    private var holdsSaves = false
    private var held: [CheckedContinuation<Void, Never>] = []

    init(firstWeek: LocalDay = Fixtures.day("2026-09-07")) {
        profileResult = .success(
            ScheduleProfile(nickname: "Tracy", timeZone: Fixtures.losAngeles, firstWeek: firstWeek))
    }

    func set(_ sheet: WeekSheet) { sheets[sheet.weekStart] = sheet }
    func failSaves(with error: ScheduleError?) { saveError = error }
    func failProfile(with error: ScheduleError) { profileResult = .failure(error) }
    func holdSaves() { holdsSaves = true }

    func finishSave() {
        holdsSaves = false
        held.forEach { $0.resume() }
        held = []
    }

    func profile() async throws(ScheduleError) -> ScheduleProfile { try profileResult.get() }

    func week(starting weekStart: LocalDay) async throws(ScheduleError) -> WeekSheet {
        if let sheet = sheets[weekStart] { return sheet }
        return try WeekSheet(weekStart: weekStart, plan: Fixtures.plan, marks: Array(repeating: .none, count: 7))
    }

    func savePlan(_ days: [PlanDay], weekStart: LocalDay) async throws(ScheduleError) -> [PlanDay] {
        savedPlans.append(days)
        if holdsSaves { await withCheckedContinuation { held.append($0) } }
        if let saveError { throw saveError }
        sheets[weekStart]?.plan = days
        return days
    }

    func saveFuel(_ goals: [FuelGoal], weekStart: LocalDay) async throws(ScheduleError) {
        savedFuel.append(goals)
        if let saveError { throw saveError }
    }

    func trainedDays() async throws(ScheduleError) -> Int { 46 }
}
