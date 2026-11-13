import Contracts
import DesignSystem

/// What the squad did at a place, as the server counts it from the posts tagged there (the
/// squad's 动态 only). A place nobody in the squad tagged has none: its page is the empty card.
public struct PlaceDetail: Hashable, Sendable {
    /// The place as the newest post there tagged it.
    public var place: Place
    /// 小队来过 N 次: posts tagged with it.
    public var visits: Int
    /// 来过的队友 N 人.
    public var people: Int
    /// The 训练 there, by sport, most first.
    public var sports: [SportCount]
    /// The meals there and what rated ones scored.
    public var meals: MealTally
    /// The posts tagged with it, newest first.
    public var posts: [PlaceVisit]

    public init(
        place: Place, visits: Int, people: Int, sports: [SportCount], meals: MealTally,
        posts: [PlaceVisit]
    ) {
        (self.place, self.visits, self.people) = (place, visits, people)
        (self.sports, self.meals, self.posts) = (sports, meals, posts)
    }
}

/// One sport the squad trained at a place and how many 训练 named it.
public struct SportCount: Hashable, Sendable {
    public var activity: Activity
    public var count: Int

    public init(_ activity: Activity, count: Int) {
        (self.activity, self.count) = (activity, count)
    }
}

/// 大家在这里吃: meals by kind. A place shows no average of its meals' scores (Tracy, 2026-11-13).
public struct MealTally: Hashable, Sendable {
    public var healthyMeals: Int
    public var cheatMeals: Int

    public init(healthyMeals: Int = 0, cheatMeals: Int = 0) {
        (self.healthyMeals, self.cheatMeals) = (healthyMeals, cheatMeals)
    }

    public static let none = MealTally()
}

/// One post tagged at a place, as its tile on the page shows it.
public struct PlaceVisit: Hashable, Sendable, Identifiable {
    public let id: CheckInID
    public let author: MemberID
    /// A 训练 or a meal: only those carry a place.
    public let kind: CheckInKind
    /// A 训练's sport.
    public let activity: Activity?
    /// The day it counts for, on the author's clock.
    public let day: LocalDay
    /// Its first photo; nil for a post without one, whose tile wears its colour and icons.
    public let cover: PhotoRef?
    /// A 训练's minutes.
    public let minutes: Int?

    public init(
        id: CheckInID, author: MemberID, kind: CheckInKind, activity: Activity? = nil, day: LocalDay,
        cover: PhotoRef? = nil, minutes: Int? = nil
    ) {
        (self.id, self.author, self.kind, self.activity, self.day) = (id, author, kind, activity, day)
        (self.cover, self.minutes) = (cover, minutes)
    }
}
