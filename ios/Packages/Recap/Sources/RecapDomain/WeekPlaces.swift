import Contracts
import Foundation

/// A meal on 小队菜单: one of the week's rated meals with the best 卡价比, a dish to try, never a
/// ranking of who ate better.
public struct MenuDish: Hashable, Sendable {
    public let checkIn: CheckInID
    public let author: MemberID
    public let day: LocalDay
    /// The meal's own 健康 and 好吃, 1 to 5 each.
    public let healthy: Int
    public let tasty: Int
    public let caption: String?
    /// The cover's signed URL.
    public let photo: URL?
    public let place: Place?

    public init(
        checkIn: CheckInID, author: MemberID, day: LocalDay, healthy: Int, tasty: Int, caption: String? = nil,
        photo: URL? = nil, place: Place? = nil
    ) {
        self.checkIn = checkIn
        self.author = author
        self.day = day
        self.healthy = min(max(healthy, 1), 5)
        self.tasty = min(max(tasty, 1), 5)
        self.caption = caption
        self.photo = photo
        self.place = place
    }

    /// 卡价比 (卡路里性价比): 好吃 × 健康 ÷ 5, from 0.2 to 5, as the API ranks the menu by.
    public var calorieValue: Double { Double(healthy * tasty) / 5 }

    /// 「4.0」: one decimal, as the card's chip shows it.
    public var calorieValueText: String {
        let tenths = (healthy * tasty * 2)
        return "\(tenths / 10).\(tenths % 10)"
    }

    /// The dish's name on its card: the caption, else where it was eaten.
    public var name: String? { caption ?? place?.name }
}

/// A place the squad trained at that week, with each 训练 tagged there.
public struct PlaceWeek: Hashable, Sendable {
    public struct Visit: Hashable, Sendable {
        public let member: MemberID
        public let day: LocalDay

        public init(member: MemberID, day: LocalDay) {
            self.member = member
            self.day = day
        }
    }

    /// Someone who trained there, with how often and their first day there that week.
    public struct Visitor: Hashable, Sendable {
        public let member: MemberID
        public let visits: Int
        public let firstDay: LocalDay
    }

    /// `apple:` and Maps' id, or `squad:` and the squad's own place's id.
    public let key: String
    public let place: Place
    /// Nobody had posted a 训练 there to the squad before that week.
    public let firstTime: Bool
    /// Each 训练 there, by day.
    public let visits: [Visit]

    public init(key: String, place: Place, firstTime: Bool, visits: [Visit]) {
        self.key = key
        self.place = place
        self.firstTime = firstTime
        self.visits = visits.sorted { $0.day < $1.day }
    }

    /// Who trained there: the most visits first, then who came first, as the heads stack.
    public var visitors: [Visitor] {
        var order: [MemberID] = []
        var counts: [MemberID: Int] = [:]
        var first: [MemberID: LocalDay] = [:]
        for visit in visits {
            if counts[visit.member] == nil { order.append(visit.member) }
            counts[visit.member, default: 0] += 1
            first[visit.member] = min(first[visit.member] ?? visit.day, visit.day)
        }
        return order.compactMap { member in
            guard let visits = counts[member], let day = first[member] else { return nil }
            return Visitor(member: member, visits: visits, firstDay: day)
        }
        .enumerated()
        .sorted { lhs, rhs in
            lhs.element.visits != rhs.element.visits ? lhs.element.visits > rhs.element.visits : lhs.offset < rhs.offset
        }
        .map(\.element)
    }
}

/// 小队最爱去 or 新发现: one place in focus on the map, with the squad's other places that week
/// faint around it.
public struct PlaceSpotlight: Hashable, Sendable {
    public let place: PlaceWeek
    public let others: [PlaceWeek]

    public init(place: PlaceWeek, others: [PlaceWeek]) {
        self.place = place
        self.others = others
    }
}

extension WeekStory {
    /// 小队最爱去: the place the squad trained at most (the API sends them that way round).
    public var favoritePlace: PlaceSpotlight? {
        places.first.map { favorite in PlaceSpotlight(place: favorite, others: Array(places.dropFirst())) }
    }

    /// 新发现: the squad's first visit to a place it hadn't posted a 训练 at before; skipped when the
    /// only one is already 小队最爱去, so the same map never plays twice.
    public var discovery: PlaceSpotlight? {
        guard let favorite = places.first,
            let found = places.first(where: { $0.firstTime && $0.key != favorite.key })
        else { return nil }
        return PlaceSpotlight(place: found, others: places.filter { $0.key != found.key })
    }
}
