import Contracts
import DesignSystem
import Foundation
import PlacesDomain
import Testing

struct SquadMapTests {
    private static let squad = SquadID(UUID())
    private static let mia = MemberID(UUID())
    private static let leo = MemberID(UUID())
    private static let kiki = MemberID(UUID())
    private let gym: Place
    private let salad: Place
    private let park: Place

    init() throws {
        gym = try Place(name: "Equinox", appleID: "IGYM", category: "fitnessCenter", latitude: 40.74, longitude: -73.99)
        salad = try Place(
            name: "Sweetgreen", appleID: "ISALAD", category: "restaurant", latitude: 40.73, longitude: -73.99)
        park = try Place(
            name: "Hudson River Park", appleID: "IPARK", category: "park", latitude: 40.72, longitude: -74.01)
    }

    private static func post(
        _ member: MemberID, at place: Place?, day: String, minute: Int64, meal: Bool = false, inFeed: Bool = true
    ) throws -> CheckIn {
        let entry: CheckIn.Entry =
            meal
            ? .healthyMeal(Meal(place: place))
            : .trained(Training(activity: .sport("run"), minutes: try WorkoutMinutes(30), place: place))
        return CheckIn(
            id: CheckInID(UUID()), member: member, day: try LocalDay(day),
            createdAt: Timestamp(millisecondsSince1970: minute * 60_000), audience: try Audience([squad]),
            inFeed: inFeed, entry: entry)
    }

    private func map() throws -> (SquadMapLayout, [CheckIn]) {
        let posts = [
            try Self.post(Self.mia, at: gym, day: "2026-11-10", minute: 1),
            try Self.post(Self.leo, at: gym, day: "2026-11-11", minute: 2),
            try Self.post(Self.mia, at: gym, day: "2026-11-12", minute: 3),
            try Self.post(Self.kiki, at: park, day: "2026-11-13", minute: 4),
            try Self.post(Self.kiki, at: salad, day: "2026-11-13", minute: 5, meal: true),
            try Self.post(Self.mia, at: salad, day: "2026-11-13", minute: 6, meal: true),
            try Self.post(Self.leo, at: nil, day: "2026-11-13", minute: 7),
            try Self.post(Self.leo, at: park, day: "2026-11-13", minute: 8, inFeed: false),
        ]
        let data = FeedPlaceSource.map(from: posts, today: try LocalDay("2026-11-13"))
        return (SquadMapLayout(data: data, today: try LocalDay("2026-11-13")), posts)
    }

    @Test func oftenListsEveryTaggedPlaceMostVisitedFirst() throws {
        let (view, _) = try map()
        #expect(view.oftenPlaces.map(\.place.name) == ["Equinox", "Sweetgreen", "Hudson River Park"])
        #expect(view.oftenPlaces.map(\.visits) == [3, 2, 1])
        let equinox = try #require(view.oftenPlaces.first)
        #expect(equinox.members == [MemberVisits(Self.mia, visits: 2), MemberVisits(Self.leo, visits: 1)])
        #expect(view.oftenPlaces[1].meals.healthyMeals == 2)
    }

    @Test func oftenMakesTheTopPlaceBiggestAndFarLowerOnesFaint() throws {
        let (view, _) = try map()
        #expect(view.oftenSpots.map(\.emphasis) == [.top, .regular, .faint])
        #expect(view.oftenSpots.first?.heads == [Self.mia, Self.leo])
    }

    @Test func todayStacksTodaysPostsByPlaceNewestFirst() throws {
        let (view, posts) = try map()
        #expect(view.todayVisits.map(\.id) == [posts[5].id, posts[4].id, posts[3].id])
        #expect(view.todaySpots.map(\.place.place.name) == ["Sweetgreen", "Hudson River Park"])
        #expect(view.todaySpots.first?.heads == [Self.mia, Self.kiki])
        #expect(view.todaySpots.allSatisfy { $0.emphasis == .regular })
    }

    @Test func aMembersDayIsTheirPostsTodayEachWhereItWas() throws {
        let (view, posts) = try map()
        #expect(view.stops(of: Self.kiki).map(\.visit.id) == [posts[4].id, posts[3].id])
        #expect(view.stops(of: Self.kiki).map(\.place.place.name) == ["Sweetgreen", "Hudson River Park"])
        #expect(view.stops(of: Self.leo).isEmpty)
    }

    @Test func recentKeepsOnlyTodayAndTheDayBefore() throws {
        let (view, _) = try map()
        #expect(Set(view.data.recent.map(\.day.description)) == ["2026-11-12", "2026-11-13"])
    }
}

@MainActor
struct SquadMapStoreTests {
    private actor Source: PlaceSource {
        let data: SquadMapData
        init(_ data: SquadMapData) { self.data = data }
        func detail(of place: PlaceKey, in squad: SquadID) async throws(PlacesError) -> PlaceDetail? { nil }
        func map(of squad: SquadID) async throws(PlacesError) -> SquadMapData { data }
        func characters(in squad: SquadID) async throws(PlacesError) -> [MemberID: MemberCharacter] { [:] }
        func photo(_ ref: PhotoRef) async -> Data? { nil }
    }

    @Test func tappingARowShowsOnlyThatMembersDayUntilClosed() async throws {
        let place = try Place(name: "Equinox", appleID: "IGYM", latitude: 40.74, longitude: -73.99)
        let key = try #require(place.key)
        let (mia, leo) = (MemberID(UUID()), MemberID(UUID()))
        let today = try LocalDay("2026-11-13")
        let visits = [
            MapVisit(
                id: CheckInID(UUID()), author: leo, kind: .trained, day: today,
                createdAt: Timestamp(millisecondsSince1970: 2), key: key),
            MapVisit(
                id: CheckInID(UUID()), author: mia, kind: .trained, day: today,
                createdAt: Timestamp(millisecondsSince1970: 1), key: key),
        ]
        let data = SquadMapData(
            places: [
                MapPlace(
                    key: key, place: place, visits: 2,
                    members: [MemberVisits(leo, visits: 1), MemberVisits(mia, visits: 1)])
            ], recent: visits)
        let store = SquadMapStore(squad: SquadID(UUID()), today: today, source: Source(data))
        await store.load()
        #expect(store.phase == .loaded)
        #expect(store.spots.first?.heads == [leo, mia])
        store.toggle(key)
        #expect(store.expanded == key)
        store.show(mia)
        #expect(store.expanded == nil)
        #expect(store.spots.isEmpty)
        #expect(store.stops.map(\.visit.author) == [mia])
        #expect(store.rows.map(\.author) == [mia])
        store.showSquad()
        #expect(store.rows.map(\.author) == [leo, mia])
        store.mode = .often
        #expect(store.spots.first?.emphasis == .top)
    }
}
