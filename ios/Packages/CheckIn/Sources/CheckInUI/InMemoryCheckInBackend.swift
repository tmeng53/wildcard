import AvatarArt
import CheckInDomain
import Contracts
import Foundation

/// A squad kept in memory, for previews, UI tests and builds that don't talk to the API. It
/// starts from a given home and counts each post the way the API does.
public actor InMemoryCheckInBackend: CheckInBackend {
    private var current: Home?
    private var reactionsByCheckIn: [CheckInID: [Reaction]] = [:]
    private var photoCount = 0
    private var squadPokes: SquadPokes

    public init(home: Home?, pokes: SquadPokes = .none) {
        current = home
        squadPokes = pokes
    }

    /// The squad the screens are reviewed against: 本周小队 14/22, eight members on the scene in
    /// every state (three trained: running, yoga, swimming; one 请假条; one rest day; two not yet)
    /// and the member not checked in, today being `now`'s day in the device's zone. A smaller
    /// `size` (1 to 8, me included) keeps the 请假条, then the runner, the rest day and so on. Pass
    /// `member` and `squad` to share them with another screen's sample, such as 动态's.
    /// Everyone goes by the approved home's names (小米, 阿杰, 豆豆, …). With `patted`, the
    /// runner (小米) and the 请假条 (阿杰) patted me an hour ago, so the home plays it.
    public static func sampleSquad(
        now: Date, size: Int = 8, member: MemberID = MemberID(UUID()), squad squadID: SquadID = SquadID(UUID()),
        patted: Bool = false
    ) -> InMemoryCheckInBackend {
        let zone = TimeZone.current
        let day = LocalDay(at: now, in: zone)
        let everyone = (0..<7).map { _ in MemberID(UUID()) }
        let kept = Set([3, 0, 4, 1, 5, 2, 6].prefix(min(7, max(0, size - 1))).map { everyone[$0] })
        let mates = everyone.filter(kept.contains)
        func at(_ hoursAgo: Double) -> Timestamp { Timestamp(now.addingTimeInterval(-hoursAgo * 3600)) }
        func mate(_ id: MemberID, _ training: TrainingStatus, rest: Bool = false, since first: Timestamp? = nil)
            -> SquadmateToday
        {
            SquadmateToday(
                member: id, catchphrase: nil, character: character(of: id, everyone: everyone), day: day,
                training: training, latestMeal: nil, plannedRest: rest, firstCheckInAt: first)
        }
        let members =
            [
                mate(everyone[0], .trained, since: at(5)), mate(everyone[1], .trained, since: at(4)),
                mate(everyone[2], .trained, since: at(3)), mate(everyone[3], .disclaimer, since: at(2)),
                mate(everyone[4], .notCheckedIn, rest: true), mate(everyone[5], .notCheckedIn),
                mate(everyone[6], .notCheckedIn),
            ].filter { kept.contains($0.member) } + [mate(member, .notCheckedIn)]
        // My week so far: a swim yesterday and a run the day before, where those are this week.
        let earlier = [1, 2].map { day.adding(days: -$0) }.filter { $0.weekStart == day.weekStart }
        let checkIns =
            sampleCheckIns(by: everyone, on: day, in: squadID) { at($0) }.filter { kept.contains($0.member) }
            + myEarlierCheckIns(by: member, on: earlier, in: squadID) { at($0) }
        let plan = try? WeeklyPlan(
            member: member, weekStart: day.weekStart,
            days: [.train(.sport("run")), .train(nil), .rest, .train(.sport("run")), .train(nil), .train(nil), .rest])
        return InMemoryCheckInBackend(
            home: plan.map { plan in
                Home(
                    member: member, timeZone: zone,
                    squad: Squad(
                        id: squadID,
                        name: Bundle.module.localizedString(forKey: "周三不练腿俱乐部", value: nil, table: nil),
                        inviteCode: "K7M2QX9P", members: mates + [member], captain: member),
                    today: SquadToday(
                        squad: squadID, members: members,
                        today: counts(of: members),
                        myWeek: MyWeek(
                            firstDay: day.weekStart, lastDay: day.weekStart.adding(days: 6),
                            week: WeekCount(trainedDays: earlier.count, plannedDays: 5)),
                        squadWeek: WeekCount(trainedDays: 14, plannedDays: 22)),
                    plan: plan, checkIns: checkIns)
            },
            pokes: patted ? pats(by: [everyone[0], everyone[3]].filter(kept.contains), at: at) : .none)
    }

    /// `patters` patted me, the first an hour ago and each next one ten minutes later.
    private static func pats(by patters: [MemberID], at time: (Double) -> Timestamp) -> SquadPokes {
        SquadPokes(
            sent: [],
            received: patters.enumerated().map { offset, from in
                ReceivedPoke(from: from, patAt: time(1 - Double(offset) / 6))
            })
    }

    /// The sample squad's names, from the approved home, in the order of `everyone`: the three
    /// who trained, the 请假条, the rest day and the two not yet.
    private static let names = ["小米", "豆豆", "大卫", "阿杰", "Coco", "Leo", "Mia"]

    /// A sample teammate's nickname, on the stand-in look and persona the scene gives them.
    private static func character(of member: MemberID, everyone: [MemberID]) -> MemberCharacter? {
        guard let index = everyone.firstIndex(of: member),
            let nickname = try? Nickname(Bundle.module.localizedString(forKey: names[index], value: nil, table: nil))
        else { return nil }
        return MemberCharacter(
            nickname: nickname,
            look: CharacterLook(
                outfit: StandInCharacter.look(of: member), persona: StandInCharacter.persona(of: member)))
    }

    /// Today's counts of the sample squad's `members`, never 全员上场.
    private static func counts(of members: [SquadmateToday]) -> TodayCounts {
        TodayCounts(
            trained: members.count { $0.training == .trained },
            disclaimer: members.count { $0.training == .disclaimer },
            resting: members.count { $0.plannedRest && $0.training == .notCheckedIn },
            everyoneTrained: false)
    }

    /// The sample squad's check-ins today: three 练了 and a 请假条.
    private static func sampleCheckIns(
        by mates: [MemberID], on day: LocalDay, in squad: SquadID, at time: (Double) -> Timestamp
    ) -> [CheckIn] {
        guard let audience = try? Audience([squad]) else { return [] }
        func checkIn(_ who: MemberID, _ hoursAgo: Double, _ entry: CheckIn.Entry) -> CheckIn {
            CheckIn(
                id: CheckInID(UUID()), member: who, day: day, createdAt: time(hoursAgo), audience: audience,
                entry: entry)
        }
        let leave = try? Disclaimer(
            Bundle.module.localizedString(forKey: "加班到十点，腿说它也想下班", value: nil, table: nil))
        return [
            checkIn(mates[0], 5, .trained(Training(activity: .sport("run")))),
            checkIn(mates[1], 4, .trained(Training(activity: .sport("yoga")))),
            checkIn(mates[2], 3, .trained(Training(activity: .sport("swim")))),
        ] + (leave.map { [checkIn(mates[3], 2, .disclaimer($0))] } ?? [])
    }

    /// The member's own check-ins on `days` (most recent first): a run and a healthy meal, then
    /// a swim. Yesterday's 练了 is the run, so the suggested sport is 跑步 on any weekday.
    private static func myEarlierCheckIns(
        by member: MemberID, on days: [LocalDay], in squad: SquadID, at time: (Double) -> Timestamp
    ) -> [CheckIn] {
        guard let audience = try? Audience([squad]) else { return [] }
        let entries: [[CheckIn.Entry]] = [
            [.trained(Training(activity: .sport("run"))), .healthyMeal(Meal())],
            [.trained(Training(activity: .sport("swim")))],
        ]
        return zip(days, entries).enumerated().flatMap { offset, pair in
            pair.1.map { entry in
                CheckIn(
                    id: CheckInID(UUID()), member: member, day: pair.0, createdAt: time(Double(offset + 1) * 24),
                    audience: audience, entry: entry)
            }
        }
        .sorted { $0.createdAt < $1.createdAt }
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

    public func react(_ emoji: Emoji, to checkIn: CheckInID) async throws(CheckInError) {
        guard let member = current?.member else { throw .notInSquad }
        var list = (reactionsByCheckIn[checkIn] ?? []).filter { $0.member != member }
        list.append(Reaction(member: member, emoji: emoji, reactedAt: Timestamp(Date())))
        reactionsByCheckIn[checkIn] = list
    }

    public func removeReaction(from checkIn: CheckInID) async throws(CheckInError) {
        guard let member = current?.member else { throw .notInSquad }
        reactionsByCheckIn[checkIn]?.removeAll { $0.member == member }
    }

    public func pokes(in squad: SquadID) async throws(CheckInError) -> SquadPokes {
        squadPokes
    }

    public func pat(_ member: MemberID, in squad: SquadID) async throws(CheckInError) {
        guard current?.squad.members.contains(member) ?? false else { throw .notInSquad }
        squadPokes.sent.insert(member)
    }
}

/// Posts waiting to go out, kept in memory: for previews, UI tests and tests.
public actor InMemoryOutbox: Outbox {
    private var kept: [PendingCheckIn] = []

    public init() {}

    public func load() async -> [PendingCheckIn] { kept }

    public func save(_ pending: [PendingCheckIn]) async { kept = pending }
}
