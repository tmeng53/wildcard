import AccountDomain
import Contracts
import Foundation
import Testing

@testable import Backend

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// The app's API client against the built API and local Supabase, never a stand-in: members sign
// up and in through Supabase Auth, check-ins land in Postgres, photos in Supabase Storage.

/// A minute before `now`, inside the API's 48-hour window, and its day for a member in UTC: the
/// API's day starts at 3am, so before 3am UTC it is still the day before.
func moment(now: Date = Date()) throws -> (day: LocalDay, createdAt: Timestamp) {
    let createdAt = Timestamp(now.addingTimeInterval(-60))
    var utc = Calendar(identifier: .gregorian)
    utc.timeZone = try #require(TimeZone(identifier: "UTC"))
    let parts = utc.dateComponents([.year, .month, .day], from: createdAt.date.addingTimeInterval(-3 * 3600))
    let day = try LocalDay(
        year: try #require(parts.year), month: try #require(parts.month), day: try #require(parts.day))
    return (day, createdAt)
}

@Test func theDayStartsAtThreeInTheMorning() throws {
    // 00:30 UTC on the 24th is still the 23rd; 03:30 is the 24th.
    #expect(try moment(now: Date(timeIntervalSince1970: 1_792_801_800)).day == LocalDay(year: 2026, month: 10, day: 23))
    #expect(try moment(now: Date(timeIntervalSince1970: 1_792_812_600)).day == LocalDay(year: 2026, month: 10, day: 24))
}

func checkIn(by member: SignedInMember, to squad: SquadID, _ entry: CheckIn.Entry) throws -> CheckIn {
    let now = try moment()
    return CheckIn(
        id: CheckInID(UUID()), member: member.id, day: now.day, createdAt: now.createdAt,
        audience: try Audience([squad]), entry: entry)
}

/// 2 KiB of noise standing in for a photo: storage checks the declared type, not the bytes.
func photoBytes() -> Data {
    Data((0..<2048).map { _ in UInt8.random(in: 0...255) })
}

@Test func aNewMemberSavesTheirProfileAfterSigningIn() async throws {
    let stack = try LocalStack()
    let member = try await stack.signedInMember()

    let before = try await member.api.me()
    #expect(before.id == member.id)
    #expect(before.profile == nil)

    let profile = Profile(timeZone: try #require(TimeZone(identifier: "America/Los_Angeles")))
    #expect(try await member.api.save(profile) == profile)
    #expect(try await member.api.me().profile == profile)

    // Saving again replaces it, catchphrase and character included.
    let character = MemberCharacter(
        nickname: try Nickname(" 小周 "),
        look: CharacterLook(
            persona: "deadpan", variants: ["body": "tuxedo", "top": "hoodie"], colors: ["top": "#2D5BA0"]))
    let moved = Profile(
        timeZone: try #require(TimeZone(identifier: "America/Toronto")), catchphrase: try Catchphrase("冲就完了🔥"),
        character: character)
    #expect(try await member.api.save(moved) == moved)
    #expect(try await member.api.me().profile == moved)

    // The whole profile is replaced, so saving without one clears it.
    #expect(try await member.api.save(profile) == profile)
    #expect(try await member.api.me().profile == profile)
}

@Test func aTrainedCheckInIsSavedOnceAndTheSquadSeesIt() async throws {
    let stack = try LocalStack()
    let author = try await stack.signedInMember()
    let mate = try await stack.signedInMember()
    let squad = try await stack.squad(of: author, mate)
    let trained = try checkIn(
        by: author, to: squad,
        .trained(Training(activity: .custom(try CustomSport("飞盘")), caption: try Caption("累但爽"))))

    #expect(try await author.api.save(trained) == trained)
    // A retry, such as after a dropped connection, answers with the saved one.
    #expect(try await author.api.save(trained) == trained)

    #expect(try await mate.api.checkIns(of: squad, from: trained.day, through: trained.day) == [trained])
    #expect(try await author.api.myCheckIns(from: trained.day, through: trained.day) == [trained])
    #expect(try await mate.api.myCheckIns(from: trained.day, through: trained.day) == [])
}

@Test func differentContentsUnderTheSameIDAreRefused() async throws {
    let stack = try LocalStack()
    let author = try await stack.signedInMember()
    let squad = try await stack.squad(of: author)
    let first = try checkIn(by: author, to: squad, .healthyMeal(Meal(caption: try Caption("沙拉"))))
    _ = try await author.api.save(first)

    let changed = CheckIn(
        id: first.id, member: author.id, day: first.day, createdAt: first.createdAt, audience: first.audience,
        entry: .healthyMeal(Meal(caption: try Caption("改了"))))
    await #expect(throws: APIError.refused(.checkInIDConflict)) { try await author.api.save(changed) }
}

@Test func aPhotoIsUploadedToStorageAndTheSquadDownloadsTheSameBytes() async throws {
    let stack = try LocalStack()
    let author = try await stack.signedInMember()
    let mate = try await stack.signedInMember()
    let squad = try await stack.squad(of: author, mate)
    let bytes = photoBytes()

    let photo = try await author.api.upload(bytes, as: .jpeg)
    #expect(photo.path.hasPrefix("\(author.id)/"))
    let meal = try checkIn(by: author, to: squad, .cheatMeal(Meal(photos: try Photos([photo]))))
    #expect(try await author.api.save(meal) == meal)

    let seen = try await mate.api.checkIns(of: squad, from: meal.day, through: meal.day)
    #expect(seen == [meal])
    guard case .cheatMeal(let seenMeal) = try #require(seen.first).entry else {
        Issue.record("mate saw \(seen)")
        return
    }
    let viewURL = try #require(seenMeal.photos?.cover.viewURL)
    let (downloaded, response) = try await URLSession.shared.data(from: viewURL)
    #expect((response as? HTTPURLResponse)?.statusCode == 200)
    #expect(downloaded == bytes)

    // Each upload belongs to one check-in, and only its owner's.
    let again = try checkIn(by: author, to: squad, .healthyMeal(Meal(photos: try Photos([photo]))))
    await #expect(throws: APIError.refused(.photoInUse)) { try await author.api.save(again) }
    let borrowed = try checkIn(by: mate, to: squad, .healthyMeal(Meal(photos: try Photos([photo]))))
    await #expect(throws: APIError.refused(.photoNotYours)) { try await mate.api.save(borrowed) }
}

@Test func aPhotoThatWasNeverUploadedIsRefused() async throws {
    let stack = try LocalStack()
    let author = try await stack.signedInMember()
    let squad = try await stack.squad(of: author)
    let missing = try PhotoRef(path: "\(author.id)/\(UUID().uuidString.lowercased())")
    let meal = try checkIn(by: author, to: squad, .healthyMeal(Meal(photos: try Photos([missing]))))
    await #expect(throws: APIError.refused(.photoNotUploaded)) { try await author.api.save(meal) }
}

@Test func storageRefusesAPhotoOverTenMebibytes() async throws {
    let stack = try LocalStack()
    let author = try await stack.signedInMember()
    let tooBig = Data(count: 10 * 1024 * 1024 + 1)
    await #expect(throws: APIError.refused(.photoRejected)) { try await author.api.upload(tooBig, as: .jpeg) }
}

@Test func aDisclaimerWithAPhotoPostsOnceADay() async throws {
    let stack = try LocalStack()
    let author = try await stack.signedInMember()
    let mate = try await stack.signedInMember()
    let squad = try await stack.squad(of: author, mate)
    let photo = try await author.api.upload(photoBytes(), as: .heic)
    let disclaimer = try checkIn(
        by: author, to: squad, .disclaimer(try Disclaimer("腿还在酸，今天先躺平", photos: try Photos([photo]))))

    #expect(try await author.api.save(disclaimer) == disclaimer)
    #expect(try await mate.api.checkIns(of: squad, from: disclaimer.day, through: disclaimer.day) == [disclaimer])

    let second = try checkIn(by: author, to: squad, .disclaimer(try Disclaimer("再来一条")))
    await #expect(throws: APIError.refused(.disclaimerAlreadyPosted)) { try await author.api.save(second) }
}

@Test func someoneOutsideTheSquadCantPostToItOrReadIt() async throws {
    let stack = try LocalStack()
    let author = try await stack.signedInMember()
    let outsider = try await stack.signedInMember()
    let squad = try await stack.squad(of: author)
    let trained = try checkIn(by: outsider, to: squad, .trained(Training(activity: .sport("run"))))

    await #expect(throws: APIError.refused(.squadNotJoined)) { try await outsider.api.save(trained) }
    await #expect(throws: APIError.refused(.squadNotJoined)) {
        try await outsider.api.checkIns(of: squad, from: trained.day, through: trained.day)
    }
}

@Test func aRefusedTokenIsRenewedOnceAndTheCallGoesThrough() async throws {
    let stack = try LocalStack()
    let member = try await stack.signedInMember()
    let asked = Asked()
    // The first token is one the API refuses, as when the member signed out on another device;
    // the client asks again with it as `rejected` and gets the session's real one.
    let api = WildcardAPI(url: stack.apiURL) { rejected async throws(AccountError) in
        await asked.record(rejected)
        return rejected == nil ? "refused.token.here" : try await member.account.accessToken()
    }
    #expect(try await api.me().id == member.id)
    #expect(await asked.rejected == [nil, "refused.token.here"])
}

@Test func whenTheRenewedTokenIsRefusedTooTheMemberIsSignedOut() async throws {
    let stack = try LocalStack()
    let api = WildcardAPI(url: stack.apiURL) { _ async throws(AccountError) in "refused.token.here" }
    await #expect(throws: APIError.account(.signedOut)) { try await api.me() }
}

@Test func whenTheAPIRefusesTheAccountsRenewedTokenTheAccountIsSignedOut() async throws {
    let stack = try LocalStack()
    let member = try await stack.supabase.signUp()
    // A real sign-in whose tokens the API refuses, as after a signing-key mismatch.
    let account = AccountSession(
        provider: RefusedTokens(wrapping: stack.supabase.auth), store: MemorySessionStore(), now: { Date() })
    _ = try await account.restore()
    _ = try await account.signIn(with: .testMember(email: member.email, password: member.password))
    let api = WildcardAPI(url: stack.apiURL, account: account)
    await #expect(throws: APIError.account(.signedOut)) { try await api.me() }
    #expect(try await account.restore() == .signedOut)
}

@Test(arguments: [
    // What local Supabase Storage answers, each with HTTP 400.
    (#"{"statusCode":"413","error":"Payload too large","code":"EntityTooLarge"}"#, true),
    (#"{"statusCode":"415","error":"invalid_mime_type","code":"InvalidMimeType"}"#, true),
    (#"{"statusCode":"409","error":"Duplicate","code":"KeyAlreadyExists"}"#, false),
    (#"{"statusCode":"400","error":"InvalidJWT","code":"InvalidJWT"}"#, false),
    ("not json", false),
])
func onlyThePhotosOwnSizeOrTypeIsRefusedForGood(answer: String, aboutThePhoto: Bool) {
    #expect(StorageRefusal.isAboutThePhoto(Data(answer.utf8)) == aboutThePhoto)
}

@Test func afterSigningOutCallsNeedASignIn() async throws {
    let stack = try LocalStack()
    let member = try await stack.signedInMember()
    try await member.account.signOut()
    await #expect(throws: APIError.account(.signedOut)) { try await member.api.me() }
}

@Test func anUnreachableAPIIsUnavailable() async throws {
    // Nothing listens on port 9 (discard) on the test machine.
    let api = WildcardAPI(url: try #require(URL(string: "http://127.0.0.1:9"))) { _ async throws(AccountError) in
        "token"
    }
    await #expect(throws: APIError.unavailable) { try await api.me() }
}

private actor Asked {
    var rejected: [String?] = []
    func record(_ token: String?) { rejected.append(token) }
}

/// Supabase Auth with every session's access token swapped for one the API refuses.
private struct RefusedTokens: AuthProvider {
    let wrapping: SupabaseAuth

    func signIn(with credential: Credential) async throws(AccountError) -> Session {
        refused(try await wrapping.signIn(with: credential))
    }

    func refresh(_ refreshToken: String) async throws(AccountError) -> Session {
        refused(try await wrapping.refresh(refreshToken))
    }

    func signOut(_ session: Session) async throws(AccountError) { try await wrapping.signOut(session) }

    private func refused(_ session: Session) -> Session {
        Session(
            member: session.member, accessToken: "refused.token.here", refreshToken: session.refreshToken,
            expiresAt: session.expiresAt)
    }
}
