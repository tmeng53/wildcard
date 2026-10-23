import APIContract
import CheckInDomain
import Contracts
import Foundation
import OpenAPIRuntime

/// The home and 打卡 over our API, with a copy of the last home kept on the device, as the API
/// sent it, so the home opens offline. The copy is the member's: `forget()` it on sign-out.
public struct APICheckInBackend: CheckInBackend {
    private let api: WildcardAPI
    private let saved: URL
    private let shared: SharedSquad?
    private let now: @Sendable () -> Date

    /// - Parameters:
    ///   - directory: where the copy is kept, such as Application Support.
    ///   - shared: where the squad's looks are kept for the 6pm push view.
    public init(
        api: WildcardAPI, directory: URL, shared: SharedSquad? = nil, now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.api = api
        saved = directory.appending(path: "home.json")
        self.shared = shared
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
            if signedIn.profile == nil {
                // Saved right after the first sign-in; a member without one gets the phone's zone.
                _ = try await api.save(Profile(timeZone: .current))
                signedIn = try await api.meWire()
            }
            guard let squad = try await api.mySquadsWire().squads.first else {
                forget()
                return nil
            }
            let zone = signedIn.profile.flatMap { TimeZone(identifier: $0.timeZone) } ?? .current
            let day = LocalDay(at: now(), in: zone)
            let squadID = try api.read { () throws(ContractsError) in try Squad(squad).id }
            async let today = api.todayWire(of: squadID)
            async let plan = api.weeklyPlanWire(weekStart: day.weekStart)
            async let checkIns = api.checkInsWire(of: squadID, from: day.adding(days: -2), through: day.adding(days: 2))
            async let week = api.myCheckInsWire(from: day.weekStart, through: day)
            let copy = SavedHome(
                version: 1, member: signedIn, squad: squad, today: try await today, plan: try await plan,
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

    public func upload(_ photo: PreparedPhoto) async throws(CheckInError) -> PhotoRef {
        do { return try await api.upload(photo.jpeg, as: .jpeg) } catch { throw CheckInError(error) }
    }

    public func save(_ checkIn: CheckIn) async throws(CheckInError) -> CheckIn {
        do { return try await api.save(checkIn) } catch { throw CheckInError(error) }
    }

    public func reactions(to checkIn: CheckInID) async throws(CheckInError) -> [Reaction] {
        do { return try await api.reactions(to: checkIn) } catch { throw CheckInError(error) }
    }

    public func react(_ emoji: Emoji, to checkIn: CheckInID) async throws(CheckInError) {
        do { try await api.react(emoji, to: checkIn) } catch { throw CheckInError(error) }
    }

    public func removeReaction(from checkIn: CheckInID) async throws(CheckInError) {
        do { try await api.removeReaction(from: checkIn) } catch { throw CheckInError(error) }
    }

    public func pokes(in squad: SquadID) async throws(CheckInError) -> SquadPokes {
        do { return try await api.pokes(in: squad) } catch { throw CheckInError(error) }
    }

    public func pat(_ member: MemberID, in squad: SquadID) async throws(CheckInError) {
        do { try await api.pat(member, in: squad) } catch { throw CheckInError(error) }
    }

    /// Deletes the copy and the squad's looks, when the member signs out or deletes their account.
    public func forget() {
        try? FileManager.default.removeItem(at: saved)
        shared?.forget()
    }
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
    /// The member's own, since Monday.
    let week: Components.Schemas.CheckInList

    func home(api: WildcardAPI) throws(APIError) -> Home {
        guard version == 1, let id = UUID(uuidString: member.userId) else { throw .unreadableResponse }
        let zone = member.profile.flatMap { TimeZone(identifier: $0.timeZone) } ?? .current
        return try api.read { () throws(ContractsError) in
            Home(
                member: MemberID(id), timeZone: zone, squad: try Squad(squad), today: try SquadToday(today),
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
            case .refused(.disclaimerAlreadyPosted): .disclaimerAlreadyPosted
            case .refused(.squadNotJoined): .notInSquad
            case .refused(.checkInOutOfTime): .outOfTime
            case .refused(.photoRejected): .photoRejected
            case .refused, .unreadableResponse: .refused
            }
    }
}
