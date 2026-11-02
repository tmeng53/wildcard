import Contracts
import FeedDomain
import Foundation

/// The member's squad day as the 6pm push carries it (the server's `event`): the squad's week,
/// who patted them, and teammates' check-ins today, newest first, at most four, with how many
/// more there are. Nothing is loaded when the push opens; this is all it shows.
public struct DailyPush: Hashable, Sendable {
    /// The member the push is for.
    public let viewer: MemberID
    /// Days trained this week, added up over the squad, and days planned.
    public let squadWeek: WeekCount
    /// Who patted the member since their last push, first first.
    public let pokedBy: [MemberID]
    public internal(set) var posts: [PushPost]
    /// Teammates' check-ins today beyond `posts`, for 「还有 n 条」.
    public let more: Int
    /// Nobody else checked in today. A push whose posts didn't fit carries none, yet `more` counts them.
    public var nobodyPosted: Bool { posts.isEmpty && more == 0 }
    private let names: [MemberID: String]

    /// Reads the push's `event`, as JSON.
    public init(event: Data) throws(DailyPushError) {
        guard let wire = try? JSONDecoder().decode(Wire.self, from: event), wire.kind == "dailyProgress",
            let today = wire.today, let first = today.members.first
        else { throw .unreadable }
        let members = today.members.map(\.id)
        func member(_ index: Int) throws(DailyPushError) -> MemberID {
            guard members.indices.contains(index) else { throw .unreadable }
            return members[index]
        }
        viewer = first.id
        squadWeek = WeekCount(trainedDays: wire.squadTrainedDays, plannedDays: wire.squadPlannedDays)
        names = Dictionary(today.members.compactMap { each in each.name.map { (each.id, $0) } }) { first, _ in first }
        more = max(today.more, 0)
        var pokers: [MemberID] = []
        for index in today.pokedBy ?? [] { pokers.append(try member(index)) }
        pokedBy = pokers
        var posts: [PushPost] = []
        for post in today.posts {
            var newestFirst: [(MemberID, Emoji)] = []
            for pair in post.reactions {
                guard let emoji = try? Emoji(pair.emoji) else { continue }
                newestFirst.append((try member(pair.member), emoji))
            }
            // The push carries order, not times: older ones get earlier moments.
            let count = Int64(newestFirst.count)
            let responses = Responses<Emoji>(
                newestFirst.enumerated().map { index, pair in
                    .init(member: pair.0, kind: pair.1, moment: Timestamp(millisecondsSince1970: count - Int64(index)))
                })
            guard let posted = try? Timestamp(post.posted) else { throw .unreadable }
            posts.append(
                PushPost(
                    id: post.id, author: try member(post.author), entry: try PushEntry(post), posted: posted,
                    text: post.text, reactions: responses, unseen: max(post.reactionCount - responses.all.count, 0)))
        }
        self.posts = posts
    }

    /// What a member is called: their nickname, or nil before they made their character.
    public func name(of member: MemberID) -> String? { names[member] }

    /// Everyone the push names, the member first.
    public var members: [MemberID] {
        var seen: [MemberID] = [viewer]
        for member in pokedBy + posts.flatMap({ [$0.author] + $0.reactions.all.map(\.member) })
        where !seen.contains(member) {
            seen.append(member)
        }
        return seen
    }
}

/// One teammate's check-in today, as the push carries it: no photos, its words cut short.
public struct PushPost: Hashable, Sendable, Identifiable {
    public let id: CheckInID
    public let author: MemberID
    public let entry: PushEntry
    /// When it was posted.
    public let posted: Timestamp
    /// The caption, or the 请假条's text.
    public let text: String?
    /// The reactions the push carries: the newest, and the member's own.
    public internal(set) var reactions: Responses<Emoji>
    /// Reactions the push left out, counted in 「+n」.
    public let unseen: Int

    /// The heads at the start of the reaction row, newest first, at most `limit`.
    public func latest(_ limit: Int) -> [Responses<Emoji>.Response] {
        Array(reactions.all.reversed().prefix(limit))
    }

    /// Everyone who reacted, the unseen included.
    public var reactionCount: Int { reactions.all.count + unseen }
}

/// What a teammate checked in.
public enum PushEntry: Hashable, Sendable {
    /// 练了, the sport when this build knows it, and the minutes when the member gave them.
    case trained(Activity?, minutes: WorkoutMinutes?)
    case healthyMeal
    case cheatMeal
    case disclaimer

    init(_ post: WirePost) throws(DailyPushError) {
        switch post.kind {
        case "trained":
            // Minutes outside the range the app takes are left out, as a sport it doesn't know is.
            let minutes = post.minutes.flatMap { try? WorkoutMinutes($0) }
            if let name = post.customSport, let custom = try? CustomSport(name) {
                self = .trained(.custom(custom), minutes: minutes)
            } else {
                self = .trained(post.sport.flatMap(Sport.init(rawValue:)).map(Activity.sport), minutes: minutes)
            }
        case "healthyMeal": self = .healthyMeal
        case "cheatMeal": self = .cheatMeal
        case "disclaimer": self = .disclaimer
        default: throw .unreadable
        }
    }
}

/// The push's `event` as the server writes it (`api/apps/server/src/flows/daily-push-today.ts`).
struct Wire: Decodable {
    struct Member: Decodable {
        let id: MemberID
        let name: String?
    }

    struct Reaction: Decodable {
        let member: Int
        let emoji: String

        init(from decoder: Decoder) throws {
            var pair = try decoder.unkeyedContainer()
            member = try pair.decode(Int.self)
            emoji = try pair.decode(String.self)
        }
    }

    struct Today: Decodable {
        let members: [Member]
        let posts: [WirePost]
        let more: Int
        let pokedBy: [Int]?
    }

    let kind: String
    let squadTrainedDays: Int
    let squadPlannedDays: Int
    let today: Today?
}

/// A post in the push's `today`.
struct WirePost: Decodable {
    let id: CheckInID
    let author: Int
    let kind: String
    let sport: String?
    let customSport: String?
    /// A 练了's minutes; pushes from before the server sent them have none.
    let minutes: Int?
    let posted: String
    let text: String?
    let reactions: [Wire.Reaction]
    let reactionCount: Int

    enum CodingKeys: String, CodingKey {
        case id, kind, sport, customSport, minutes, text, reactions, reactionCount
        case author = "by"
        case posted = "at"
    }
}
