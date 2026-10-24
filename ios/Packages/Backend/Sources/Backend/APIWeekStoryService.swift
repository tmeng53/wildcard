import APIContract
import Contracts
import DesignSystem
import Foundation
import RecapDomain

/// The Sunday 战报 from our API, as the story reads it.
public struct APIWeekStoryService: WeekStoryService {
    private let api: WildcardAPI

    public init(api: WildcardAPI) {
        self.api = api
    }

    /// The story, with the pages the API's story doesn't carry yet drawn from the week's summary,
    /// the squad's check-ins and the reader's plan. A page whose facts can't be read is left out;
    /// the story still opens.
    public func story(squad: SquadID, week monday: LocalDay) async throws(RecapError) -> WeekStory? {
        let story: WeekStory?
        do {
            story = try await api.weekStory(of: squad, week: monday)
        } catch {
            throw Self.reason(error)
        }
        // The facts are read only for a story that is out, which before Sunday's awards it isn't.
        guard let story else { return nil }
        guard let facts = await Self.facts(api: api, squad: squad, week: monday) else { return story }
        return story.filled(with: facts)
    }

    private static func facts(api: WildcardAPI, squad: SquadID, week monday: LocalDay) async -> WeekFacts? {
        async let summary = try? await api.weekSummaryWire(of: squad, week: monday)
        async let checkIns = try? await api.checkIns(of: squad, from: monday, through: monday.adding(days: 6))
        async let plan = try? await api.weeklyPlan(weekStart: monday)
        guard let summary = await summary, let plan = await plan else { return nil }
        return WeekFacts(summary, viewer: plan.member, checkIns: await checkIns ?? [], plan: plan.days)
    }

    public func nudge(squad: SquadID, week monday: LocalDay) async throws(RecapError) {
        do {
            try await api.nudgeWeekStory(of: squad, week: monday)
        } catch {
            throw Self.reason(error)
        }
    }

    private static func reason(_ error: APIError) -> RecapError {
        switch error {
        case .account: .signedOut
        case .refused(.squadNotJoined): .notInSquad
        default: .unavailable
        }
    }
}

extension WildcardAPI {
    /// The squad's story for the week starting `monday`; nil before the week's awards (Sunday 8pm
    /// Eastern), when there is nothing to open yet.
    public func weekStory(of squad: SquadID, week monday: LocalDay) async throws(APIError) -> WeekStory? {
        let wire: Components.Schemas.WeekStory
        do {
            wire = try await weekStoryWire(of: squad, week: monday)
        } catch .refused(.weekStoryNotReady) {
            return nil
        }
        guard let story = WeekStory(wire) else { throw .unreadableResponse }
        return story
    }
}

extension WeekFacts {
    init(_ summary: Components.Schemas.WeekSummary, viewer: MemberID, checkIns: [CheckIn], plan: [PlanDay]) {
        func winners(_ kind: String) -> [Components.Schemas.WeekAward.WinnersPayloadPayload] {
            summary.awards.first { $0.kind == kind }?.winners ?? []
        }
        func members(_ kind: String) -> [MemberID] {
            winners(kind).compactMap { UUID(uuidString: $0.member).map(MemberID.init) }
        }
        func count(_ stats: [Components.Schemas.WeekStat], _ kind: String) -> Int {
            stats.first { $0.kind == kind }?.value ?? 0
        }
        let best = winners("bestDisclaimer").first.flatMap { winner in
            winner.checkIn.flatMap(UUID.init(uuidString:)).map { Best(checkIn: CheckInID($0), reactions: winner.value) }
        }
        self.init(
            viewer: viewer, planCompleted: members("planCompleted"), crown: members("crown"), bestDisclaimer: best,
            squadTrained: count(summary.squadTotals.stats, "trainedDays"),
            squadPlanned: count(summary.squadTotals.stats, "plannedDays"),
            myPlanned: count(summary.me.stats, "plannedDays"),
            myReactionsReceived: count(summary.me.stats, "reactionsReceived"), checkIns: checkIns, plan: plan)
    }
}

extension WeekStory {
    /// What the API sends today: the titles (or that they're late) and the reader's hottest
    /// check-in. The other pages come once the API writes them.
    init?(_ wire: Components.Schemas.WeekStory) {
        let status: Status
        let squad: (id: String, name: String)
        let week: (from: String, to: String)
        let hottest: Components.Schemas.StoryHottest?
        let titles: [MemberTitles]
        switch wire {
        case .case1(let ready):
            status = .ready
            squad = (ready.squad.id, ready.squad.name)
            week = (ready.week.from, ready.week.to)
            hottest = ready.hottest
            var read: [MemberTitles] = []
            for member in ready.titles {
                guard let id = UUID(uuidString: member.member) else { return nil }
                read.append(
                    MemberTitles(
                        member: MemberID(id),
                        titles: member.titles.map {
                            MemberTitles.Title(title: $0.title, speech: $0.speech, move: AwardMove(wire: $0.move))
                        }))
            }
            titles = read
        case .case2(let pending):
            status = .pending
            squad = (pending.squad.id, pending.squad.name)
            week = (pending.week.from, pending.week.to)
            hottest = pending.hottest
            titles = []
        }
        guard let squadID = UUID(uuidString: squad.id), let monday = try? LocalDay(week.from),
            let sunday = try? LocalDay(week.to)
        else { return nil }
        var readHottest: Hottest?
        if let hottest {
            guard let read = Hottest(hottest) else { return nil }
            readHottest = read
        }
        self.init(
            status: status, squad: SquadID(squadID), squadName: squad.name, week: Week(monday: monday, sunday: sunday),
            titles: titles, hottest: readHottest)
    }
}

extension Hottest {
    init?(_ wire: Components.Schemas.StoryHottest) {
        guard let checkIn = UUID(uuidString: wire.checkIn), let day = try? LocalDay(wire.day),
            let kind = CheckInKind(rawValue: wire.kind.rawValue)
        else { return nil }
        // A sport of the member's own has no art of its own: the page shows just the kind.
        let sport = wire.sport.flatMap(Sport.init(rawValue:))
        self.init(
            checkIn: CheckInID(checkIn), day: day, kind: kind, sport: sport, words: wire.text ?? wire.caption,
            photos: wire.photos.compactMap { URL(string: $0.url) },
            reactions: wire.reactions.map { ReactionCount(emoji: $0.emoji, count: $0.count) })
    }
}
