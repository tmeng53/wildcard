import APIContract
import AccountDomain
import Contracts
import Foundation
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

    private let client: Client
    private let http: URLSession

    /// - Parameters:
    ///   - url: where the API is served, such as `https://api.example.com`.
    public init(url: URL, accessToken: @escaping AccessToken, http: URLSession = .shared) {
        client = Client(
            serverURL: url, configuration: .api, transport: URLSessionTransport(configuration: .init(session: http)),
            // The first wraps the rest: `Problems` reads the answer after any retry.
            middlewares: [Problems(), BearerToken(accessToken: accessToken)])
        self.http = http
    }

    public init(url: URL, account: AccountSession, http: URLSession = .shared) {
        self.init(
            url: url,
            accessToken: { rejected async throws(AccountError) in try await account.accessToken(rejected: rejected) },
            http: http)
    }

    // MARK: - The member

    /// The signed-in member, with their profile once it is saved.
    public func me() async throws(APIError) -> Member {
        let answer = try await call { try await client.getMe().ok.body.json }
        guard let id = UUID(uuidString: answer.userId) else { throw .unreadableResponse }
        return Member(id: MemberID(id), profile: try answer.profile.map(Profile.init))
    }

    /// Creates the profile, right after the first sign-in, or replaces it.
    public func save(_ profile: Profile) async throws(APIError) -> Profile {
        let saved = try await call {
            try await client.putMyProfile(
                body: .json(
                    .init(version: ._1, timeZone: profile.timeZone.identifier, catchphrase: profile.catchphrase?.text))
            ).ok.body.json
        }
        return try Profile(timeZone: saved.timeZone, catchphrase: saved.catchphrase)
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
        let list = try await call {
            try await client.listSquadCheckIns(
                path: .init(squadId: squad.description), query: .init(from: from.description, to: last.description)
            ).ok.body.json
        }
        return try read(list)
    }

    /// The member's own check-ins counted for these days (at most 31).
    public func myCheckIns(from: LocalDay, through last: LocalDay) async throws(APIError) -> [CheckIn] {
        let list = try await call {
            try await client.listMyCheckIns(query: .init(from: from.description, to: last.description)).ok.body.json
        }
        return try read(list)
    }

    // MARK: - Photos

    /// Uploads a photo straight to storage, never through the API, and returns it for a
    /// check-in to list. Each upload is used by one check-in only.
    public func upload(_ photo: Data, as type: PhotoType) async throws(APIError) -> PhotoRef {
        let upload = try await call { try await client.createPhotoUpload().created.body.json }
        guard let target = URL(string: upload.uploadUrl) else { throw .unreadableResponse }
        var request = URLRequest(url: target)
        request.httpMethod = "PUT"
        request.setValue(type.rawValue, forHTTPHeaderField: "Content-Type")
        let status: Int
        do {
            let (_, response) = try await http.upload(for: request, from: photo)
            status = (response as? HTTPURLResponse)?.statusCode ?? 0
        } catch {
            throw .unavailable
        }
        switch status {
        case 200..<300: return try read { () throws(ContractsError) in try PhotoRef(path: upload.path) }
        case 400..<500: throw .refused(.photoRejected)
        default: throw .unavailable
        }
    }

    // MARK: - Private

    /// Runs a generated call, turning whatever it throws into an `APIError`.
    private func call<T>(_ body: () async throws -> T) async throws(APIError) -> T {
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
    private func read<T>(_ body: () throws(ContractsError) -> T) throws(APIError) -> T {
        do {
            return try body()
        } catch {
            throw .unreadableResponse
        }
    }

    private func read(_ list: Components.Schemas.CheckInList) throws(APIError) -> [CheckIn] {
        try read { () throws(ContractsError) in try list.checkIns.map(CheckIn.init) }
    }
}

/// A member as the API knows them.
public struct Member: Hashable, Sendable {
    public let id: MemberID
    /// Nil until it is first saved, right after signing up.
    public let profile: Profile?
}

/// What the member tells the API about themselves.
public struct Profile: Hashable, Sendable {
    /// Where the member lives, for their weekly reset.
    public let timeZone: TimeZone
    /// What their character shouts when the squad cheers a teammate's 练了. Nil until they pick
    /// one, and the app uses their persona's own line.
    public let catchphrase: Catchphrase?

    public init(timeZone: TimeZone, catchphrase: Catchphrase? = nil) {
        self.timeZone = timeZone
        self.catchphrase = catchphrase
    }

    init(timeZone identifier: String, catchphrase: String?) throws(APIError) {
        guard let timeZone = TimeZone(identifier: identifier) else { throw .unreadableResponse }
        self.init(
            timeZone: timeZone,
            catchphrase: try catchphrase.map { text throws(APIError) in
                do { return try Catchphrase(text) } catch { throw .unreadableResponse }
            })
    }

    init(_ wire: Components.Schemas.Me.ProfilePayload) throws(APIError) {
        try self.init(timeZone: wire.timeZone, catchphrase: wire.catchphrase)
    }
}

/// The photo formats storage takes, as their media types.
public enum PhotoType: String, Sendable, CaseIterable {
    case jpeg = "image/jpeg"
    case heic = "image/heic"
    case png = "image/png"
    case webp = "image/webp"
}
