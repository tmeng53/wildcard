import APIContract
import Contracts
import Foundation
import ScheduleDomain

/// 出赛表 over our API: the member's weekly plans with their 饮食小目标, the days they checked
/// in, the titles the weekly awards gave them and, for this week, their squad's count.
public struct APIScheduleBackend: ScheduleBackend {
    private let api: WildcardAPI
    private let now: @Sendable () -> Date

    /// `now` says which week is this week, on the member's own clock.
    public init(api: WildcardAPI, now: @escaping @Sendable () -> Date = Date.init) {
        (self.api, self.now) = (api, now)
    }

    public func profile() async throws(ScheduleError) -> ScheduleProfile {
        try await schedule { () throws(APIError) in
            let profile = try await api.me().profile
            let timeZone = profile?.timeZone ?? .current
            let thisWeek = LocalDay(at: now(), in: timeZone).weekStart
            let plan = try await api.weeklyPlanWire(weekStart: thisWeek)
            let firstWeek = try plan.firstWeek.map { text throws(APIError) in try day(text) } ?? thisWeek
            return ScheduleProfile(
                nickname: profile?.character?.nickname.text ?? "", timeZone: timeZone, firstWeek: firstWeek,
                look: profile?.character?.look)
        }
    }

    public func week(starting weekStart: LocalDay) async throws(ScheduleError) -> WeekSheet {
        try await schedule { () throws(APIError) in
            let member = try await api.me()
            let thisWeek = LocalDay(at: now(), in: member.profile?.timeZone ?? .current).weekStart
            let wire = try await api.weeklyPlanWire(weekStart: weekStart)
            let plan = try api.read { () throws(ContractsError) in try WeeklyPlan(wire) }
            let checkIns = try await api.myCheckIns(from: weekStart, through: weekStart.adding(days: 6))
            let squad = try await api.mySquads().first
            // The squad's count shows on this week; the titles on a week that is over.
            let squadCount =
                if let squad, weekStart == thisWeek {
                    try await api.today(of: squad.id).squadWeek
                } else {
                    WeekCount?.none
                }
            let titles =
                if let squad, weekStart < thisWeek {
                    try await self.titles(of: member.id, in: squad.id, weekStart: weekStart)
                } else {
                    [AwardTitle]()
                }
            do {
                return try WeekSheet(
                    weekStart: weekStart, plan: plan.days, marks: Self.marks(of: checkIns, weekStart: weekStart),
                    titles: titles,
                    squad: squadCount.map { SquadCount(trained: $0.trainedDays, planned: $0.plannedDays) },
                    fuel: try wire.fuelGoals.map(FuelGoal.init))
            } catch {
                throw .unreadableResponse
            }
        }
    }

    public func savePlan(_ days: [PlanDay], weekStart: LocalDay) async throws(ScheduleError) -> [PlanDay] {
        try await schedule { () throws(APIError) in try await api.save(days, weekStart: weekStart).days }
    }

    public func saveFuel(_ goals: [FuelGoal], weekStart: LocalDay) async throws(ScheduleError) {
        try await schedule { () throws(APIError) in
            try await api.saveFuelGoalsWire(goals.map(\.wire), weekStart: weekStart)
        }
    }

    public func trainedDays() async throws(ScheduleError) -> Int {
        try await schedule { () throws(APIError) in try await api.checkInTotals().trainedDays }
    }

    // MARK: - Private

    /// The member's titles in the squad's story of a week; none until they are written. The
    /// titles only decorate the poster, so a story that can't be read leaves them off rather
    /// than the week; a signed-out member still fails.
    private func titles(of member: MemberID, in squad: SquadID, weekStart: LocalDay) async throws(APIError)
        -> [AwardTitle]
    {
        let story: Components.Schemas.WeekStory
        do {
            story = try await api.weekStoryWire(of: squad, weekStart: weekStart)
        } catch .account(let error) {
            throw .account(error)
        } catch {
            return []
        }
        guard case .case1(let ready) = story else { return [] }
        let mine = ready.titles.first { UUID(uuidString: $0.member).map(MemberID.init) == member }
        return mine?.titles.map { AwardTitle(title: $0.title, speech: $0.speech) } ?? []
    }

    /// How each day of the week went: a 练了 over a 请假条, Monday first.
    static func marks(of checkIns: [CheckIn], weekStart: LocalDay) -> [DayMark] {
        (0..<WeeklyPlan.dayCount).map { offset in
            let day = checkIns.filter { $0.day == weekStart.adding(days: offset) }
            if day.contains(where: { if case .trained = $0.entry { true } else { false } }) { return .trained }
            if day.contains(where: { if case .disclaimer = $0.entry { true } else { false } }) { return .disclaimer }
            return .none
        }
    }

    private func day(_ text: String) throws(APIError) -> LocalDay {
        try api.read { () throws(ContractsError) in try LocalDay(text) }
    }

    private func schedule<T>(_ call: () async throws(APIError) -> T) async throws(ScheduleError) -> T {
        do {
            return try await call()
        } catch {
            throw ScheduleError(error)
        }
    }
}

extension ScheduleError {
    /// What a failed API call means for the 出赛表.
    init(_ error: APIError) {
        self =
            switch error {
            case .unavailable: .notSent
            case .account(.signedOut), .account(.credentialRejected), .account(.canceled): .signedOut
            case .account: .notSent
            case .refused(.weekClosed): .weekOver
            case .refused(.planDayStarted): .dayStarted
            case .refused(.restDaysFixed): .restDaysFixed
            case .refused, .unreadableResponse: .refused
            }
    }
}

extension FuelGoal {
    init(_ wire: Components.Schemas.FuelGoalsPayload) throws(ScheduleError) {
        switch wire {
        case .case1(let suggested):
            guard let suggestion = FuelSuggestion(rawValue: suggested.suggestion.rawValue) else { throw .refused }
            self = .suggested(suggestion)
        case .case2(let own):
            self = try .own(typed: own.text)
        }
    }

    var wire: Components.Schemas.FuelGoalsPayload {
        switch self {
        case .suggested(let suggestion):
            .case1(.init(kind: .suggested, suggestion: suggestion.wire))
        case .own(let text):
            .case2(.init(kind: .own, text: text))
        }
    }
}

extension FuelSuggestion {
    var wire: Components.Schemas.FuelGoalsPayload.Case1Payload.SuggestionPayload {
        switch self {
        case .water: .water
        case .cookAtHome: .cookAtHome
        case .veggies: .veggies
        case .lessBubbleTea: .lessBubbleTea
        case .breakfast: .breakfast
        case .earlyDinner: .earlyDinner
        }
    }
}
