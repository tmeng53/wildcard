import Contracts

/// A tagged place's page (地点页, Tracy, 2026-11-13): what the squad's posts there add up to, and
/// the scores its members gave. Worked out by the server from the posts in the squad's 动态,
/// never from where anyone's phone was.
public struct PlacePage: Equatable, Sendable {
    /// A sport the squad trained there, and how many 训练 named it.
    public struct SportCount: Equatable, Sendable {
        public let activity: Activity
        public let count: Int

        public init(activity: Activity, count: Int) {
            (self.activity, self.count) = (activity, count)
        }
    }

    /// The meals posted there: how many of each kind, and what the rated ones scored on average.
    public struct Meals: Equatable, Sendable {
        public let healthyMeals: Int
        public let cheatMeals: Int
        public let healthy: Double?
        public let tasty: Double?
        /// 卡价比 (好吃 × 健康 ÷ 5), averaged over the rated meals.
        public let calorieValue: Double?

        public init(healthyMeals: Int, cheatMeals: Int, healthy: Double?, tasty: Double?, calorieValue: Double?) {
            (self.healthyMeals, self.cheatMeals) = (healthyMeals, cheatMeals)
            (self.healthy, self.tasty, self.calorieValue) = (healthy, tasty, calorieValue)
        }

        public static let none = Meals(healthyMeals: 0, cheatMeals: 0, healthy: nil, tasty: nil, calorieValue: nil)

        public var count: Int { healthyMeals + cheatMeals }
    }

    public let key: PlaceKey
    /// The place as the newest post there tagged it.
    public let place: Place
    /// 小队来过 N 次: posts in the squad's 动态 tagged with it.
    public let visits: Int
    /// 来过的队友 N 人.
    public let people: Int
    /// 小队评分: the squad's members' scores averaged to one decimal; nil before anyone gave one.
    public let stars: Double?
    /// How many of the squad's members gave a score.
    public let raters: Int
    /// The member's own score; nil before they gave one.
    public let myStars: Int?
    /// 大家在这里练, most first.
    public let sports: [SportCount]
    public let meals: Meals
    /// The posts tagged with it, newest first.
    public let posts: [PlaceVisit]

    public init(
        key: PlaceKey, place: Place, visits: Int, people: Int, stars: Double?, raters: Int, myStars: Int?,
        sports: [SportCount], meals: Meals, posts: [PlaceVisit]
    ) {
        (self.key, self.place, self.visits, self.people) = (key, place, visits, people)
        (self.stars, self.raters, self.myStars) = (stars, raters, myStars)
        (self.sports, self.meals, self.posts) = (sports, meals, posts)
    }

    /// A place nobody in the squad posted from yet: its page shows it empty.
    public static func empty(_ place: Place, key: PlaceKey, myStars: Int? = nil) -> PlacePage {
        PlacePage(
            key: key, place: place, visits: 0, people: 0, stars: nil, raters: 0, myStars: myStars, sports: [],
            meals: .none, posts: [])
    }

    /// The stars a member's score can have.
    public static let scores = 1...5

    /// How many 训练 were posted there.
    public var trainings: Int { posts.count - meals.count }
}

/// One post tagged with the place, for the page's 动态.
public struct PlaceVisit: Equatable, Sendable, Identifiable {
    public enum Kind: Equatable, Sendable {
        /// A 训练, with its sport when this build can read it.
        case trained(Activity?)
        case healthyMeal
        case cheatMeal
    }

    public let checkIn: CheckInID
    public let member: MemberID
    public let kind: Kind
    public let minutes: Int?
    public let day: LocalDay
    public let createdAt: Timestamp

    public var id: CheckInID { checkIn }

    public init(
        checkIn: CheckInID, member: MemberID, kind: Kind, minutes: Int?, day: LocalDay, createdAt: Timestamp
    ) {
        (self.checkIn, self.member, self.kind, self.minutes) = (checkIn, member, kind, minutes)
        (self.day, self.createdAt) = (day, createdAt)
    }
}

/// The server, as a place's page needs it: `Backend`'s API adapter, or the in-memory squad.
public protocol PlaceBook: Sendable {
    /// The place's page in the squad; nil when no post in its 动态 was tagged with it.
    func page(of key: PlaceKey, in squad: SquadID) async throws(FeedError) -> PlacePage?
    /// Gives the member's score for the place, 1 to 5, over any earlier one. Safe to repeat.
    func rate(_ key: PlaceKey, stars: Int) async throws(FeedError)
}
