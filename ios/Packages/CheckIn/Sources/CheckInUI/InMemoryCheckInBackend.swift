import CheckInDomain
import Contracts
import Foundation

/// A squad kept in memory, for previews, UI tests and builds that don't talk to the API. It
/// starts from a given home and counts each post the way the API does.
public actor InMemoryCheckInBackend: CheckInBackend {
    private var current: Home?
    private var reactionsByCheckIn: [CheckInID: [Reaction]] = [:]
    private var photoCount = 0

    public init(home: Home?) {
        current = home
    }

    /// The squad the screens are reviewed against: 本周小队 14/22 and 3 trained today (spec
    /// rev 186), with the member not checked in, today being `now`'s day in the device's zone.
    public static func sampleSquad(now: Date) -> InMemoryCheckInBackend {
        let zone = TimeZone.current
        let day = LocalDay(at: now, in: zone)
        let member = MemberID(UUID())
        let mates = (0..<4).map { _ in MemberID(UUID()) }
        let moment = Timestamp(now.addingTimeInterval(-3600))
        let squadID = SquadID(UUID())
        func mate(_ id: MemberID, _ training: TrainingStatus, since first: Timestamp?) -> SquadmateToday {
            SquadmateToday(
                member: id, catchphrase: nil, day: day, training: training, latestMeal: nil, plannedRest: false,
                firstCheckInAt: first)
        }
        let members =
            mates.prefix(3).map { mate($0, .trained, since: moment) } + [
                mate(mates[3], .notCheckedIn, since: nil), mate(member, .notCheckedIn, since: nil),
            ]
        let plan = try? WeeklyPlan(
            member: member, weekStart: day.weekStart,
            days: [.train(.sport(.run)), .train(nil), .rest, .train(.sport(.run)), .train(nil), .train(nil), .rest])
        return InMemoryCheckInBackend(
            home: plan.map { plan in
                Home(
                    member: member, timeZone: zone,
                    squad: Squad(
                        id: squadID,
                        name: Bundle.module.localizedString(forKey: "周三不练腿俱乐部", value: nil, table: nil),
                        inviteCode: "K7M2QX9P", members: mates + [member]),
                    today: SquadToday(
                        squad: squadID, members: members,
                        today: TodayCounts(trained: 3, disclaimer: 0, resting: 0, everyoneTrained: false),
                        myWeek: MyWeek(
                            firstDay: day.weekStart, lastDay: day.weekStart.adding(days: 6),
                            week: WeekCount(trainedDays: 2, plannedDays: 5), lifetimeTrainedDays: 40),
                        squadWeek: WeekCount(trainedDays: 14, plannedDays: 22)),
                    plan: plan, checkIns: [])
            })
    }

    public func savedHome() async -> Home? { current }

    public func home() async throws(CheckInError) -> Home? { current }

    public func upload(_ photo: PreparedPhoto) async throws(CheckInError) -> PhotoRef {
        photoCount += 1
        do { return try PhotoRef(path: "memory/\(photoCount)") } catch { throw .refused }
    }

    public func save(_ checkIn: CheckIn) async throws(CheckInError) -> CheckIn {
        guard var home = current else { throw .notInSquad }
        if let saved = home.checkIns.first(where: { $0.id == checkIn.id }) { return saved }
        if case .disclaimer = checkIn.entry, let mine = home.mine {
            switch mine.training {
            case .trained: throw .alreadyTrained
            case .disclaimer: throw .disclaimerAlreadyPosted
            case .notCheckedIn: break
            }
        }
        home.today = home.today.countingMine(checkIn)
        home.checkIns.append(checkIn)
        current = home
        return checkIn
    }

    public func reactions(to checkIn: CheckInID) async throws(CheckInError) -> [Reaction] {
        reactionsByCheckIn[checkIn] ?? []
    }

    public func react(_ kind: ReactionKind, to checkIn: CheckInID) async throws(CheckInError) {
        guard let member = current?.member else { throw .notInSquad }
        var list = (reactionsByCheckIn[checkIn] ?? []).filter { $0.member != member }
        list.append(Reaction(member: member, kind: kind, reactedAt: Timestamp(Date())))
        reactionsByCheckIn[checkIn] = list
    }

    public func removeReaction(from checkIn: CheckInID) async throws(CheckInError) {
        guard let member = current?.member else { throw .notInSquad }
        reactionsByCheckIn[checkIn]?.removeAll { $0.member == member }
    }
}

/// Posts waiting to go out, kept in memory: for previews, UI tests and tests.
public actor InMemoryOutbox: Outbox {
    private var kept: [PendingCheckIn] = []

    public init() {}

    public func load() async -> [PendingCheckIn] { kept }

    public func save(_ pending: [PendingCheckIn]) async { kept = pending }
}
