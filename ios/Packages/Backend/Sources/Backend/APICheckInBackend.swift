import APIContract
import CheckInDomain
import Contracts
import Foundation
import OpenAPIRuntime

/// The home and 打卡 over our API, with a copy of the last home kept on the device, as the API
/// sent it, so the home opens offline. The copy is the member's: keep it in their
/// `MemberFolders` folder.
public struct APICheckInBackend: CheckInBackend {
    private let api: WildcardAPI
    private let saved: URL
    /// The newest coach's letter (交接信) opened on this phone.
    private let openedLetterFile: URL
    private let shared: SharedSquad?
    private let now: @Sendable () -> Date
    private let phoneZone: @Sendable () -> TimeZone

    /// - Parameters:
    ///   - directory: where the copy is kept, such as Application Support.
    ///   - shared: where the squad's looks are kept for the 6pm push view.
    ///   - phoneZone: the phone's time zone, which the member's day follows.
    public init(
        api: WildcardAPI, directory: URL, shared: SharedSquad? = nil, now: @escaping @Sendable () -> Date = { Date() },
        phoneZone: @escaping @Sendable () -> TimeZone = { .autoupdatingCurrent }
    ) {
        self.api = api
        saved = directory.appending(path: "home.json")
        openedLetterFile = directory.appending(path: "coach-letter.json")
        self.shared = shared
        self.phoneZone = phoneZone
        self.now = now
    }

    public func savedHome() async -> Home? {
        guard let data = try? Data(contentsOf: saved),
            let copy = try? DeviceJSON.decoder.decode(SavedHome.self, from: data)
        else { return nil }
        return try? copy.home(api: api)
    }

    public func home() async throws(CheckInError) -> Home? {
        do {
            var signedIn = try await api.meWire()
            let zone = phoneZone()
            if signedIn.profile == nil {
                // Saved right after the first sign-in; a member without one gets the phone's zone.
                _ = try await api.save(Profile(timeZone: zone))
                signedIn = try await api.meWire()
            }
            guard let squad = try await api.mySquadWire() else {
                try? FileManager.default.removeItem(at: saved)
                shared?.forget()
                return nil
            }
            let day = LocalDay(at: now(), in: signedIn.profile.flatMap { TimeZone(identifier: $0.timeZone) } ?? zone)
            let squadID = try api.read { () throws(ContractsError) in try Squad(squad).id }
            async let today = api.todayWire(of: squadID)
            async let plan = api.weeklyPlanWire(weekStart: day.weekStart)
            async let checkIns = api.checkInsWire(of: squadID, from: day.adding(days: -2), through: day.adding(days: 2))
            // As far back as a 补打卡 can go, so a Health workout posted to last week stays posted.
            let firstDay = min(day.weekStart, day.adding(days: -CheckIn.backfillDays))
            async let week = api.myCheckInsWire(from: firstDay, through: day)
            let copy = SavedHome(
                version: 1, member: signedIn, squad: squad, today: try await today,
                plan: try await plan,
                checkIns: try await checkIns, week: try await week)
            let home = try copy.home(api: api)
            try? DeviceJSON.write(try DeviceJSON.encoder.encode(copy), to: saved)
            shared?.save(home.today.members)
            return home
        } catch let error as APIError {
            throw CheckInError(error)
        } catch {
            throw .notSent
        }
    }

    public func followPhoneZone() async throws(CheckInError) -> Bool {
        let zone = phoneZone()
        do throws(APIError) {
            guard let profile = try await api.me().profile, profile.timeZone.identifier != zone.identifier else {
                return false
            }
            // The profile is saved whole, so the rest of it is kept.
            _ = try await api.save(
                Profile(
                    timeZone: zone, catchphrase: profile.catchphrase, character: profile.character,
                    jerseyNumber: profile.jerseyNumber))
            return true
        } catch {
            throw CheckInError(error)
        }
    }

    public func upload(_ photo: PreparedPhoto) async throws(CheckInError) -> PhotoRef {
        do { return try await api.upload(photo.jpeg, as: .jpeg) } catch { throw CheckInError(error) }
    }

    public func save(_ checkIn: CheckIn) async throws(CheckInError) -> CheckIn {
        do { return try await api.save(checkIn) } catch { throw CheckInError(error) }
    }

    public func edit(_ checkIn: CheckIn) async throws(CheckInError) -> CheckIn {
        do { return try await api.edit(checkIn) } catch { throw CheckInError(error) }
    }

    public func delete(_ checkIn: CheckInID) async throws(CheckInError) {
        do { try await api.delete(checkIn) } catch { throw CheckInError(error) }
    }

    public func pokes(in squad: SquadID) async throws(CheckInError) -> SquadPokes {
        do { return try await api.pokes(in: squad) } catch { throw CheckInError(error) }
    }

    public func pat(_ member: MemberID, in squad: SquadID) async throws(CheckInError) {
        do { try await api.pat(member, in: squad) } catch { throw CheckInError(error) }
    }

    public func coach(in squad: SquadID) async throws(CheckInError) -> SidelineCoach? {
        do {
            guard let hire = try await api.coach(of: squad).hire else { return nil }
            let activity = try await api.coachActivity(of: squad)
            return SidelineCoach(
                coach: CoachSpeaker(id: hire.coach.id, name: hire.coach.name), note: activity.note,
                letter: activity.letter)
        } catch { throw CheckInError(error) }
    }

    public func hasUnseenCoachCards(in squad: SquadID) async throws(CheckInError) -> Bool {
        do { return !(try await api.coachCards(in: squad).stack.isEmpty) } catch { throw CheckInError(error) }
    }

    public func todayChallenge(in squad: SquadID) async throws(CheckInError) -> DayChallenge? {
        do { return try await api.todayChallenge(in: squad) } catch { throw CheckInError(error) }
    }

    public func completeChallenge(_ note: String, in squad: SquadID) async throws(CheckInError)
        -> CoachChallengeCompleter
    {
        guard let id = Int(note) else { throw .refused }
        do { return try await api.completeChallenge(of: id, in: squad) } catch { throw CheckInError(error) }
    }

    public func writeLetter(in squad: SquadID) async throws(CheckInError) -> CoachLetter? {
        do { return try await api.writeLetter(in: squad) } catch { throw CheckInError(error) }
    }

    public func openedLetter() async -> Int? {
        guard let data = try? Data(contentsOf: openedLetterFile),
            let kept = try? DeviceJSON.decoder.decode(OpenedCoachLetter.self, from: data), kept.version == 1
        else { return nil }
        return kept.letter
    }

    public func opened(_ letter: CoachLetter) async {
        guard let data = try? DeviceJSON.encoder.encode(OpenedCoachLetter(version: 1, letter: letter.id)) else {
            return
        }
        try? DeviceJSON.write(data, to: openedLetterFile)
    }
}

/// The newest coach's letter opened on this phone, by its id. Stored JSON, so it carries a `version`.
struct OpenedCoachLetter: Codable {
    let version: Int
    let letter: Int
}

/// The home as the API sent it. Stored JSON, so it carries a `version`.
struct SavedHome: Codable {
    let version: Int
    let member: Components.Schemas.Me
    let squad: Components.Schemas.Squad
    let today: Components.Schemas.SquadToday
    let plan: Components.Schemas.WeeklyPlan
    /// The squad's, from two days before the member's day to two days after.
    let checkIns: Components.Schemas.SquadPostList
    /// The member's own, since Monday or the first day a 补打卡 can count for, whichever is earlier.
    let week: Components.Schemas.CheckInList

    func home(api: WildcardAPI) throws(APIError) -> Home {
        guard version == 1, let id = UUID(uuidString: member.userId) else { throw .unreadableResponse }
        let zone = member.profile.flatMap { TimeZone(identifier: $0.timeZone) } ?? .current
        return try api.read { () throws(ContractsError) in
            Home(
                member: MemberID(id), timeZone: zone, squad: try Squad(squad),
                today: try SquadToday(today),
                plan: try WeeklyPlan(plan), checkIns: try Self.merged(checkIns, week))
        }
    }

    /// Both lists as one, each check-in once, oldest first.
    private static func merged(_ squad: Components.Schemas.SquadPostList, _ mine: Components.Schemas.CheckInList)
        throws(ContractsError) -> [CheckIn]
    {
        var byID: [CheckInID: CheckIn] = [:]
        for wire in squad.posts.map(\.checkIn) + mine.checkIns {
            let checkIn = try CheckIn(wire)
            byID[checkIn.id] = checkIn
        }
        return byID.values.sorted { ($0.createdAt, $0.id.description) < ($1.createdAt, $1.id.description) }
    }
}

/// JSON kept on the device: dates as the API writes them, milliseconds included.
enum DeviceJSON {
    static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(try Configuration.api.dateTranscoder.encode(date))
        }
        return encoder
    }

    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            try Configuration.api.dateTranscoder.decode(try decoder.singleValueContainer().decode(String.self))
        }
        return decoder
    }

    /// Writes a file whole, readable only while the phone is unlocked.
    static func write(_ data: Data, to file: URL) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        #if os(iOS)
        try data.write(to: file, options: [.atomic, .completeFileProtection])
        #else
        try data.write(to: file, options: .atomic)
        #endif
    }
}

extension CheckInError {
    /// What a failed API call means for a check-in.
    init(_ error: APIError) {
        self =
            switch error {
            case .unavailable: .notSent
            case .account(.signedOut), .account(.credentialRejected), .account(.canceled): .signedOut
            case .account: .notSent
            case .refused(.squadNotJoined): .notInSquad
            case .refused(.checkInOutOfTime): .outOfTime
            case .refused(.photoRejected): .photoRejected
            case .refused, .unreadableResponse: .refused
            }
    }
}
