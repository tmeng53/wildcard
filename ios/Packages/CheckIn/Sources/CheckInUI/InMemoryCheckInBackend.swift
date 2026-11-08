import AvatarArt
import CheckInDomain
import Contracts
import DesignSystemUI
import Foundation

/// A squad kept in memory, for previews, UI tests and builds that don't talk to the API. It
/// starts from a given home and counts each post the way the API does.
public actor InMemoryCheckInBackend: CheckInBackend {
    private var current: Home?
    private var reactionsByCheckIn: [CheckInID: [Reaction]] = [:]
    private var photoCount = 0
    private var squadPokes: SquadPokes
    private var sidelineCoach: SidelineCoach?
    private var memberNotes: [CoachMemberNote]
    private var opened: CoachMemberNote?
    private var openedLetterID: Int?

    public init(
        home: Home?, pokes: SquadPokes = .none, coach: SidelineCoach? = nil, notes: [CoachMemberNote] = []
    ) {
        current = home
        squadPokes = pokes
        sidelineCoach = coach
        memberNotes = notes
    }

    /// The squad the screens are reviewed against: 本周小队 14/22, eight members on the scene in
    /// every state (three trained: running, yoga, swimming; one 请假条; one rest day; two not yet)
    /// and the member not checked in, today being `now`'s day in the device's zone. A smaller
    /// `size` (1 to 8, me included) keeps the 请假条, then the runner, the rest day and so on. Pass
    /// `member` and `squad` to share them with another screen's sample, such as 动态's.
    /// Everyone goes by the approved home's names (小米, 阿杰, 豆豆, …). With `patted`, the
    /// runner (小米) and the 请假条 (阿杰) patted me an hour ago, so the home plays it. With `coach`,
    /// the squad has hired 毛头, who wrote today's 战术板 line. With `together`, the home opens on
    /// that celebration: `.wave` reaches the squad's week (22/22), `.stack` has the yoga teammate
    /// run like 小米, and `.bump` has me trained too.
    public static func sampleSquad(
        now: Date, size: Int = 8, member: MemberID = MemberID(UUID()), squad squadID: SquadID = SquadID(UUID()),
        patted: Bool = false, coach: Bool = false, coachNote: Bool = false, coachLetter: Bool = false,
        together: SquadCelebration.Kind? = nil, meals: Bool = false
    ) -> InMemoryCheckInBackend {
        let (zone, day) = (TimeZone.current, LocalDay(at: now, in: TimeZone.current))
        let everyone = (0..<7).map { _ in MemberID(UUID()) }
        let kept = Set([3, 0, 4, 1, 5, 2, 6].prefix(min(7, max(0, size - 1))).map { everyone[$0] })
        func at(_ hoursAgo: Double) -> Timestamp { Timestamp(now.addingTimeInterval(-hoursAgo * 3600)) }
        func mate(
            _ id: MemberID, _ training: TrainingStatus, rest: Bool = false, since first: Timestamp? = nil,
            title: WornTitle? = nil
        ) -> SquadmateToday {
            SquadmateToday(
                member: id, catchphrase: nil, character: character(of: id, everyone: everyone), day: day,
                training: training, latestMeal: nil, plannedRest: rest, firstCheckInAt: first, title: title)
        }
        // Two wear a weekly title beside their name, as the approved 头衔徽章 home shows.
        let members =
            [
                mate(everyone[0], .trained, since: at(5), title: worn("早八战神", "shield", "track", "sun.max.fill")),
                mate(everyone[1], .trained, since: at(4)), mate(everyone[2], .trained, since: at(3)),
                mate(everyone[3], .disclaimer, since: at(2), title: worn("请假条艺术家", "circle", "pool", "doc.text.fill")),
                mate(everyone[4], .notCheckedIn, rest: true), mate(everyone[5], .notCheckedIn),
                mate(everyone[6], .notCheckedIn),
            ].filter { kept.contains($0.member) }
            + [mate(member, together == .bump ? .trained : .notCheckedIn, since: together == .bump ? at(1) : nil)]
        // My week so far: a swim yesterday and a run the day before, where those are this week.
        let earlier = [1, 2].map { day.adding(days: -$0) }.filter { $0.weekStart == day.weekStart }
        let checkIns =
            sampleCheckIns(by: everyone, on: day, in: squadID, secondSport: together == .stack ? "run" : "yoga") {
                at($0)
            }.filter { kept.contains($0.member) }
            + (meals ? sampleMeals(by: everyone, on: day, in: squadID) { at($0) } : [])
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
                        name: Bundle.module.inAppLanguage.localizedString(forKey: "周三不练腿俱乐部", value: nil, table: nil),
                        inviteCode: "K7M2QX9P", members: everyone.filter(kept.contains) + [member], captain: member),
                    today: SquadToday(
                        squad: squadID, members: members,
                        today: counts(of: members),
                        myWeek: MyWeek(
                            firstDay: day.weekStart, lastDay: day.weekStart.adding(days: 6),
                            week: WeekCount(trainedDays: earlier.count, plannedDays: 5)),
                        squadWeek: squadWeek(of: members.count, reached: together == .wave)),
                    plan: plan, checkIns: checkIns)
            },
            pokes: patted ? pats(by: [everyone[0], everyone[3]].filter(kept.contains), at: at) : .none,
            coach: sideline(coach || coachNote, coachLetter, now, squadID), notes: sampleNotes(coachNote, now, squadID))
    }

    /// The squad's week at 人均 3 天, the default goal: 14 days so far, or the whole goal once
    /// everyone `reached` it together.
    private static func squadWeek(of members: Int, reached: Bool) -> WeekCount {
        WeekCount(trainedDays: reached ? 3 * members : 14, plannedDays: 3 * members)
    }

    /// 毛头's morning note to me, as the approved 便条 shows it, when `shown`.
    private static func sampleNotes(_ shown: Bool, _ now: Date, _ squad: SquadID) -> [CoachMemberNote] {
        guard shown else { return [] }
        let words = Bundle.module.inAppLanguage
        return [
            CoachMemberNote(
                id: 1, squad: squad, day: LocalDay(at: now, in: CoachNote.timeZone),
                text: words.localizedString(forKey: "今天出赛表写的是力量。病刚好，重量先打八折，我在场边数着。", value: nil, table: nil),
                coach: CoachSpeaker(id: "xiaohun", name: words.localizedString(forKey: "毛头", value: nil, table: nil)))
        ]
    }

    /// A sample title, its words from the catalog.
    private static func worn(_ key: String, _ shape: String, _ colour: String, _ glyph: String) -> WornTitle {
        WornTitle(
            title: Bundle.module.inAppLanguage.localizedString(forKey: key, value: nil, table: nil),
            badge: TitleBadge(shape: shape, colour: colour, glyph: glyph))
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
            let nickname = try? Nickname(
                Bundle.module.inAppLanguage.localizedString(forKey: names[index], value: nil, table: nil))
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
        by mates: [MemberID], on day: LocalDay, in squad: SquadID, secondSport: Sport = "yoga",
        at time: (Double) -> Timestamp
    ) -> [CheckIn] {
        guard let audience = try? Audience([squad]) else { return [] }
        func checkIn(_ who: MemberID, _ hoursAgo: Double, _ entry: CheckIn.Entry) -> CheckIn {
            CheckIn(
                id: CheckInID(UUID()), member: who, day: day, createdAt: time(hoursAgo), audience: audience,
                entry: entry)
        }
        let leave = try? Disclaimer(
            Bundle.module.inAppLanguage.localizedString(forKey: "加班到十点，腿说它也想下班", value: nil, table: nil))
        return [
            checkIn(mates[0], 5, .trained(Training(activity: .sport("run")))),
            checkIn(mates[1], 4, .trained(Training(activity: .sport(secondSport)))),
            checkIn(mates[2], 3, .trained(Training(activity: .sport("swim")))),
        ] + (leave.map { [checkIn(mates[3], 2, .disclaimer($0))] } ?? [])
    }

    /// With `meals`, two teammates' latest posts are meals: 小米 had a salad after her run, and
    /// Leo, who hasn't trained, owned up to a boba. Both eat on the home.
    private static func sampleMeals(
        by mates: [MemberID], on day: LocalDay, in squad: SquadID, at time: (Double) -> Timestamp
    ) -> [CheckIn] {
        let words = Bundle.module.inAppLanguage
        guard let audience = try? Audience([squad]),
            let salad = try? Caption(words.localizedString(forKey: "练完来碗沙拉", value: nil, table: nil)),
            let boba = try? Caption(words.localizedString(forKey: "奶茶续命", value: nil, table: nil))
        else { return [] }
        return [
            CheckIn(
                id: CheckInID(UUID()), member: mates[0], day: day, createdAt: time(1), audience: audience,
                entry: .healthyMeal(Meal(caption: salad))),
            CheckIn(
                id: CheckInID(UUID()), member: mates[5], day: day, createdAt: time(0.5), audience: audience,
                entry: .cheatMeal(Meal(caption: boba))),
        ]
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
        // As the API: no 请假条 on a day the member has a 练了 (补打卡 can pick a past day).
        if case .disclaimer = checkIn.entry {
            let trainedThatDay = home.checkIns.contains { saved in
                guard saved.member == home.member, saved.day == checkIn.day, case .trained = saved.entry else {
                    return false
                }
                return true
            }
            if trainedThatDay || (checkIn.day == home.mine?.day && home.mine?.training == .trained) {
                throw .alreadyTrained
            }
        }
        home.today = home.today.countingMine(checkIn, squadSaw: home.squadSees(on: checkIn.day))
        home.checkIns.append(checkIn)
        current = home
        return checkIn
    }

    public func edit(_ checkIn: CheckIn) async throws(CheckInError) -> CheckIn {
        guard var home = current, let index = home.checkIns.firstIndex(where: { $0.id == checkIn.id }) else {
            throw .refused
        }
        home.checkIns[index] = checkIn
        current = home
        return checkIn
    }

    public func delete(_ checkIn: CheckInID) async throws(CheckInError) {
        current?.checkIns.removeAll { $0.id == checkIn }
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

    /// The sample squad's member has no profile to keep a zone on.
    public func followPhoneZone() async throws(CheckInError) -> Bool { false }

    public func pokes(in squad: SquadID) async throws(CheckInError) -> SquadPokes {
        squadPokes
    }

    public func pat(_ member: MemberID, in squad: SquadID) async throws(CheckInError) {
        guard current?.squad.members.contains(member) ?? false else { throw .notInSquad }
        squadPokes.sent.insert(member)
    }

    public func coach(in squad: SquadID) async throws(CheckInError) -> SidelineCoach? { sidelineCoach }

    public func coachNotes(in squads: [SquadID]) async throws(CheckInError) -> [CoachMemberNote] {
        squads.compactMap { squad in memberNotes.first { $0.squad == squad } }
    }

    public func putAway(_ note: CoachMemberNote) async throws(CheckInError) {
        memberNotes.removeAll { $0.id == note.id }
        opened = note
    }

    public func openedNote() async -> CoachMemberNote? { opened }

    /// 毛头 takes a few seconds over its letter to 帕帕, as the model would, so 「交接中」 shows.
    public func writeLetter(in squad: SquadID) async throws(CheckInError) -> CoachLetter? {
        try? await Task.sleep(for: .seconds(3))
        let letter = Self.sampleLetter(in: squad, now: .now)
        sidelineCoach = SidelineCoach(coach: letter.recipient, note: nil, letter: letter)
        return letter
    }

    public func openedLetter() async -> Int? { openedLetterID }

    public func opened(_ letter: CoachLetter) async { openedLetterID = letter.id }
}

/// Posts waiting to go out, kept in memory: for previews, UI tests and tests.
public actor InMemoryOutbox: Outbox {
    private var kept: [PendingCheckIn] = []

    public init() {}

    public func load() async -> [PendingCheckIn] { kept }

    public func save(_ pending: [PendingCheckIn]) async { kept = pending }
}
