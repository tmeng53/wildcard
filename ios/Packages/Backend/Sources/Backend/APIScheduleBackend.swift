import APIContract
import Contracts
import Foundation
import ScheduleDomain

/// 出赛表 over our API: the member's weekly plans and their typical week
/// (我的每周计划), the days they checked in and the titles the weekly awards gave them.
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
            let squadFirstWeek = try plan.squadFirstWeek.map { text throws(APIError) in try day(text) }
            return ScheduleProfile(
                nickname: profile?.character?.nickname.text ?? "", timeZone: timeZone, firstWeek: firstWeek,
                squadFirstWeek: squadFirstWeek, look: profile?.character?.look)
        }
    }

    public func week(starting weekStart: LocalDay) async throws(ScheduleError) -> WeekSheet {
        try await schedule { () throws(APIError) in
            let member = try await api.me()
            let thisWeek = LocalDay(at: now(), in: member.profile?.timeZone ?? .current).weekStart
            let wire = try await api.weeklyPlanWire(weekStart: weekStart)
            let plan = try api.read { () throws(ContractsError) in try WeeklyPlan(wire) }
            let checkIns = try await api.myCheckIns(from: weekStart, through: weekStart.adding(days: 6))
            let squad = try await api.mySquad()
            // The week's scene and titles come from its 战报 once the week is over. This week
            // draws the squad's scene now until Sunday's 战报, after which that is next week's
            // pick, so it then wears its own (the gym's when it has no 战报, like a past week).
            // Next week wears its pick once made.
            let story: (titles: [AwardTitle], scene: SceneID?) =
                if let squad, weekStart < thisWeek {
                    try await self.story(of: member.id, in: squad.id, weekStart: weekStart)
                } else if let squad, weekStart == thisWeek {
                    try await thisWeekStory(of: member.id, in: squad.id, weekStart: weekStart)
                } else if let squad {
                    ([], try await pickedScene(of: squad.id, weekStart: weekStart))
                } else {
                    ([], nil)
                }
            do {
                return try WeekSheet(
                    weekStart: weekStart, plan: plan.days, marks: Self.marks(of: checkIns, weekStart: weekStart),
                    titles: story.titles, scene: story.scene)
            } catch {
                throw .unreadableResponse
            }
        }
    }

    public func savePlan(_ days: [PlanDay], weekStart: LocalDay) async throws(ScheduleError) -> [PlanDay] {
        try await schedule { () throws(APIError) in try await api.save(days, weekStart: weekStart).days }
    }

    public func template() async throws(ScheduleError) -> [PlanDay] {
        try await schedule { () throws(APIError) in try await api.planTemplate() }
    }

    public func saveTemplate(_ days: [PlanDay]) async throws(ScheduleError) {
        try await schedule { () throws(APIError) in try await api.saveTemplate(days) }
    }

    // MARK: - Private

    /// The member's titles in the squad's story of a week, none until they are written, and the
    /// scene the squad trained on. The story only decorates the poster, so one that can't be
    /// read leaves them off rather than the week; a signed-out member still fails.
    private func story(of member: MemberID, in squad: SquadID, weekStart: LocalDay) async throws(APIError)
        -> (titles: [AwardTitle], scene: SceneID?)
    {
        let story: Components.Schemas.WeekStory
        do {
            story = try await api.weekStoryWire(of: squad, week: weekStart)
        } catch .account(let error) {
            throw .account(error)
        } catch {
            return ([], nil)
        }
        switch story {
        case .case1(let ready):
            let mine = ready.titles.first { UUID(uuidString: $0.member).map(MemberID.init) == member }
            return (
                Self.awardTitles(mine?.titles ?? []),
                SceneID(rawValue: ready.sceneId)
            )
        case .case2(let pending):
            return ([], SceneID(rawValue: pending.sceneId))
        }
    }

    /// This week's story: none, so the squad's scene now, while picking is still open for this
    /// week; once Sunday's 战报 opened next week's pick, the week's own from its story.
    private func thisWeekStory(of member: MemberID, in squad: SquadID, weekStart: LocalDay) async throws(APIError)
        -> (titles: [AwardTitle], scene: SceneID?)
    {
        guard let open = try await squadScene(of: squad)?.week, open > weekStart else { return ([], nil) }
        let story = try await self.story(of: member, in: squad, weekStart: weekStart)
        return (story.titles, story.scene ?? .gym)
    }

    /// The scene picked for a week to come, once its pick is open (from Sunday's 战报) and made.
    private func pickedScene(of squad: SquadID, weekStart: LocalDay) async throws(APIError) -> SceneID? {
        guard let scene = try await squadScene(of: squad), scene.week == weekStart else { return nil }
        return scene.picked?.scene
    }

    /// The squad's scene route. Like the story, it only decorates the poster, so one that can't
    /// be read leaves it off; a signed-out member still fails.
    private func squadScene(of squad: SquadID) async throws(APIError) -> SquadScene? {
        do {
            return try await api.scene(of: squad)
        } catch .account(let error) {
            throw .account(error)
        } catch {
            return nil
        }
    }

    /// A member's titles in a story, each with its badge; the default badge from servers before
    /// the story sent one.
    static func awardTitles(_ titles: [Components.Schemas.StoryTitle]) -> [AwardTitle] {
        titles.map { AwardTitle(title: $0.title, speech: $0.speech, badge: $0.badge.map(TitleBadge.init) ?? .plain) }
    }

    /// How each day of the week went: a 练了 over a 请假条, Monday first, with every sport a
    /// day's 练了 logged, the latest last.
    static func marks(of checkIns: [CheckIn], weekStart: LocalDay) -> [DayMark] {
        (0..<WeeklyPlan.dayCount).map { offset in
            let day = checkIns.filter { $0.day == weekStart.adding(days: offset) }
            let trained = day.compactMap { checkIn -> (Timestamp, Activity)? in
                if case .trained(let training) = checkIn.entry { (checkIn.createdAt, training.activity) } else { nil }
            }
            if !trained.isEmpty { return .trained(trained.sorted { $0.0 < $1.0 }.map(\.1)) }
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
            case .refused, .unreadableResponse: .refused
            }
    }
}
