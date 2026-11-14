import CheckInDomain
import Contracts
import DesignSystem
import FeedDomain
import Foundation

/// A place's numbers counted on the phone from the squad's 动态, for the in-memory sample squad
/// and UI tests, which have no server to count them: the posts of the last `weeks` weeks tagged
/// there, by the server's rules (places have no scores). Those rules live in
/// `api/apps/server/src/flows/squad-places.ts` (`byPlace`, `summaryOf`, `detailOf`): a change
/// there changes this too.
public struct FeedPlaceSource: PlaceSource {
    private let feed: any FeedSource
    private let today: LocalDay
    private let weeks: Int

    public init(feed: any FeedSource, today: LocalDay, weeks: Int = 8) {
        (self.feed, self.today, self.weeks) = (feed, today, weeks)
    }

    public func detail(of place: PlaceKey, in squad: SquadID) async throws(PlacesError) -> PlaceDetail? {
        let posts: [FeedPost]
        do throws(FeedError) {
            posts = try await feed.posts(in: squad, from: today.adding(days: -7 * weeks), through: today)
        } catch {
            throw PlacesError(error)
        }
        return Self.detail(of: place, from: posts.map(\.checkIn))
    }

    public func map(of squad: SquadID) async throws(PlacesError) -> SquadMapData {
        let posts: [FeedPost]
        do throws(FeedError) {
            posts = try await feed.posts(in: squad, from: today.adding(days: -7 * weeks), through: today)
        } catch {
            throw PlacesError(error)
        }
        return Self.map(from: posts.map(\.checkIn), today: today)
    }

    public func characters(in squad: SquadID) async throws(PlacesError) -> [MemberID: MemberCharacter] {
        do throws(FeedError) {
            return try await feed.characters(in: squad)
        } catch {
            throw PlacesError(error)
        }
    }

    public func photo(_ ref: PhotoRef) async -> Data? { await feed.photo(ref) }

    /// The place's numbers from these check-ins; nil when none is tagged there.
    public static func detail(of key: PlaceKey, from checkIns: [CheckIn]) -> PlaceDetail? {
        let tagged = checkIns.filter { $0.inFeed && $0.entry.place?.key == key }
            .sorted { $0.createdAt > $1.createdAt }
        guard let newest = tagged.first, let place = newest.entry.place else { return nil }
        var sports: [Activity: Int] = [:]
        var meals = MealTally()
        let visits = tagged.map { checkIn -> PlaceVisit in
            let visit = PlaceVisit(checkIn)
            switch visit.kind {
            case .trained: if let activity = visit.activity { sports[activity, default: 0] += 1 }
            case .healthyMeal: meals.healthyMeals += 1
            case .cheatMeal: meals.cheatMeals += 1
            case .disclaimer: break
            }
            return visit
        }
        return PlaceDetail(
            place: place, visits: tagged.count, people: Set(tagged.map(\.member)).count,
            sports: sports.map { SportCount($0.key, count: $0.value) }
                .sorted { ($0.count, $1.activity.sortKey) > ($1.count, $0.activity.sortKey) },
            meals: meals, posts: visits)
    }
}

extension FeedPlaceSource {
    /// 小队地图 from these check-ins, by the server's rules: every place tagged, most visited first
    /// (the newest first on a tie), and the posts of `today` and the day before, newest first.
    public static func map(from checkIns: [CheckIn], today: LocalDay) -> SquadMapData {
        let tagged = checkIns.filter { $0.inFeed && $0.entry.place?.key != nil }
            .sorted { $0.createdAt > $1.createdAt }
        var order: [PlaceKey] = []
        var byPlace: [PlaceKey: [CheckIn]] = [:]
        for checkIn in tagged {
            guard let key = checkIn.entry.place?.key else { continue }
            if byPlace[key] == nil { order.append(key) }
            byPlace[key, default: []].append(checkIn)
        }
        let places = order.compactMap { key -> MapPlace? in
            guard let detail = detail(of: key, from: byPlace[key] ?? []) else { return nil }
            var visits: [MemberID: Int] = [:]
            var members: [MemberID] = []
            for post in detail.posts {
                if visits[post.author] == nil { members.append(post.author) }
                visits[post.author, default: 0] += 1
            }
            let counted = members.map { MemberVisits($0, visits: visits[$0] ?? 0) }
                .enumerated().sorted { ($0.element.visits, $1.offset) > ($1.element.visits, $0.offset) }
                .map(\.element)
            return MapPlace(
                key: key, place: detail.place, visits: detail.visits, members: counted, sports: detail.sports,
                meals: detail.meals)
        }
        .enumerated().sorted { ($0.element.visits, $1.offset) > ($1.element.visits, $0.offset) }.map(\.element)
        let since = today.adding(days: -1)
        let recent = tagged.filter { $0.day >= since }.compactMap { checkIn -> MapVisit? in
            guard let key = checkIn.entry.place?.key else { return nil }
            let tile = PlaceVisit(checkIn)
            return MapVisit(
                id: tile.id, author: tile.author, kind: tile.kind, activity: tile.activity, day: tile.day,
                createdAt: checkIn.createdAt, key: key)
        }
        return SquadMapData(places: places, recent: recent)
    }
}

extension PlaceVisit {
    /// A post's tile.
    init(_ checkIn: CheckIn) {
        let (id, author, day) = (checkIn.id, checkIn.member, checkIn.day)
        switch checkIn.entry {
        case .trained(let training):
            self.init(
                id: id, author: author, kind: .trained, activity: training.activity, day: day,
                cover: training.photos?.cover, minutes: training.minutes?.value)
        case .healthyMeal(let meal):
            self.init(id: id, author: author, kind: .healthyMeal, day: day, cover: meal.photos?.cover)
        case .cheatMeal(let meal):
            self.init(id: id, author: author, kind: .cheatMeal, day: day, cover: meal.photos?.cover)
        case .disclaimer:
            self.init(id: id, author: author, kind: .disclaimer, day: day)
        }
    }
}

extension PlacesError {
    init(_ error: FeedError) {
        self =
            switch error {
            case .signedOut: .signedOut
            case .notInSquad: .notInSquad
            default: .unavailable
            }
    }
}

extension Activity {
    /// For an order that never changes between reads.
    fileprivate var sortKey: String {
        switch self {
        case .sport(let sport): sport.rawValue
        case .custom(let custom): "custom.\(custom.name)"
        }
    }
}
