import APIContract
import AccountDomain
import CheckInDomain
import Contracts
import Foundation
import NotificationsDomain
import OpenAPIRuntime
import OpenAPIURLSession

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Our API, the only way into the data, in `Contracts` types. Every call sends the member's
/// access token and fails with an `APIError`.
public struct WildcardAPI: Sendable {
    /// A current access token; given the token the API just refused, a renewed one.
    /// `AccountSession.accessToken(rejected:)` is the app's.
    public typealias AccessToken = @Sendable (_ rejected: String?) async throws(AccountError) -> String

    let client: Client
    private let http: URLSession

    /// - Parameters:
    ///   - url: where the API is served, such as `https://api.example.com`.
    ///   - refused: called with a freshly renewed token the API refuses too: its session is over.
    ///   - language: the tag (`zh-Hans`, `en`) of the language the 战报's words come in.
    public init(
        url: URL, accessToken: @escaping AccessToken,
        refused: @escaping @Sendable (_ token: String) async -> Void = { _ in },
        language: LanguageTag? = nil, http: URLSession = .shared
    ) {
        client = Client(
            serverURL: url, configuration: .api, transport: URLSessionTransport(configuration: .init(session: http)),
            // The first wraps the rest: `Problems` reads the answer after any retry.
            middlewares: [Problems(), BearerToken(accessToken: accessToken, refused: refused)]
                + (language.map { [AcceptLanguage(language: $0)] } ?? []))
        self.http = http
    }

    /// Calls with the account's tokens, and signs the account out when the API refuses a renewed
    /// one, so screens following `AccountSession.states()` see the member signed out (a session
    /// signed in while that call was on its way stays).
    public init(url: URL, account: AccountSession, language: LanguageTag? = nil, http: URLSession = .shared) {
        self.init(
            url: url,
            accessToken: { rejected async throws(AccountError) in try await account.accessToken(rejected: rejected) },
            refused: { token in try? await account.signOut(ifCurrent: token) },
            language: language, http: http)
    }

    // MARK: - The member

    /// The signed-in member, with their profile once it is saved.
    public func me() async throws(APIError) -> Member {
        let answer = try await meWire()
        guard let id = UUID(uuidString: answer.userId) else { throw .unreadableResponse }
        return Member(
            id: MemberID(id), profile: try answer.profile.map(Profile.init),
            joinedAt: answer.profile.map { Timestamp($0.joinedAt) })
    }

    /// Creates the profile, right after the first sign-in, or replaces it.
    public func save(_ profile: Profile) async throws(APIError) -> Profile {
        let saved = try await call {
            try await client.putMyProfile(
                body: .json(
                    .init(
                        version: ._1, timeZone: profile.timeZone.identifier, catchphrase: profile.catchphrase?.text,
                        character: profile.character.map(Components.Schemas.Character.init),
                        jerseyNumber: profile.jerseyNumber?.value))
            ).ok.body.json
        }
        return try Profile(
            timeZone: saved.timeZone, catchphrase: saved.catchphrase, character: saved.character,
            jerseyNumber: saved.jerseyNumber)
    }

    // MARK: - Check-ins

    /// Saves a check-in under its own id. Safe to retry: the same check-in again answers with
    /// the saved one.
    public func save(_ checkIn: CheckIn) async throws(APIError) -> CheckIn {
        let saved = try await call {
            switch try await client.saveCheckIn(path: .init(id: checkIn.id.description), body: .json(checkIn.draft)) {
            case .created(let created): try created.body.json
            case .ok(let retried): try retried.body.json
            default: throw APIError.unreadableResponse
            }
        }
        return try read { () throws(ContractsError) in try CheckIn(saved) }
    }

    /// The squad's check-ins counted for these days (at most 31), as its members see them.
    public func checkIns(of squad: SquadID, from: LocalDay, through last: LocalDay) async throws(APIError) -> [CheckIn]
    {
        try read(try await checkInsWire(of: squad, from: from, through: last))
    }

    /// The member's own check-ins counted for these days (at most 31).
    public func myCheckIns(from: LocalDay, through last: LocalDay) async throws(APIError) -> [CheckIn] {
        try read(try await myCheckInsWire(from: from, through: last))
    }

    // MARK: - Squads and their today

    /// The member's squads, the earliest joined first.
    public func mySquads() async throws(APIError) -> [Squad] {
        let list = try await mySquadsWire()
        return try read { () throws(ContractsError) in try list.squads.map(Squad.init) }
    }

    /// The squad's today: every member's day, today's counts, the member's 本周 and the squad's.
    public func today(of squad: SquadID) async throws(APIError) -> SquadToday {
        let wire = try await todayWire(of: squad)
        return try read { () throws(ContractsError) in try SquadToday(wire) }
    }

    /// The member's plan for the week starting on `weekStart`, a Monday: the one saved for it,
    /// else their typical week, else the default.
    public func weeklyPlan(weekStart: LocalDay) async throws(APIError) -> WeeklyPlan {
        let wire = try await weeklyPlanWire(weekStart: weekStart)
        return try read { () throws(ContractsError) in try WeeklyPlan(wire) }
    }

    /// Saves the member's plan for the week starting on `weekStart`, a Monday: seven days, its
    /// first day first.
    public func save(_ days: [PlanDay], weekStart: LocalDay) async throws(APIError) -> WeeklyPlan {
        let wire = try await call {
            try await client.saveMyWeeklyPlan(
                path: .init(weekStart: weekStart.description), body: .json(.init(days))
            ).ok.body.json
        }
        return try read { () throws(ContractsError) in try WeeklyPlan(wire) }
    }

    // MARK: - Reactions

    /// Who reacted to a check-in, and with which emoji.
    public func reactions(to checkIn: CheckInID) async throws(APIError) -> [Reaction] {
        let list = try await call {
            try await client.listCheckInReactions(path: .init(checkInId: checkIn.description)).ok.body.json
        }
        return try read { () throws(ContractsError) in try list.reactions.map(Reaction.init) }
    }

    /// Sets the member's one reaction on a teammate's check-in, replacing any earlier one.
    public func react(_ emoji: Emoji, to checkIn: CheckInID) async throws(APIError) {
        try await call {
            switch try await client.reactToCheckIn(
                path: .init(checkInId: checkIn.description), body: .json(emoji.draft))
            {
            case .ok, .created: return
            default: throw APIError.unreadableResponse
            }
        }
    }

    /// Takes the member's reaction back; fine when there is none.
    public func removeReaction(from checkIn: CheckInID) async throws(APIError) {
        try await call {
            _ = try await client.removeMyReaction(path: .init(checkInId: checkIn.description)).noContent
        }
    }

    // MARK: - 请假条 drafts

    /// What the AI writer made of the member's reason, in a style; nil when it doesn't write
    /// about this reason, and the dice stand in.
    public func disclaimerDrafts(reason: String, style: DisclaimerStyle) async throws(APIError)
        -> DisclaimerSuggestions?
    {
        let wireStyle: Components.Schemas.DisclaimerDraftRequest.StylePayload =
            switch style {
            case .funny: .funny
            case .unhinged: .unhinged
            case .heroic: .heroic
            case .stubborn: .stubborn
            }
        let answer = try await call {
            try await client.writeDisclaimerDrafts(body: .json(.init(version: ._1, reason: reason, style: wireStyle)))
                .ok.body.json
        }
        return switch answer {
        case .case1(let drafts): .drafts(drafts.drafts)
        case .case2: .blocked
        case .case3: nil
        }
    }

    // MARK: - Wire answers, which the device copy keeps as the API sent them

    func meWire() async throws(APIError) -> Components.Schemas.Me {
        try await call { try await client.getMe().ok.body.json }
    }

    func mySquadsWire() async throws(APIError) -> Components.Schemas.SquadList {
        try await call { try await client.listMySquads().ok.body.json }
    }

    func todayWire(of squad: SquadID) async throws(APIError) -> Components.Schemas.SquadToday {
        try await call { try await client.getSquadToday(path: .init(squadId: squad.description)).ok.body.json }
    }

    func weeklyPlanWire(weekStart: LocalDay) async throws(APIError) -> Components.Schemas.WeeklyPlan {
        try await call {
            try await client.getMyWeeklyPlan(path: .init(weekStart: weekStart.description)).ok.body.json
        }
    }

    func myCheckInsWire(from: LocalDay, through last: LocalDay) async throws(APIError) -> Components.Schemas.CheckInList
    {
        try await call {
            try await client.listMyCheckIns(query: .init(from: from.description, to: last.description)).ok.body.json
        }
    }

    func checkInsWire(of squad: SquadID, from: LocalDay, through last: LocalDay) async throws(APIError)
        -> Components.Schemas.SquadPostList
    {
        try await call {
            try await client.listSquadCheckIns(
                path: .init(squadId: squad.description), query: .init(from: from.description, to: last.description)
            ).ok.body.json
        }
    }

    // MARK: - Photos

    /// A check-in's photo from the URL the API signed for it, or nil when it can't be had now
    /// (offline, or the URL ran out: listing again signs fresh ones).
    public func photo(at url: URL) async -> Data? {
        guard let (data, response) = try? await http.data(from: url),
            (response as? HTTPURLResponse)?.statusCode == 200
        else { return nil }
        return data
    }

    /// Uploads a photo straight to storage, never through the API, and returns it for a
    /// check-in to list. Each upload is used by one check-in only.
    public func upload(_ photo: Data, as type: PhotoType) async throws(APIError) -> PhotoRef {
        let upload = try await call { try await client.createPhotoUpload().created.body.json }
        guard let target = URL(string: upload.uploadUrl) else { throw .unreadableResponse }
        var request = URLRequest(url: target)
        request.httpMethod = "PUT"
        request.setValue(type.rawValue, forHTTPHeaderField: "Content-Type")
        let status: Int
        let answer: Data
        do {
            let (data, response) = try await http.upload(for: request, from: photo)
            status = (response as? HTTPURLResponse)?.statusCode ?? 0
            answer = data
        } catch {
            throw .unavailable
        }
        switch status {
        case 200..<300: return try read { () throws(ContractsError) in try PhotoRef(path: upload.path) }
        // Only the photo's own size or type is refused for good. Anything else (an expired
        // upload token, a path already taken) passes with a fresh upload URL, which a retry gets.
        case 400..<500 where StorageRefusal.isAboutThePhoto(answer): throw .refused(.photoRejected)
        default: throw .unavailable
        }
    }

    // MARK: - Push

    /// This phone gets the member's pushes from now on. Safe to repeat; a phone someone else
    /// signed in on before moves to this member.
    public func register(_ device: PushDevice) async throws(APIError) {
        let environment: Components.Schemas.Device.EnvironmentPayload =
            switch device.environment {
            case .sandbox: .sandbox
            case .production: .production
            }
        _ = try await call {
            try await client.registerMyDevice(
                body: .json(.init(version: ._1, token: device.token.description, environment: environment))
            ).ok
        }
    }

    /// This phone stops getting the member's pushes, for signing out. Safe to repeat.
    public func removeDevice(_ token: DeviceToken) async throws(APIError) {
        _ = try await call {
            try await client.removeMyDevice(body: .json(.init(version: ._1, token: token.description))).noContent
        }
    }

    // MARK: - Private

    /// Runs a generated call, turning whatever it throws into an `APIError`.
    func call<T>(_ body: () async throws -> T) async throws(APIError) -> T {
        do {
            return try await body()
        } catch let error as APIError {
            throw error
        } catch let error as ClientError {
            if let error = error.underlyingError as? APIError { throw error }
            if error.underlyingError is URLError || error.underlyingError is CancellationError { throw .unavailable }
            throw .unreadableResponse
        } catch {
            throw .unreadableResponse
        }
    }

    /// Reads what the API sent into `Contracts` types, which check every rule.
    func read<T>(_ body: () throws(ContractsError) -> T) throws(APIError) -> T {
        do {
            return try body()
        } catch {
            throw .unreadableResponse
        }
    }

    func read(_ list: Components.Schemas.CheckInList) throws(APIError) -> [CheckIn] {
        try read { () throws(ContractsError) in try list.checkIns.map(CheckIn.init) }
    }

    func read(_ list: Components.Schemas.SquadPostList) throws(APIError) -> [CheckIn] {
        try read { () throws(ContractsError) in
            try list.posts.map { post throws(ContractsError) in try CheckIn(post.checkIn) }
        }
    }
}

/// A member as the API knows them.
public struct Member: Hashable, Sendable {
    public let id: MemberID
    /// Nil until it is first saved, right after signing up.
    public let profile: Profile?
    /// When the profile was first saved, right after signing up. Nil until then.
    public let joinedAt: Timestamp?
}

/// What the member tells the API about themselves.
public struct Profile: Hashable, Sendable {
    /// Where the member lives, for their weekly reset.
    public let timeZone: TimeZone
    /// What their character shouts when the squad cheers a teammate's 练了. Nil until they pick
    /// one, and the app uses their persona's own line.
    public let catchphrase: Catchphrase?
    /// Their nickname and character's look. Nil until they make it, right after signing in.
    /// A save without it clears it, since the profile is saved whole.
    public let character: MemberCharacter?
    /// The number on their player card. Nil until they pick one, and the card shows their place
    /// in their squad.
    public let jerseyNumber: JerseyNumber?

    public init(
        timeZone: TimeZone, catchphrase: Catchphrase? = nil, character: MemberCharacter? = nil,
        jerseyNumber: JerseyNumber? = nil
    ) {
        self.timeZone = timeZone
        self.catchphrase = catchphrase
        self.character = character
        self.jerseyNumber = jerseyNumber
    }

    init(
        timeZone identifier: String, catchphrase: String?, character: Components.Schemas.Character?,
        jerseyNumber: Int?
    ) throws(APIError) {
        guard let timeZone = TimeZone(identifier: identifier) else { throw .unreadableResponse }
        do {
            self.init(
                timeZone: timeZone,
                catchphrase: try catchphrase.map { text throws(ContractsError) in try Catchphrase(text) },
                character: try character.map { wire throws(ContractsError) in try MemberCharacter(wire) },
                jerseyNumber: try jerseyNumber.map { number throws(ContractsError) in try JerseyNumber(number) })
        } catch {
            throw .unreadableResponse
        }
    }

    init(_ wire: Components.Schemas.Me.ProfilePayload) throws(APIError) {
        try self.init(
            timeZone: wire.timeZone, catchphrase: wire.catchphrase, character: wire.character,
            jerseyNumber: wire.jerseyNumber)
    }
}

/// What storage says when it refuses an upload. It answers 400 for every refusal and puts the
/// real one in `code`, as Supabase Storage does.
struct StorageRefusal: Decodable {
    let code: String

    static func isAboutThePhoto(_ answer: Data) -> Bool {
        guard let refusal = try? JSONDecoder().decode(Self.self, from: answer) else { return false }
        return ["EntityTooLarge", "InvalidMimeType"].contains(refusal.code)
    }
}

/// The photo formats storage takes, as their media types.
public enum PhotoType: String, Sendable, CaseIterable {
    case jpeg = "image/jpeg"
    case heic = "image/heic"
    case png = "image/png"
    case webp = "image/webp"
}
