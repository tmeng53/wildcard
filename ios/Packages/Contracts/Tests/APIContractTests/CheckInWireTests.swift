import APIContract
import Contracts
import Foundation
import OpenAPIRuntime
import Testing

private let checkInID = CheckInID(UUID(uuidString: "11111111-1111-1111-1111-111111111111")!)
private let memberID = MemberID(UUID(uuidString: "22222222-2222-2222-2222-222222222222")!)
private let squadA = SquadID(UUID(uuidString: "33333333-3333-3333-3333-333333333333")!)
private let squadB = SquadID(UUID(uuidString: "44444444-4444-4444-4444-444444444444")!)
private let createdAt = Timestamp(millisecondsSince1970: 1_760_745_600_123)  // 2025-10-18T00:00:00.123Z
private let photoA = "22222222-2222-2222-2222-222222222222/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
private let photoB = "22222222-2222-2222-2222-222222222222/bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"

/// JSON as a client configured with `Configuration.api` sends and reads it.
private func encode(_ draft: Components.Schemas.CheckInDraft) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    encoder.dateEncodingStrategy = .custom { date, encoder in
        var container = encoder.singleValueContainer()
        try container.encode(try Configuration.api.dateTranscoder.encode(date))
    }
    return String(decoding: try encoder.encode(draft), as: UTF8.self)
}

private func decode(_ json: String) throws -> CheckIn {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .custom { decoder in
        try Configuration.api.dateTranscoder.decode(try decoder.singleValueContainer().decode(String.self))
    }
    return try CheckIn(try decoder.decode(Components.Schemas.CheckIn.self, from: Data(json.utf8)))
}

private func checkIn(_ entry: CheckIn.Entry, audience: [SquadID] = [squadA]) throws -> CheckIn {
    CheckIn(
        id: checkInID, member: memberID, day: try LocalDay("2025-10-17"), createdAt: createdAt,
        audience: try Audience(audience), entry: entry)
}

/// A saved check-in as `GET /me/check-ins` lists it, with `kind` and its fields spliced in.
private func saved(_ kindAndFields: String) -> String {
    #"{"version":1,"id":"11111111-1111-1111-1111-111111111111","member":"22222222-2222-2222-2222-222222222222","day":"2025-10-17","createdAt":"2025-10-18T00:00:00.123Z","audience":["33333333-3333-3333-3333-333333333333"],"#
        + kindAndFields + "}"
}

@Test func trainedDraftIsTheBodyTheAPITakes() throws {
    let training = Training(
        activity: .sport("run"), photos: try Photos([try PhotoRef(path: photoB), try PhotoRef(path: photoA)]),
        caption: try Caption("  雨中五公里 "))
    #expect(
        try encode(try checkIn(.trained(training), audience: [squadA, squadB]).draft)
            == #"{"audience":["33333333-3333-3333-3333-333333333333","44444444-4444-4444-4444-444444444444"],"createdAt":"2025-10-18T00:00:00.123Z","day":"2025-10-17","kind":"trained","training":{"caption":"雨中五公里","photos":[{"path":"22222222-2222-2222-2222-222222222222/bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"},{"path":"22222222-2222-2222-2222-222222222222/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"}],"sport":"run"},"version":1}"#
    )
}

@Test func eachKindsDraftCarriesOnlyItsOwnFields() throws {
    #expect(
        try encode(try checkIn(.trained(Training(activity: .custom(try CustomSport("飞盘高尔夫"))))).draft)
            .hasSuffix(#""kind":"trained","training":{"customSport":"飞盘高尔夫","sport":"custom"},"version":1}"#))
    #expect(
        try encode(try checkIn(.healthyMeal(Meal(caption: try Caption("沙拉碗")))).draft)
            .hasSuffix(#""kind":"healthyMeal","meal":{"caption":"沙拉碗"},"version":1}"#))
    #expect(
        try encode(try checkIn(.cheatMeal(Meal())).draft).hasSuffix(#""kind":"cheatMeal","meal":{},"version":1}"#))
    #expect(
        try encode(try checkIn(.disclaimer(try Disclaimer("下雨了，跑道在哭"))).draft)
            .hasSuffix(#""disclaimer":{"text":"下雨了，跑道在哭"},"kind":"disclaimer","version":1}"#))
}

@Test func aSportListedAfterThisBuildReads() throws {
    // The list is data the server keeps, so a check-in may name a sport this build never saw.
    let read = try decode(saved(#""kind":"trained","training":{"sport":"padel"}"#))
    #expect(read.entry == .trained(Training(activity: .sport("padel"))))
}

@Test func minutesGoWithTheSportBothWays() throws {
    let training = Training(activity: .sport("run"), minutes: try WorkoutMinutes(45))
    #expect(
        try encode(try checkIn(.trained(training)).draft)
            .hasSuffix(#""kind":"trained","training":{"minutes":45,"sport":"run"},"version":1}"#))
    #expect(
        try decode(saved(#""kind":"trained","training":{"sport":"run","minutes":45}"#)) == checkIn(.trained(training)))
    #expect(throws: ContractsError.workoutMinutes(0)) {
        try decode(saved(#""kind":"trained","training":{"sport":"run","minutes":0}"#))
    }
}

@Test func savedTrainingReadsWithItsPhotoURLs() throws {
    let json = saved(
        #""kind":"trained","training":{"sport":"swim","caption":"一千米","photos":[{"path":"\#(photoA)","url":"https://storage.example.com/a?token=1"}]}"#
    )
    let photo = try PhotoRef(path: photoA, viewURL: URL(string: "https://storage.example.com/a?token=1"))
    #expect(
        try decode(json)
            == checkIn(
                .trained(Training(activity: .sport("swim"), photos: try Photos([photo]), caption: try Caption("一千米")))))
}

@Test func savedMealsAndDisclaimersRead() throws {
    #expect(
        try decode(saved(#""kind":"cheatMeal","meal":{"caption":"火锅，不后悔"}"#))
            == checkIn(.cheatMeal(Meal(caption: try Caption("火锅，不后悔")))))
    #expect(try decode(saved(#""kind":"healthyMeal","meal":{}"#)) == checkIn(.healthyMeal(Meal())))
    #expect(
        try decode(saved(#""kind":"disclaimer","disclaimer":{"text":"腿还在酸"}"#))
            == checkIn(.disclaimer(try Disclaimer("腿还在酸"))))
}

@Test func aDisclaimerCarriesPhotosBothWays() throws {
    let photos = try Photos([try PhotoRef(path: photoA)])
    #expect(
        try encode(try checkIn(.disclaimer(try Disclaimer("躺平也是训练", photos: photos))).draft)
            .hasSuffix(
                #""disclaimer":{"photos":[{"path":"\#(photoA)"}],"text":"躺平也是训练"},"kind":"disclaimer","version":1}"#
            ))
    let json = saved(
        #""kind":"disclaimer","disclaimer":{"text":"躺平也是训练","photos":[{"path":"\#(photoA)","url":"https://storage.example.com/a"}]}"#
    )
    let viewed = try Photos([try PhotoRef(path: photoA, viewURL: URL(string: "https://storage.example.com/a"))])
    #expect(try decode(json) == checkIn(.disclaimer(try Disclaimer("躺平也是训练", photos: viewed))))
}

@Test func aPhotosSizeGoesBothWays() throws {
    let portrait = try PhotoSize(width: 1080, height: 1350)
    let photos = try Photos([try PhotoRef(path: photoA, size: portrait), try PhotoRef(path: photoB)])
    #expect(
        try encode(try checkIn(.healthyMeal(Meal(photos: photos))).draft)
            .contains(
                #""photos":[{"path":"\#(photoA)","size":{"height":1350,"width":1080}},{"path":"\#(photoB)"}]"#))
    let json = saved(
        #""kind":"healthyMeal","meal":{"photos":[{"path":"\#(photoA)","url":"https://s.example.com/a","size":{"width":1080,"height":1350}},{"path":"\#(photoB)","url":"https://s.example.com/b"}]}"#
    )
    guard case .healthyMeal(let meal) = try decode(json).entry else {
        Issue.record("not a meal")
        return
    }
    #expect(meal.photos?.all.map(\.size) == [portrait, nil])
}

@Test func aPhotoSizeOutsideTheRangeIsRefused() throws {
    #expect(throws: ContractsError.photoSize(width: 0, height: 1350)) { try PhotoSize(width: 0, height: 1350) }
    #expect(throws: ContractsError.photoSize(width: 1080, height: 10_001)) {
        try PhotoSize(width: 1080, height: 10_001)
    }
    #expect(try PhotoSize(width: 1080, height: 1350).aspectRatio == 0.8)
}

@Test func aSixtyCharacterCaptionFromTheAPIReads() throws {
    let caption = String(repeating: "爽", count: 60)
    let read = try decode(saved(#""kind":"healthyMeal","meal":{"caption":"\#(caption)"}"#))
    #expect(read.entry == .healthyMeal(Meal(caption: try Caption(caption))))
}

@Test func whatTheAppWouldNeverHoldIsRejected() {
    #expect(throws: ContractsError.strayCustomSport) {
        try decode(saved(#""kind":"trained","training":{"sport":"run","customSport":"飞盘"}"#))
    }
    #expect(throws: ContractsError.strayCustomSport) {
        try decode(saved(#""kind":"trained","training":{"sport":"custom"}"#))
    }
    #expect(throws: ContractsError.photoCount(0)) {
        try decode(saved(#""kind":"trained","training":{"sport":"run","photos":[]}"#))
    }
    #expect(throws: ContractsError.invalidID("squad")) {
        try decode(
            #"{"version":1,"id":"11111111-1111-1111-1111-111111111111","member":"22222222-2222-2222-2222-222222222222","day":"2025-10-17","createdAt":"2025-10-18T00:00:00.123Z","audience":["squad"],"kind":"healthyMeal","meal":{}}"#
        )
    }
    #expect(throws: ContractsError.invalidDay("2025-02-30")) {
        try decode(saved(#""kind":"healthyMeal","meal":{}"#).replacingOccurrences(of: "2025-10-17", with: "2025-02-30"))
    }
}

@Test func whatTheContractDoesNotAllowFailsToDecode() {
    // A version this build doesn't know, a sport id of the wrong shape.
    #expect(throws: DecodingError.self) {
        try decode(
            saved(#""kind":"healthyMeal","meal":{}"#).replacingOccurrences(of: #""version":1"#, with: #""version":2"#))
    }
    #expect(throws: ContractsError.unknownSport("Padel Tennis")) {
        try decode(saved(#""kind":"trained","training":{"sport":"Padel Tennis"}"#))
    }
}

@Test func aFieldThisBuildDoesNotKnowIsSkipped() throws {
    // The API adds fields without a new version; a build already on phones must keep reading.
    let checkIn = try decode(saved(#""kind":"trained","training":{"sport":"run","addedLater":300}"#))
    #expect(checkIn.entry == .trained(Training(activity: .sport("run"))))
}

@Test(arguments: [0, 1, 7, 123, 499, 500, 501, 998, 999])
func datesKeepEveryMillisecond(millis: Int64) throws {
    let moment = Timestamp(millisecondsSince1970: 1_760_745_600_000 + millis)
    let draft = try checkIn(.healthyMeal(Meal())).draft
    guard case .healthyMeal(var body) = draft else { throw ContractsError.invalidTimestamp("not a meal") }
    body.createdAt = moment.date
    let json = try encode(.healthyMeal(body))
    #expect(json.contains(#""createdAt":"\#(moment.description)""#))
    let read = try decode(
        saved(#""kind":"healthyMeal","meal":{}"#).replacingOccurrences(
            of: createdAt.description, with: moment.description))
    #expect(read.createdAt == moment)
}
