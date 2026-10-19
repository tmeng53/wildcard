import AccountDomain
import Backend
import Contracts
import Foundation
import Testing

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// The app's API client against the built API and local Supabase, never a stand-in: members sign
// up and in through Supabase Auth, check-ins land in Postgres, photos in Supabase Storage.

/// A minute ago, inside the API's 48-hour window, and its UTC day: what the app sends for a
/// member in UTC.
private func moment() throws -> (day: LocalDay, createdAt: Timestamp) {
    let createdAt = Timestamp(Date().addingTimeInterval(-60))
    var utc = Calendar(identifier: .gregorian)
    utc.timeZone = try #require(TimeZone(identifier: "UTC"))
    let parts = utc.dateComponents([.year, .month, .day], from: createdAt.date)
    let day = try LocalDay(
        year: try #require(parts.year), month: try #require(parts.month), day: try #require(parts.day))
    return (day, createdAt)
}

private func checkIn(by member: SignedInMember, to squad: SquadID, _ entry: CheckIn.Entry) throws -> CheckIn {
    let now = try moment()
    return CheckIn(
        id: CheckInID(UUID()), member: member.id, day: now.day, createdAt: now.createdAt,
        audience: try Audience([squad]), entry: entry)
}

/// 2 KiB of noise standing in for a photo: storage checks the declared type, not the bytes.
private func photoBytes() -> Data {
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

    // Saving again replaces it.
    let moved = Profile(timeZone: try #require(TimeZone(identifier: "America/Toronto")))
    #expect(try await member.api.save(moved) == moved)
    #expect(try await member.api.me().profile == moved)
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
    let trained = try checkIn(by: outsider, to: squad, .trained(Training(activity: .sport(.run))))

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
