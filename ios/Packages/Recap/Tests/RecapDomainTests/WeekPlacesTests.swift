import Contracts
import DesignSystem
import Foundation
import Testing

@testable import RecapDomain

private func member(_ number: Int) -> MemberID {
    MemberID(UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", number)) ?? UUID())
}

private func day(_ number: Int) throws -> LocalDay {
    try LocalDay(year: 2026, month: 10, day: number)
}

private func place(_ name: String) throws -> Place {
    try Place(name: name, latitude: 40.74, longitude: -73.99)
}

private func spot(_ key: String, firstTime: Bool = false, _ visits: [(Int, Int)]) throws -> PlaceWeek {
    PlaceWeek(
        key: key, place: try place(key), firstTime: firstTime,
        visits: try visits.map { PlaceWeek.Visit(member: member($0.0), day: try day($0.1)) })
}

private func story(menu: [MenuDish] = [], places: [PlaceWeek] = [], meals: Bool = true) throws -> WeekStory {
    WeekStory(
        status: .ready, squad: SquadID(UUID()), squadName: "晨跑五人组",
        week: Week(monday: try day(13), sunday: try day(19)), scene: .gym, squadmates: [],
        order: [.myWeek, .squadWeek, .hottest, .meals, .ending],
        myWeek: MyWeek(plan: 5, days: [], healthyMeals: 3, cheatMeals: 1, reactionsReceived: 12),
        squadWeek: SquadWeek(members: [.init(member: member(1), days: [.trained("run")])]),
        hottest: Hottest(checkIn: CheckInID(UUID()), day: try day(16), kind: .trained, reactions: []),
        meals: meals ? Meals(healthy: 14, cheat: 5, eaters: []) : nil,
        menu: menu, places: places, ending: Ending(done: 23, plan: 22))
}

private func dish(_ healthy: Int, _ tasty: Int, caption: String? = nil) throws -> MenuDish {
    MenuDish(
        checkIn: CheckInID(UUID()), author: member(1), day: try day(14), healthy: healthy, tasty: tasty,
        caption: caption)
}

private func names(_ pages: [StoryPage]) -> [String] {
    pages.map {
        switch $0 {
        case .myWeek: "myWeek"
        case .squadWeek: "squadWeek"
        case .hottest: "hottest"
        case .meals: "meals"
        case .menu: "menu"
        case .favoritePlace(let spot): "favorite:\(spot.place.key)"
        case .discovery(let spot): "discovery:\(spot.place.key)"
        case .ending: "ending"
        default: "other"
        }
    }
}

@Test func theMenuFollowsMealsAndThePlacesFollowTheSquadsWeek() throws {
    let pages = try story(
        menu: [try dish(5, 5)],
        places: [try spot("gym", [(1, 14), (2, 15)]), try spot("park", firstTime: true, [(3, 16)])]
    ).pages
    #expect(
        names(pages) == [
            "myWeek", "squadWeek", "favorite:gym", "discovery:park", "hottest", "meals", "menu", "ending",
        ])
}

@Test func withoutDataTheirPagesAreLeftOut() throws {
    #expect(names(try story().pages) == ["myWeek", "squadWeek", "hottest", "meals", "ending"])
    // No new place: no 新发现.
    #expect(
        names(try story(places: [try spot("gym", [(1, 14)]), try spot("park", [(2, 15)])]).pages)
            == ["myWeek", "squadWeek", "favorite:gym", "hottest", "meals", "ending"])
}

@Test func theFavoriteIsNeverAlsoTheDiscovery() throws {
    let only = try story(places: [try spot("gym", firstTime: true, [(1, 14)])])
    #expect(only.discovery == nil)
    let two = try story(places: [
        try spot("gym", firstTime: true, [(1, 14)]), try spot("park", firstTime: true, [(2, 15)]),
    ])
    #expect(two.discovery?.place.key == "park")
    #expect(two.discovery?.others.map(\.key) == ["gym"])
    #expect(two.favoritePlace?.others.map(\.key) == ["park"])
}

@Test func withoutMealsTheMenuStillPlaysBeforeTheEnding() throws {
    #expect(
        names(try story(menu: [try dish(4, 4)], meals: false).pages)
            == ["myWeek", "squadWeek", "hottest", "menu", "ending"])
}

@Test func aDishShowsItsCalorieValueToOneDecimal() throws {
    #expect(try dish(5, 5).calorieValueText == "5.0")
    #expect(try dish(4, 5).calorieValueText == "4.0")
    #expect(try dish(4, 4).calorieValueText == "3.2")
    #expect(try dish(1, 1).calorieValueText == "0.2")
    #expect(try dish(3, 4).calorieValue == 2.4)
}

@Test func aDishIsNamedByItsCaptionElseItsPlace() throws {
    #expect(try dish(5, 5, caption: "牛油果碗").name == "牛油果碗")
    let atPlace = MenuDish(
        checkIn: CheckInID(UUID()), author: member(1), day: try day(14), healthy: 5, tasty: 5,
        place: try place("Sweetgreen"))
    #expect(atPlace.name == "Sweetgreen")
    #expect(try dish(5, 5).name == nil)
}

@Test func theMenuKeepsAtMostThree() throws {
    let menu = try (1...5).map { _ in try dish(5, 5) }
    #expect(try story(menu: menu).menu.count == 3)
}

@Test func visitorsStackByVisitsThenWhoCameFirst() throws {
    let gym = try spot("gym", [(2, 17), (1, 14), (3, 15), (2, 15), (1, 16), (2, 18)])
    #expect(gym.visitors.map(\.member) == [member(2), member(1), member(3)])
    #expect(gym.visitors.map(\.visits) == [3, 2, 1])
    #expect(gym.visitors.map(\.firstDay) == [try day(15), try day(14), try day(15)])
    #expect(gym.visits.first?.day == (try day(14)))
}
