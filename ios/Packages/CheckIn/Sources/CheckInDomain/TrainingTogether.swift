import Contracts
import Foundation

/// 一起练 on a new 训练: the squadmates the member can name, and the ones the compose page
/// offers at a tap (Tracy, 2026-11-10): whoever named the member on a 训练 that day, then whoever
/// posted a 训练 that day starting within an hour of the member's own. A Health workout picked
/// and the people picked never change each other.
public struct TrainingTogether: Hashable, Sendable {
    /// The squadmates the member may name, as the squad's today lists them, the member left out.
    public let mates: [SquadmateToday]
    /// The squadmates' 训练 the page offers, those naming the member first, one a squadmate.
    public let hints: [Hint]

    /// A squadmate's 训练 the member may have trained with.
    public struct Hint: Hashable, Sendable, Identifiable {
        public let mate: MemberID
        public let activity: Activity
        public let minutes: WorkoutMinutes?
        /// When it started, on the member's clock, as an hour and minute.
        public let startTime: StartTime?
        /// Whether the squadmate named the member on it: tapping it then also fills the sport,
        /// start and minutes, unless a Health workout is picked.
        public let namedMe: Bool

        public var id: MemberID { mate }

        public init(
            mate: MemberID, activity: Activity, minutes: WorkoutMinutes?, startTime: StartTime?, namedMe: Bool
        ) {
            (self.mate, self.activity, self.minutes, self.startTime, self.namedMe) =
                (mate, activity, minutes, startTime, namedMe)
        }
    }

    public static let none = TrainingTogether(mates: [], hints: [])

    /// How far apart two starts may be for a squadmate's 训练 to be offered.
    public static let window = 60
    /// The most hints the page offers.
    public static let hintLimit = 4

    public init(mates: [SquadmateToday], hints: [Hint]) {
        (self.mates, self.hints) = (mates, hints)
    }

    /// What `home` offers for a 训练 on `day` that started at `start` on the member's clock (a
    /// Health workout's start, else the start picked by hand); with no start, every squadmate who
    /// trained that day. Only 训练 shared to the member's squad count.
    public init(home: Home, on day: LocalDay, around start: StartTime?) {
        let mates = home.today.members.filter { $0.member != home.member }
        let ids = Set(mates.map(\.member))
        var seen = Set<MemberID>()
        var hints: [Hint] = []
        let posts = home.checkIns.reversed().filter {
            ids.contains($0.member) && $0.day == day && $0.audience.squads.contains(home.squad.id)
        }
        for checkIn in posts {
            guard case .trained(let training) = checkIn.entry else { continue }
            let started = Self.start(of: checkIn, training, in: home.timeZone)
            let namedMe = training.trainedWith.members.contains(home.member)
            guard namedMe || Self.near(started, start) else { continue }
            guard seen.insert(checkIn.member).inserted else { continue }
            hints.append(
                Hint(
                    mate: checkIn.member, activity: training.activity, minutes: training.minutes,
                    startTime: started, namedMe: namedMe))
        }
        let named = hints.filter(\.namedMe) + hints.filter { !$0.namedMe }
        self.init(mates: mates, hints: Array(named.prefix(Self.hintLimit)))
    }

    /// The squadmate's 训练's start on the member's clock: its workout's, else the start picked,
    /// else when it was posted less its minutes.
    static func start(of checkIn: CheckIn, _ training: Training, in timeZone: TimeZone) -> StartTime? {
        if let workout = training.workout { return clock(workout.startedAt.date, in: timeZone) }
        if let picked = training.startTime { return picked }
        let back = TimeInterval((training.minutes?.value ?? 0) * 60)
        return clock(checkIn.createdAt.date.addingTimeInterval(-back), in: timeZone)
    }

    /// `moment` as an hour and minute in `timeZone`.
    public static func clock(_ moment: Date, in timeZone: TimeZone) -> StartTime? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.hour, .minute], from: moment)
        guard let hour = parts.hour, let minute = parts.minute else { return nil }
        return try? StartTime(hour: hour, minute: minute)
    }

    private static func near(_ started: StartTime?, _ reference: StartTime?) -> Bool {
        guard let reference else { return true }
        guard let started else { return false }
        return abs(started.minuteOfDay - reference.minuteOfDay) <= window
    }
}

extension StartTime {
    fileprivate var minuteOfDay: Int { hour * 60 + minute }
}

extension Home {
    /// What 一起练 offers for the member's 训练 on `day` (today when nil): around the start of
    /// `workout` when one from Health is picked, else around `startTime`.
    public func together(on day: LocalDay?, workout: Workout?, startTime: StartTime?) -> TrainingTogether {
        let start = workout.flatMap { TrainingTogether.clock($0.startedAt.date, in: timeZone) } ?? startTime
        guard let day = day ?? mine?.day else { return .none }
        return TrainingTogether(home: self, on: day, around: start)
    }

    /// 我也发: the squadmate's 训练 `post` as a hint to start the member's own from, when it is one
    /// in this home shared to the squad and naming the member.
    public func hint(along post: CheckInID) -> TrainingTogether.Hint? {
        guard let checkIn = checkIns.first(where: { $0.id == post }), checkIn.member != member,
            checkIn.audience.squads.contains(squad.id), case .trained(let training) = checkIn.entry,
            training.trainedWith.members.contains(member)
        else { return nil }
        return TrainingTogether.Hint(
            mate: checkIn.member, activity: training.activity, minutes: training.minutes,
            startTime: TrainingTogether.start(of: checkIn, training, in: timeZone), namedMe: true)
    }
}
