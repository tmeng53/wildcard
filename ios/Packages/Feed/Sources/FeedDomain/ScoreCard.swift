import Contracts

/// A 训练 saved as a 3:4 picture, the 成绩卡 (Tracy, 2026-11-09): what the member picked for this
/// one save, tapping on its preview. Its backdrop (one of the post's photos, its route, its chart,
/// or the sport's colour alone), which of the post's numbers stands big, which numbers of the
/// strip under it are struck out of the picture, the character's pose and whether the squad's
/// name shows. Every number comes from the post's own 成绩条, so a cell struck on the post never
/// appears; nothing here is kept after the sheet closes.
public struct ScoreCard: Hashable, Sendable {
    /// What fills the top of the card.
    public enum Backdrop: Hashable, Sendable {
        case photo(PhotoRef)
        /// The route on a map.
        case map
        /// The heart-rate curve, or a swim's laps.
        case chart
        /// No picture: the whole card in the sport's colour (纯色).
        case plain
    }

    /// What the character does, each a still from a move it already has.
    public enum Pose: Hashable, Sendable, CaseIterable {
        /// The sport's own move, in its kit.
        case sport
        /// The persona's cheer.
        case cheer
        /// Fist pumps, a flex.
        case flex
        /// Holding the prop the member put on in the editor.
        case prop
    }

    /// Under the big number, at most this many of the rest.
    public static let stripLimit = 3

    /// The post's photos, its route and its chart where the post shows them, then 纯色.
    public let backdrops: [Backdrop]
    public private(set) var backdrop: Backdrop
    /// The post's numbers in the strip's order.
    public let numbers: [WorkoutCell]
    /// The big one; nil for a post without numbers.
    public private(set) var hero: WorkoutCell?
    /// Numbers left out of the picture; on the preview they show faded and crossed through.
    public private(set) var struck: Set<WorkoutCell> = []
    /// The poses this character can strike, in the order a tap goes through them.
    public let poses: [Pose]
    public private(set) var pose: Pose
    /// Whether the squad's name shows bottom right (小队名).
    public var showsSquad = true

    /// - Parameters:
    ///   - hasKit: the character has a move of its own for the post's sport.
    ///   - holdsProp: the member's look holds a prop.
    public init(training: Training, hasKit: Bool, holdsProp: Bool) {
        var backdrops: [Backdrop] = training.photos?.all.map(Backdrop.photo) ?? []
        let shown = training.tiles
        if shown.contains(.workout(.map)) { backdrops.append(.map) }
        if shown.contains(.workout(.chart)) { backdrops.append(.chart) }
        backdrops.append(.plain)
        self.backdrops = backdrops
        backdrop = backdrops[0]
        let numbers = Self.numbers(of: training)
        self.numbers = numbers
        hero = Self.firstHero.first { numbers.contains($0) } ?? numbers.first
        let poses = Pose.allCases.filter { pose in
            switch pose {
            case .sport: hasKit
            case .cheer, .flex: true
            case .prop: holdsProp
            }
        }
        self.poses = poses
        pose = poses[0]
    }

    /// The numbers the strip shows, under the big one: the rest, in order, at most three.
    public var strip: [WorkoutCell] {
        Array(numbers.filter { $0 != hero }.prefix(Self.stripLimit))
    }

    /// The strip as saved: without what was struck.
    public var savedStrip: [WorkoutCell] { strip.filter { !struck.contains($0) } }

    /// Whether the card is the sport's colour alone (A) rather than a picture over a band (A2).
    public var isPlain: Bool { backdrop == .plain }

    /// The next number stands big, round to the first.
    public mutating func nextHero() {
        guard let hero, let index = numbers.firstIndex(of: hero) else { return }
        let next = numbers[(index + 1) % numbers.count]
        self.hero = next
        // A number taken up big shows, struck or not.
        struck.remove(next)
    }

    /// Strikes a number of the strip out of the picture, or brings it back.
    public mutating func toggle(_ cell: WorkoutCell) {
        guard strip.contains(cell) else { return }
        if struck.remove(cell) == nil { struck.insert(cell) }
    }

    /// The next pose, round to the first.
    public mutating func nextPose() {
        guard let index = poses.firstIndex(of: pose) else { return }
        pose = poses[(index + 1) % poses.count]
    }

    /// Fills the top with one of the post's own pictures, or 纯色.
    public mutating func pick(_ backdrop: Backdrop) {
        guard backdrops.contains(backdrop) else { return }
        self.backdrop = backdrop
    }

    /// The number that stands big by default, the first the post has: how far a run, a ride or a
    /// walk went, how far down a ski day went, a swim's laps; else how long it took.
    static let firstHero: [WorkoutCell] = [.descent, .distance, .laps, .runs, .duration]

    /// A workout's numbers as its strip has them, or a post's minutes alone.
    static func numbers(of training: Training) -> [WorkoutCell] {
        if let workout = training.workout { return workout.summary.cells }
        return training.minutes == nil ? [] : [.duration]
    }
}

extension ScoreCard {
    /// 本周第 N 次: which of the member's 训练 of that week `checkIn` is, counting the days they
    /// count for and, on one day, the order they were made; nil when `posts` doesn't hold it.
    public static func weekCount(of checkIn: CheckIn, among posts: [CheckIn]) -> Int? {
        let week = checkIn.day.weekStart
        let trainings =
            posts
            .filter { post in
                guard post.member == checkIn.member, post.day.weekStart == week else { return false }
                if case .trained = post.entry { return true }
                return false
            }
            .sorted { ($0.day, $0.createdAt) < ($1.day, $1.createdAt) }
        return trainings.firstIndex { $0.id == checkIn.id }.map { $0 + 1 }
    }
}

extension FeedStore {
    /// 本周第 N 次 for one of the member's 训练, as its 成绩卡 says: read from the first squad it
    /// went to, over its week and the 补打卡 days after, which may count for that week too. Nil
    /// for a post shared to no squad, or when the server can't be reached.
    public func weekCount(of checkIn: CheckIn) async -> Int? {
        guard let squad = checkIn.audience.squads.first else { return nil }
        let week = checkIn.day.weekStart
        guard
            let posts = try? await source.posts(
                in: squad, from: week, through: week.adding(days: 6 + CheckIn.backfillDays))
        else { return nil }
        return ScoreCard.weekCount(of: checkIn, among: posts.map(\.checkIn))
    }
}
