import CheckInDomain
import Contracts
import DesignSystem

/// 小队地图 as the server counts it (Tracy, 2026-11-12): every place the squad's 动态 was tagged
/// with, and the posts tagged in the last two days. Nothing on it comes from where a phone was.
public struct SquadMapData: Hashable, Sendable {
    /// 常去: every place, most visited first.
    public var places: [MapPlace]
    /// The posts tagged with a place in the last two days, newest first.
    public var recent: [MapVisit]

    public init(places: [MapPlace], recent: [MapVisit]) {
        (self.places, self.recent) = (places, recent)
    }

    public static let empty = SquadMapData(places: [], recent: [])
}

/// One place on the map and what the squad did there.
public struct MapPlace: Hashable, Sendable, Identifiable {
    public let key: PlaceKey
    /// As the newest post there tagged it.
    public let place: Place
    /// 小队去过 N 次.
    public let visits: Int
    /// Who posted there and how often, most first; one who left the squad is still listed.
    public let members: [MemberVisits]
    /// The 训练 there by sport, most first.
    public let sports: [SportCount]
    /// The meals there by kind.
    public let meals: MealTally

    public var id: PlaceKey { key }

    public init(
        key: PlaceKey, place: Place, visits: Int, members: [MemberVisits], sports: [SportCount] = [],
        meals: MealTally = .none
    ) {
        (self.key, self.place, self.visits, self.members) = (key, place, visits, members)
        (self.sports, self.meals) = (sports, meals)
    }
}

/// How many of a place's posts are one member's.
public struct MemberVisits: Hashable, Sendable {
    public let member: MemberID
    public let visits: Int

    public init(_ member: MemberID, visits: Int) {
        (self.member, self.visits) = (member, visits)
    }
}

/// One post tagged with a place.
public struct MapVisit: Hashable, Sendable, Identifiable {
    public let id: CheckInID
    public let author: MemberID
    /// A 训练 or a meal.
    public let kind: CheckInKind
    /// A 训练's sport.
    public let activity: Activity?
    /// The day it counts for, on the author's clock.
    public let day: LocalDay
    /// When it was posted.
    public let createdAt: Timestamp
    /// Where.
    public let key: PlaceKey

    public init(
        id: CheckInID, author: MemberID, kind: CheckInKind, activity: Activity? = nil, day: LocalDay,
        createdAt: Timestamp, key: PlaceKey
    ) {
        (self.id, self.author, self.kind, self.activity) = (id, author, kind, activity)
        (self.day, self.createdAt, self.key) = (day, createdAt, key)
    }
}

/// A stack of heads on the map: a place and who is on it.
public struct MapSpot: Hashable, Sendable, Identifiable {
    public let place: MapPlace
    /// 今天: today's posts there, newest first (several from one member each count). 常去: none.
    public let visits: [MapVisit]
    /// The heads, top of the stack first: 今天 newest poster first, each once; 常去 most visits
    /// first.
    public let heads: [MemberID]
    /// How it stands among the others: 常去's most visited is bigger and named, those far below
    /// it fainter.
    public let emphasis: Emphasis

    public var id: PlaceKey { place.key }

    public enum Emphasis: Hashable, Sendable {
        /// The most visited place, bigger, with its name under it.
        case top
        case regular
        /// Visited a third as often as the top or less.
        case faint
    }
}

/// One of a member's posts today, on the map by itself when their row is tapped.
public struct MapStop: Hashable, Sendable, Identifiable {
    public let visit: MapVisit
    public let place: MapPlace

    public var id: CheckInID { visit.id }
}

/// What 小队地图 shows: 今天's spots and rows, or 常去's, or one member's day; and which stack is
/// fanned out. Pure: the store reads `SquadMapData` and asks this.
public struct SquadMapLayout: Hashable, Sendable {
    public enum Mode: Hashable, Sendable, CaseIterable {
        /// 今天: who trained or ate where today.
        case today
        /// 常去: where the squad goes.
        case often
    }

    public let data: SquadMapData
    /// The viewer's today: 今天 shows the posts that count for it.
    public let today: LocalDay

    public init(data: SquadMapData, today: LocalDay) {
        (self.data, self.today) = (data, today)
    }

    /// Today's posts with a place, newest first: 今天's list.
    public var todayVisits: [MapVisit] {
        data.recent.filter { $0.day == today && place($0.key) != nil }.sorted { $0.createdAt > $1.createdAt }
    }

    /// 今天's stacks: each place someone posted from today, the newest first.
    public var todaySpots: [MapSpot] {
        var order: [PlaceKey] = []
        var visits: [PlaceKey: [MapVisit]] = [:]
        for visit in todayVisits {
            if visits[visit.key] == nil { order.append(visit.key) }
            visits[visit.key, default: []].append(visit)
        }
        return order.compactMap { key in
            guard let place = place(key), let there = visits[key] else { return nil }
            return MapSpot(place: place, visits: there, heads: Self.once(there.map(\.author)), emphasis: .regular)
        }
    }

    /// 常去's stacks, most visited first.
    public var oftenSpots: [MapSpot] {
        let places = oftenPlaces
        guard let top = places.first?.visits else { return [] }
        return places.enumerated().map { index, place in
            let emphasis: MapSpot.Emphasis =
                if index == 0 { .top } else if place.visits * 3 <= top { .faint } else { .regular }
            return MapSpot(place: place, visits: [], heads: place.members.map(\.member), emphasis: emphasis)
        }
    }

    /// 小队常去's list: every place, most visited first (the newest visited first on a tie, as the
    /// server sends them).
    public var oftenPlaces: [MapPlace] {
        data.places.enumerated().sorted { ($0.element.visits, $1.offset) > ($1.element.visits, $0.offset) }
            .map(\.element)
    }

    /// A member's posts today, each where it was, newest first: the map of their day.
    public func stops(of member: MemberID) -> [MapStop] {
        todayVisits.filter { $0.author == member }.compactMap { visit in
            place(visit.key).map { MapStop(visit: visit, place: $0) }
        }
    }

    /// The place with this key.
    public func place(_ key: PlaceKey) -> MapPlace? { data.places.first { $0.key == key } }

    /// Each member once, in the order they first come.
    private static func once(_ members: [MemberID]) -> [MemberID] {
        var seen = Set<MemberID>()
        return members.filter { seen.insert($0).inserted }
    }
}
