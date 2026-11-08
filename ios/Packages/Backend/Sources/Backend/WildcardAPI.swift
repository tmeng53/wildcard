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
    /// `AccountSession.accessToken(for:rejected:)` is the app's (`WildcardAPI+Account.swift`).
    public typealias AccessToken = @Sendable (_ rejected: String?) async throws(AccountError) -> String

    let client: Client
    /// The same API on `URLSession.live`, for the stream of live events, which stays quiet
    /// longer than a call may; always that session, whatever `http` is, since it outwaits the
    /// heartbeat.
    let live: Client
    private let http: URLSession
    /// Where photos seen once are kept, so they aren't downloaded again; none keeps nothing.
    private let photos: PhotoCache?

    /// - Parameters:
    ///   - url: where the API is served, such as `https://api.example.com`.
    ///   - refused: called with a freshly renewed token the API refuses too: its session is over.
    ///   - language: the tag (`zh-Hans`, `en`) of the language the 战报's words come in.
    ///   - photos: where check-in photos are kept once downloaded.
    public init(
        url: URL, accessToken: @escaping AccessToken,
        refused: @escaping @Sendable (_ token: String) async -> Void = { _ in },
        language: LanguageTag? = nil, http: URLSession = .wildcard, photos: PhotoCache? = nil
    ) {
        // The first wraps the rest: `Problems` reads the answer after any retry.
        let middlewares: [any ClientMiddleware] =
            [Problems(), BearerToken(accessToken: accessToken, refused: refused)]
            + (language.map { [AcceptLanguage(language: $0)] } ?? [])
            // Last, next to the network, so a read sent again goes out as it did the first time.
            + [ResendDroppedRead()]
        client = Client(
            serverURL: url, configuration: .api, transport: URLSessionTransport(configuration: .init(session: http)),
            middlewares: middlewares)
        live = Client(
            serverURL: url, configuration: .api,
            transport: URLSessionTransport(configuration: .init(session: .live)), middlewares: middlewares)
        self.http = http
        self.photos = photos
    }

    // MARK: - The member

    /// The signed-in member, with their profile once it is saved.
    public func me() async throws(APIError) -> Member {
        let answer = try await meWire()
        guard let id = UUID(uuidString: answer.userId) else { throw .unreadableResponse }
        return Member(
            id: MemberID(id), profile: try answer.profile.map(Profile.init),
            joinedAt: answer.profile.map { Timestamp($0.joinedAt) }, isAdmin: answer.isAdmin)
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

    /// The member's squad, or nil in none: a member is in one squad at most.
    public func mySquad() async throws(APIError) -> Squad? {
        guard let wire = try await mySquadWire() else { return nil }
        return try read { () throws(ContractsError) in try Squad(wire) }
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

    /// The API lists a member's squads, which is one at most.
    func mySquadWire() async throws(APIError) -> Components.Schemas.Squad? {
        try await call { try await client.listMySquads().ok.body.json }.squads.first
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
            // This build reads posts shared to no squad, so it asks for them.
            try await client.listMyCheckIns(
                query: .init(from: from.description, to: last.description, unshared: .include)
            ).ok.body.json
        }
    }

    func myPostsWire(kind: Operations.ListMyPosts.Input.Query.KindPayload?, after: String?) async throws(APIError)
        -> Components.Schemas.MyPostPage
    {
        try await call { try await client.listMyPosts(query: .init(kind: kind, after: after)).ok.body.json }
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

    /// A check-in's photo: the copy kept on the phone, else from the URL the API signed for it,
    /// then kept. Nil when it can't be had now (offline, or the URL ran out: listing again signs
    /// fresh ones).
    public func photo(_ ref: PhotoRef) async -> Data? {
        if let kept = await photos?.photo(at: ref.path) { return kept }
        let generation = await photos?.generation
        guard let url = ref.viewURL, let (data, response) = try? await http.data(from: url),
            (response as? HTTPURLResponse)?.statusCode == 200
        else { return nil }
        await photos?.keep(data, at: ref.path, postedAt: ref.postedAt?.date ?? Date(), startedIn: generation)
        return data
    }

    /// Deletes the photos kept on the phone, when the member signs out or deletes their account.
    public func forgetPhotos() async {
        await photos?.forgetAll()
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
