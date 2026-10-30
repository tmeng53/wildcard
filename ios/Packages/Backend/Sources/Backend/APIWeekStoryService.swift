import APIContract
import Contracts
import DesignSystem
import Foundation
import RecapDomain

/// The Sunday 战报 (每周战报) from our API, as it was frozen at the week's awards.
public struct APIWeekStoryService: WeekStoryService {
    private let api: WildcardAPI

    public init(api: WildcardAPI) {
        self.api = api
    }

    /// The squad's story for the week, as the API froze it at the week's awards: every page and
    /// the squad as it was then.
    public func story(squad: SquadID, week monday: LocalDay) async throws(RecapError) -> WeekStory? {
        do {
            return try await api.weekStory(of: squad, week: monday)
        } catch {
            throw Self.reason(error)
        }
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

extension WeekStory {
    /// Every page as the API froze it. The podium's 颁奖词 and moves are the champion's and the
    /// first side's first titles, once the titles are in.
    init?(_ wire: Components.Schemas.WeekStory) {
        switch wire {
        case .case1(let ready):
            var titles: [MemberTitles] = []
            for member in ready.titles {
                guard let id = UUID(uuidString: member.member) else { return nil }
                titles.append(
                    MemberTitles(
                        member: MemberID(id),
                        titles: member.titles.map {
                            MemberTitles.Title(title: $0.title, speech: $0.speech, move: AwardMove(wire: $0.move))
                        }))
            }
            self.init(
                status: .ready, titles: titles,
                frozen: Frozen(
                    squad: ready.squad, week: ready.week, scene: ready.scene.rawValue, members: ready.members,
                    podium: ready.podium, myWeek: ready.myWeek, hottest: ready.hottest, meals: ready.meals,
                    bestDisclaimer: ready.bestDisclaimer, ending: ready.ending))
        case .case2(let pending):
            self.init(
                status: .pending, titles: [],
                frozen: Frozen(
                    squad: pending.squad, week: pending.week, scene: pending.scene.rawValue,
                    members: pending.members, podium: pending.podium, myWeek: pending.myWeek,
                    hottest: pending.hottest, meals: pending.meals, bestDisclaimer: pending.bestDisclaimer,
                    ending: pending.ending))
        }
    }

    /// The pages both of the API's shapes carry: all but the titles.
    private struct Frozen {
        let squad: Components.Schemas.StorySquad
        let week: Components.Schemas.StoryWeek
        let scene: String
        let members: [Components.Schemas.StoryMember]
        let podium: Components.Schemas.StoryPodium?
        let myWeek: Components.Schemas.StoryMyWeek?
        let hottest: Components.Schemas.StoryHottest?
        let meals: Components.Schemas.StoryMeals?
        let bestDisclaimer: Components.Schemas.StoryBestDisclaimer?
        let ending: Components.Schemas.StoryEnding?
    }

    private init?(status: Status, titles: [MemberTitles], frozen: Frozen) {
        guard let squad = UUID(uuidString: frozen.squad.id), let monday = try? LocalDay(frozen.week.from),
            let sunday = try? LocalDay(frozen.week.to), let scene = SceneTheme(rawValue: frozen.scene),
            let squadmates = Self.squadmates(frozen.members)
        else { return nil }
        func first(_ member: MemberID) -> MemberTitles.Title? {
            titles.first { $0.member == member }?.titles.first
        }
        var podium: Podium?
        if let wire = frozen.podium {
            let sides = wire.sides.compactMap(Self.member)
            guard let champion = Self.member(wire.champion), sides.count == wire.sides.count else { return nil }
            podium = Podium(
                champion: champion, sides: sides, speech: first(champion)?.speech,
                championMove: first(champion)?.move, sideMove: sides.first.flatMap(first)?.move)
        }
        var bestDisclaimer: BestDisclaimer?
        if let wire = frozen.bestDisclaimer {
            guard let checkIn = UUID(uuidString: wire.checkIn), let author = Self.member(wire.author) else {
                return nil
            }
            bestDisclaimer = BestDisclaimer(
                checkIn: CheckInID(checkIn), author: author, text: wire.text, reactions: wire.reactions)
        }
        let hottest = frozen.hottest.map(Hottest.init)
        let myWeek = frozen.myWeek.map(RecapDomain.MyWeek.init)
        let meals = frozen.meals.map(Meals.init)
        // A page the API sent that can't be read makes the story unreadable, not a page short.
        if hottest == .some(nil) || myWeek == .some(nil) || meals == .some(nil) { return nil }
        self.init(
            status: status, squad: SquadID(squad), squadName: frozen.squad.name,
            week: Week(monday: monday, sunday: sunday), scene: scene, squadmates: squadmates, podium: podium,
            titles: titles, myWeek: myWeek ?? nil, hottest: hottest ?? nil, meals: meals ?? nil,
            bestDisclaimer: bestDisclaimer, ending: frozen.ending.map { Ending(done: $0.done, plan: $0.plan) })
    }

    private static func member(_ id: String) -> MemberID? {
        UUID(uuidString: id).map(MemberID.init)
    }

    private static func squadmates(_ members: [Components.Schemas.StoryMember]) -> [Squadmate]? {
        var squadmates: [Squadmate] = []
        for wire in members {
            guard let member = member(wire.member) else { return nil }
            // A character whose nickname no longer passes the app's rule shows as none.
            squadmates.append(
                Squadmate(member: member, character: wire.character.flatMap { try? MemberCharacter($0) }))
        }
        return squadmates
    }
}

extension RecapDomain.MyWeek {
    init?(_ wire: Components.Schemas.StoryMyWeek) {
        var days: [Day] = []
        for each in wire.days {
            guard let day = try? LocalDay(each.day) else { return nil }
            let kind: DayKind =
                switch each.kind {
                // A sport of the member's own has no art of its own: the day shows just that they trained.
                case .trained: .trained(each.sport.flatMap(Sport.init(rawValue:)))
                case .rest: .rest
                case .disclaimer: .disclaimer
                case .none: .none
                }
            days.append(Day(day: day, kind: kind))
        }
        self.init(
            plan: wire.plannedDays, days: days, healthyMeals: wire.healthyMeals, cheatMeals: wire.cheatMeals,
            reactionsReceived: wire.reactionsReceived)
    }
}

extension Meals {
    init?(_ wire: Components.Schemas.StoryMeals) {
        var eaters: [Eater] = []
        for eater in wire.eaters {
            guard let member = UUID(uuidString: eater.member) else { return nil }
            eaters.append(Eater(member: MemberID(member), more: eater.more == .cheat ? .cheat : .healthy))
        }
        self.init(healthy: wire.healthy, cheat: wire.cheat, eaters: eaters)
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
