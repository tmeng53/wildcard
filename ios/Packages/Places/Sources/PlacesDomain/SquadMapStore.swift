import Contracts
import Foundation
import Observation

/// 小队地图 as the app reads it (Tracy, 2026-11-12): 今天 or 常去, which stack is fanned out, and
/// whose day is on the map after their row is tapped. Opened from 动态's map button.
@MainActor @Observable
public final class SquadMapStore {
    /// Where reading the map stands.
    public enum Phase: Equatable, Sendable {
        case loading
        case loaded
        /// The server couldn't be reached; the map shows what it read last, or nothing.
        case offline
        case notInSquad
        case signedOut
    }

    public private(set) var phase = Phase.loading
    public private(set) var layout: SquadMapLayout
    /// The squad's members' characters: the heads. One who left the squad has none, and is
    /// greyed.
    public private(set) var characters: [MemberID: MemberCharacter] = [:]
    /// 今天 or 常去.
    public var mode = SquadMapLayout.Mode.today {
        didSet { (expanded, member) = (nil, nil) }
    }
    /// The stack fanned out into a row, if any.
    public private(set) var expanded: PlaceKey?
    /// Whose day the map shows after their row was tapped (今天 only).
    public private(set) var member: MemberID?

    private let squad: SquadID
    private let source: any PlaceSource

    /// - Parameter today: the viewer's today, whose posts 今天 shows.
    public init(squad: SquadID, today: LocalDay, source: any PlaceSource) {
        (self.squad, self.source) = (squad, source)
        layout = SquadMapLayout(data: .empty, today: today)
    }

    /// The stacks the map shows now: 今天's or 常去's. Empty while one member's day is up.
    public var spots: [MapSpot] {
        guard member == nil else { return [] }
        return mode == .today ? layout.todaySpots : layout.oftenSpots
    }

    /// Everyone else's 今天 stacks, faded behind a member's day while it is up: the member's own
    /// visits are left out, since their stops stand there instead.
    public var fadedSpots: [MapSpot] {
        guard let member else { return [] }
        return layout.todaySpots.compactMap { spot in
            let others = spot.visits.filter { $0.author != member }
            guard !others.isEmpty else { return nil }
            return MapSpot(
                place: spot.place, visits: others, heads: spot.heads.filter { $0 != member },
                emphasis: spot.emphasis)
        }
    }

    /// One member's posts today, each where it was, while their day is up.
    public var stops: [MapStop] { member.map(layout.stops(of:)) ?? [] }

    /// Today's posts with a place, newest first: 今天's list, or only the member's while their
    /// day is up.
    public var rows: [MapVisit] {
        let all = layout.todayVisits
        return member.map { who in all.filter { $0.author == who } } ?? all
    }

    /// Whether the member is still in the squad: one who left is greyed. Everyone counts as in
    /// while the heads couldn't be read.
    public func isInSquad(_ member: MemberID) -> Bool { characters.isEmpty || characters[member] != nil }

    /// Reads the map and the heads side by side.
    public func load() async {
        do throws(PlacesError) {
            async let people = source.characters(in: squad)
            let data = try await source.map(of: squad)
            layout = SquadMapLayout(data: data, today: layout.today)
            characters = (try? await people) ?? characters
            phase = .loaded
        } catch {
            phase =
                switch error {
                case .signedOut: .signedOut
                case .notInSquad: .notInSquad
                case .unavailable: .offline
                }
        }
    }

    /// Fans a stack out, or folds the one that is.
    public func toggle(_ spot: PlaceKey) {
        expanded = expanded == spot ? nil : spot
    }

    /// Puts one member's day on the map (their 今天 row was tapped).
    public func show(_ member: MemberID) {
        (self.member, expanded) = (member, nil)
    }

    /// Back to the whole squad (✕).
    public func showSquad() {
        member = nil
    }
}
