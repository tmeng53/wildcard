import CheckInDomain
import Contracts
import Foundation

func id(_ number: Int) -> UUID {
    UUID(uuidString: "00000000-0000-0000-0000-\(String(format: "%012d", number))") ?? UUID()
}

let myID = MemberID(id(1))
let mate = MemberID(id(2))
let resting = MemberID(id(3))
let squadID = SquadID(id(10))
let losAngeles = TimeZone(identifier: "America/Los_Angeles") ?? .gmt
/// Tuesday 2026-10-20, 10:00 in Los Angeles.
let tuesdayMorning = Date(timeIntervalSince1970: 1_792_515_600)
let tuesday = LocalDay(at: tuesdayMorning, in: losAngeles)

func entry(_ member: MemberID, _ training: TrainingStatus, plannedRest: Bool = false, since: Int64? = nil)
    -> SquadmateToday
{
    SquadmateToday(
        member: member, catchphrase: nil, character: nil, day: tuesday, training: training, latestMeal: nil,
        plannedRest: plannedRest,
        firstCheckInAt: since.map(Timestamp.init(millisecondsSince1970:)))
}

/// Mate trained this morning, I haven't checked in, the third member rests today by plan.
func sampleToday() -> SquadToday {
    SquadToday(
        squad: squadID,
        members: [
            entry(mate, .trained, since: 1_792_510_000_000), entry(myID, .notCheckedIn),
            entry(resting, .notCheckedIn, plannedRest: true),
        ],
        today: TodayCounts(trained: 1, disclaimer: 0, resting: 1, everyoneTrained: false),
        myWeek: MyWeek(
            firstDay: tuesday.weekStart, lastDay: tuesday.weekStart.adding(days: 6),
            week: WeekCount(trainedDays: 1, plannedDays: 5)),
        squadWeek: WeekCount(trainedDays: 14, plannedDays: 22))
}

func sampleHome(today: SquadToday = sampleToday(), checkIns: [CheckIn] = []) -> Home {
    let plan = try? WeeklyPlan(
        member: myID, weekStart: tuesday.weekStart,
        days: [.train(nil), .train(.sport("yoga")), .rest, .train(nil), .train(nil), .train(nil), .rest])
    return Home(
        member: myID, timeZone: losAngeles,
        squad: Squad(
            id: squadID, name: "周三不练腿", inviteCode: "K7M2QX9P", members: [mate, myID, resting], captain: myID),
        today: today, plan: plan ?? { fatalError("a seven-day plan") }(), checkIns: checkIns)
}

/// The server, scripted: online or not, refusing or not, recording what reached it.
actor ScriptedBackend: CheckInBackend {
    var saved: Home?
    var server: Home?
    var failure: CheckInError?
    /// Fails uploads after this many succeed, with `.notSent`.
    var uploadsBeforeFailing = Int.max
    private(set) var uploads: [UUID] = []
    private(set) var saves: [CheckIn] = []
    private var reactionList: [CheckInID: [Reaction]] = [:]

    init(saved: Home? = nil, server: Home? = sampleHome()) {
        self.saved = saved
        self.server = server
    }

    func set(failure: CheckInError?) { self.failure = failure }
    func set(uploadsBeforeFailing count: Int) { uploadsBeforeFailing = count }
    func set(server home: Home?) { server = home }

    /// Holds saves until `releaseSaves()`, so a test can act while one is on its way.
    private var heldSaves: [CheckedContinuation<Void, Never>]?
    private(set) var savesWaiting = 0
    func holdSaves() { heldSaves = [] }
    func releaseSaves() {
        let held = heldSaves ?? []
        heldSaves = nil
        for save in held { save.resume() }
    }

    func savedHome() async -> Home? { saved }

    func home() async throws(CheckInError) -> Home? {
        if let failure { throw failure }
        saved = server
        return server
    }

    func upload(_ photo: PreparedPhoto) async throws(CheckInError) -> PhotoRef {
        if let failure { throw failure }
        guard uploadsBeforeFailing > 0 else { throw .notSent }
        uploadsBeforeFailing -= 1
        uploads.append(photo.id)
        do { return try PhotoRef(path: "\(myID)/\(photo.id.uuidString.lowercased())") } catch { throw .refused }
    }

    func save(_ checkIn: CheckIn) async throws(CheckInError) -> CheckIn {
        if heldSaves != nil {
            savesWaiting += 1
            await withCheckedContinuation { heldSaves?.append($0) }
        }
        if let failure { throw failure }
        saves.append(checkIn)
        if var home = server, !home.checkIns.contains(where: { $0.id == checkIn.id }) {
            home.today = home.today.countingMine(checkIn)
            home.checkIns.append(checkIn)
            server = home
        }
        return checkIn
    }

    func reactions(to checkIn: CheckInID) async throws(CheckInError) -> [Reaction] {
        if let failure { throw failure }
        return reactionList[checkIn] ?? []
    }

    func react(_ emoji: Emoji, to checkIn: CheckInID) async throws(CheckInError) {
        if let failure { throw failure }
        reactionList[checkIn] = [Reaction(member: myID, emoji: emoji, reactedAt: Timestamp(millisecondsSince1970: 0))]
    }

    func removeReaction(from checkIn: CheckInID) async throws(CheckInError) {
        if let failure { throw failure }
        reactionList[checkIn] = []
    }

    var serverPokes = SquadPokes.none
    private(set) var pats: [MemberID] = []
    func set(pokes: SquadPokes) { serverPokes = pokes }

    func pokes(in squad: SquadID) async throws(CheckInError) -> SquadPokes {
        if let failure { throw failure }
        return serverPokes
    }

    func pat(_ member: MemberID, in squad: SquadID) async throws(CheckInError) {
        if let failure { throw failure }
        pats.append(member)
        serverPokes.sent.insert(member)
    }
}

actor MemoryOutbox: Outbox {
    private(set) var kept: [PendingCheckIn] = []

    func load() async -> [PendingCheckIn] { kept }
    func save(_ pending: [PendingCheckIn]) async { kept = pending }
}

/// Ids handed out in order: 100, 101, …
final class Counter: @unchecked Sendable {  // Only the main actor's store calls it, one call at a time.
    private var next = 100
    func callAsFunction() -> UUID {
        defer { next += 1 }
        return id(next)
    }
}

@MainActor
func store(_ backend: ScriptedBackend, outbox: MemoryOutbox = MemoryOutbox(), now: Date = tuesdayMorning) -> TodayStore
{
    let counter = Counter()
    return TodayStore(backend: backend, outbox: outbox, now: { now }, newID: { counter() })
}

func photo(_ number: Int) -> PreparedPhoto {
    PreparedPhoto(id: id(number), jpeg: Data([UInt8(number)]), size: try? PhotoSize(width: 1080, height: 1350))
}
