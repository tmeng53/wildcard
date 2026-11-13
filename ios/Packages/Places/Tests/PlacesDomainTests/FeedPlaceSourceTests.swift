import Contracts
import DesignSystem
import Foundation
import PlacesDomain
import Testing

struct FeedPlaceSourceTests {
    private static let squad = SquadID(UUID())
    private static let mia = MemberID(UUID())
    private static let leo = MemberID(UUID())
    private let gym: Place
    private let elsewhere: Place

    init() throws {
        gym = try Place(name: "Equinox", appleID: "IGYM", category: "fitnessCenter", latitude: 40.74, longitude: -73.99)
        elsewhere = try Place(name: "Blink", appleID: "IOTHER", latitude: 40.7, longitude: -73.9)
    }

    private static func training(
        _ member: MemberID, _ sport: Sport, at place: Place?, minute: Int64, inFeed: Bool = true
    ) throws -> CheckIn {
        CheckIn(
            id: CheckInID(UUID()), member: member, day: try LocalDay("2026-11-12"),
            createdAt: Timestamp(millisecondsSince1970: minute * 60_000), audience: try Audience([squad]),
            inFeed: inFeed,
            entry: .trained(Training(activity: .sport(sport), minutes: try WorkoutMinutes(45), place: place)))
    }

    @Test func aPlaceIsCountedFromThePostsTaggedThereNewestFirst() throws {
        let first = try Self.training(Self.mia, "cycling", at: gym, minute: 1)
        let second = try Self.training(Self.leo, "cycling", at: gym, minute: 2)
        let third = try Self.training(Self.mia, "hiit", at: gym, minute: 3)
        let other = try Self.training(Self.leo, "run", at: elsewhere, minute: 4)
        let hidden = try Self.training(Self.leo, "run", at: gym, minute: 5, inFeed: false)
        let key = try #require(gym.key)
        let detail = try #require(
            FeedPlaceSource.detail(of: key, from: [first, second, third, other, hidden]))
        #expect(detail.visits == 3)
        #expect(detail.people == 2)
        #expect(detail.sports == [SportCount(.sport("cycling"), count: 2), SportCount(.sport("hiit"), count: 1)])
        #expect(detail.posts.map(\.id) == [third.id, second.id, first.id])
        #expect(detail.posts.first?.minutes == 45)
        #expect(detail.posts.first?.kind == .trained)
    }

    @Test func aPlaceNobodyTaggedHasNoNumbers() throws {
        let key = try #require(gym.key)
        #expect(FeedPlaceSource.detail(of: key, from: [try Self.training(Self.mia, "run", at: nil, minute: 1)]) == nil)
    }
}
