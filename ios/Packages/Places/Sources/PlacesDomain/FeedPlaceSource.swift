import CheckInDomain
import Contracts
import DesignSystem
import FeedDomain
import Foundation

/// A place's numbers counted on the phone from the squad's 动态, for the in-memory sample squad
/// and UI tests, which have no server to count them: the posts of the last `weeks` weeks tagged
/// there, by the server's rules (no scores, which only the server keeps).
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
            place: place, visits: tagged.count, people: Set(tagged.map(\.member)).count, stars: nil,
            sports: sports.map { SportCount($0.key, count: $0.value) }
                .sorted { ($0.count, $1.activity.sortKey) > ($1.count, $0.activity.sortKey) },
            meals: meals, posts: visits)
    }
}

extension PlaceVisit {
    /// A post's tile, without a score: only the server keeps those.
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
