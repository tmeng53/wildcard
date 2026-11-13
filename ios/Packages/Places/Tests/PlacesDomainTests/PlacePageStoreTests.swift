import Contracts
import DesignSystem
import Foundation
import PlacesDomain
import Testing

@MainActor
struct PlacePageStoreTests {
    private static let squad = SquadID(UUID())
    nonisolated private static let member = MemberID(UUID())
    private let gym: Place

    init() throws {
        gym = try Place(
            name: "Equinox Flatiron", appleID: "I1", category: "fitnessCenter", latitude: 40.74, longitude: -73.99)
    }

    private actor Source: PlaceSource {
        var detail: PlaceDetail?
        var failure: PlacesError?
        private(set) var asked: [PlaceKey] = []

        init(detail: PlaceDetail? = nil, failure: PlacesError? = nil) {
            (self.detail, self.failure) = (detail, failure)
        }

        func detail(of place: PlaceKey, in squad: SquadID) async throws(PlacesError) -> PlaceDetail? {
            asked.append(place)
            if let failure { throw failure }
            return detail
        }

        func characters(in squad: SquadID) async throws(PlacesError) -> [MemberID: MemberCharacter] {
            guard let nickname = try? Nickname("小鱼") else { return [:] }
            return [
                PlacePageStoreTests.member: MemberCharacter(
                    nickname: nickname, look: CharacterLook(persona: "energetic", variants: [:]))
            ]
        }

        func photo(_ ref: PhotoRef) async -> Data? { nil }
    }

    private struct Directory: PlaceDirectory {
        func facts(for place: Place) async -> PlaceFacts? { PlaceFacts(address: "897 Broadway") }
    }

    @Test func aPlaceTheSquadNeverTaggedLoadsAsTheEmptyCardWithMapsFacts() async {
        let source = Source()
        let store = PlacePageStore(place: gym, squad: Self.squad, source: source, directory: Directory())
        #expect(store.phase == .loading)
        #expect(store.showsSquad)
        await store.load()
        #expect(store.phase == .loaded)
        #expect(store.showsSquad)
        #expect(store.detail == nil)
        #expect(store.facts?.address == "897 Broadway")
        #expect(store.numbers.cells == [.squadScore(nil), .visits(0), .people(0)])
        #expect(await source.asked.map(\.rawValue) == ["apple:I1"])
    }

    @Test func theSquadsPostsAndAuthorsLoad() async throws {
        let visit = PlaceVisit(
            id: CheckInID(UUID()), author: Self.member, kind: .trained, activity: .sport("cycling"),
            day: try LocalDay("2026-11-12"), minutes: 45, score: .stars(5))
        let detail = PlaceDetail(
            place: gym, visits: 1, people: 1, stars: 5, sports: [SportCount(.sport("cycling"), count: 1)],
            meals: .none, posts: [visit])
        let store = PlacePageStore(
            place: gym, squad: Self.squad, source: Source(detail: detail), directory: Directory())
        await store.load()
        #expect(store.posts == [visit])
        #expect(store.characters[Self.member]?.nickname.text == "小鱼")
    }

    @Test func aPlaceWithoutAMapsIDOrASquadIsTheCardAlone() async throws {
        let source = Source()
        let lot = try Place(name: "楼下", latitude: 40.5, longitude: -73.5)
        let store = PlacePageStore(place: lot, squad: Self.squad, source: source, directory: Directory())
        await store.load()
        let alone = PlacePageStore(place: gym, squad: nil, source: source, directory: Directory())
        await alone.load()
        #expect(store.phase == .loaded)
        #expect(alone.phase == .loaded)
        #expect(await source.asked.isEmpty)
    }

    @Test func anUnreachableServerShowsThePlaceAloneNeverAnEmptySquad() async {
        let store = PlacePageStore(
            place: gym, squad: Self.squad, source: Source(failure: .unavailable), directory: Directory())
        await store.load()
        #expect(store.phase == .offline)
        #expect(!store.showsSquad)
        #expect(store.detail == nil)
        #expect(store.facts?.address == "897 Broadway")
    }
}
