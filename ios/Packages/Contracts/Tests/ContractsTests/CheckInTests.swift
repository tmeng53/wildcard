import Foundation
import Testing
import Contracts

private let checkInID = CheckInID(UUID(uuidString: "11111111-1111-1111-1111-111111111111")!)
private let memberID = MemberID(UUID(uuidString: "22222222-2222-2222-2222-222222222222")!)
private let squadA = SquadID(UUID(uuidString: "33333333-3333-3333-3333-333333333333")!)
private let squadB = SquadID(UUID(uuidString: "44444444-4444-4444-4444-444444444444")!)
private let createdAt = Timestamp(millisecondsSince1970: 1_760_745_600_123) // 2025-10-18T00:00:00.123Z

private func encode(_ checkIn: CheckIn) throws -> String {
    String(decoding: try WireJSON.encoder().encode(checkIn), as: UTF8.self)
}

private func decode(_ json: String) throws -> CheckIn {
    try WireJSON.decoder().decode(CheckIn.self, from: Data(json.utf8))
}

@Test func trainedEncodesToTheWireShape() throws {
    let checkIn = CheckIn(
        id: checkInID, member: memberID, day: try LocalDay("2025-10-17"), createdAt: createdAt,
        audience: try Audience([squadA, squadB]),
        entry: .trained(
            try Training(
                activity: .sport(.run), minutes: 45,
                photos: try Photos([try PhotoRef(path: "m/b.jpg"), try PhotoRef(path: "m/a.jpg")]),
                caption: try Caption("  雨中五公里 ")))
    )
    #expect(try encode(checkIn) == #"{"audience":["33333333-3333-3333-3333-333333333333","44444444-4444-4444-4444-444444444444"],"createdAt":"2025-10-18T00:00:00.123Z","day":"2025-10-17","id":"11111111-1111-1111-1111-111111111111","kind":"trained","member":"22222222-2222-2222-2222-222222222222","training":{"caption":"雨中五公里","minutes":45,"photos":[{"path":"m\/b.jpg"},{"path":"m\/a.jpg"}],"sport":"run"},"version":1}"#)
}

@Test func eachKindRoundTrips() throws {
    let entries: [CheckIn.Entry] = [
        .trained(try Training(activity: .sport(.yoga), minutes: 30)),
        .trained(try Training(activity: .custom(try CustomSport("飞盘高尔夫")), minutes: 50)),
        .healthyMeal(Meal(slot: .lunch, caption: try Caption("沙拉碗"))),
        .cheatMeal(Meal(slot: .snack, photos: try Photos([try PhotoRef(path: "m/boba.jpg")]))),
        .disclaimer(try Disclaimer("下雨了，跑道在哭")),
    ]
    for entry in entries {
        let checkIn = CheckIn(id: checkInID, member: memberID, day: try LocalDay("2025-10-17"),
                              createdAt: createdAt, audience: try Audience([squadA]), entry: entry)
        #expect(try decode(try encode(checkIn)) == checkIn)
    }
}

@Test func disclaimerDecodesFromWire() throws {
    let json = #"{"version":1,"id":"11111111-1111-1111-1111-111111111111","member":"22222222-2222-2222-2222-222222222222","day":"2025-10-17","createdAt":"2025-10-18T00:00:00Z","audience":["33333333-3333-3333-3333-333333333333"],"kind":"disclaimer","disclaimer":{"text":"  腿还在酸  "}}"#
    #expect(try decode(json).entry == .disclaimer(try Disclaimer("腿还在酸")))
}

@Test func unknownVersionIsRejected() {
    let json = #"{"version":2,"id":"11111111-1111-1111-1111-111111111111","member":"22222222-2222-2222-2222-222222222222","day":"2025-10-17","createdAt":"2025-10-18T00:00:00Z","audience":["33333333-3333-3333-3333-333333333333"],"kind":"healthyMeal","meal":{"slot":"dinner"}}"#
    #expect(throws: ContractsError.unsupportedVersion(2)) { try decode(json) }
}

@Test func outOfRangeMinutesAreRejectedOnDecode() {
    let json = #"{"version":1,"id":"11111111-1111-1111-1111-111111111111","member":"22222222-2222-2222-2222-222222222222","day":"2025-10-17","createdAt":"2025-10-18T00:00:00Z","audience":["33333333-3333-3333-3333-333333333333"],"kind":"trained","training":{"sport":"run","minutes":0}}"#
    #expect(throws: ContractsError.minutesOutOfRange(0)) { try decode(json) }
}

@Test func disclaimerLengthCountsCharactersPeopleSee() throws {
    #expect(try Disclaimer(String(repeating: "累", count: 40)).text.count == 40)
    #expect(throws: ContractsError.disclaimerLength(41)) { try Disclaimer(String(repeating: "累", count: 41)) }
    #expect(throws: ContractsError.disclaimerLength(0)) { try Disclaimer("   ") }
}

@Test func emptyPhotoPathIsRejected() {
    #expect(throws: ContractsError.emptyPhotoPath) { try PhotoRef(path: "") }
}

@Test func idsEncodeLowercase() throws {
    let upper = CheckInID(UUID(uuidString: "ABCDEF01-ABCD-ABCD-ABCD-ABCDEF012345")!)
    #expect(String(decoding: try WireJSON.encoder().encode([upper]), as: UTF8.self)
        == #"["abcdef01-abcd-abcd-abcd-abcdef012345"]"#)
}

@Test func payloadThatDoesNotMatchKindIsRejected() {
    let json = #"{"version":1,"id":"11111111-1111-1111-1111-111111111111","member":"22222222-2222-2222-2222-222222222222","day":"2025-10-17","createdAt":"2025-10-18T00:00:00Z","audience":["33333333-3333-3333-3333-333333333333"],"kind":"healthyMeal","meal":{"slot":"dinner"},"training":{"sport":"run","minutes":30}}"#
    #expect(throws: ContractsError.payloadMismatch("healthyMeal")) { try decode(json) }
}

@Test func cheatMealDecodesFromWire() throws {
    let json = #"{"version":1,"id":"11111111-1111-1111-1111-111111111111","member":"22222222-2222-2222-2222-222222222222","day":"2025-10-17","createdAt":"2025-10-18T00:00:00Z","audience":["33333333-3333-3333-3333-333333333333"],"kind":"cheatMeal","meal":{"slot":"dinner","caption":"火锅，不后悔"}}"#
    #expect(try decode(json).entry == .cheatMeal(Meal(slot: .dinner, caption: try Caption("火锅，不后悔"))))
}

@Test func audienceIsOneToThreeDistinctSquads() throws {
    let squadC = SquadID(UUID(uuidString: "55555555-5555-5555-5555-555555555555")!)
    let squadD = SquadID(UUID(uuidString: "66666666-6666-6666-6666-666666666666")!)
    #expect(try Audience([squadA, squadB, squadC]).squads == [squadA, squadB, squadC])
    #expect(throws: ContractsError.audienceSize(0)) { try Audience([]) }
    #expect(throws: ContractsError.audienceSize(4)) { try Audience([squadA, squadB, squadC, squadD]) }
    #expect(throws: ContractsError.repeatedSquad) { try Audience([squadA, squadA]) }
}

@Test func checkInWithNoAudienceIsRejectedOnDecode() {
    let json = #"{"version":1,"id":"11111111-1111-1111-1111-111111111111","member":"22222222-2222-2222-2222-222222222222","day":"2025-10-17","createdAt":"2025-10-18T00:00:00Z","audience":[],"kind":"healthyMeal","meal":{"slot":"lunch"}}"#
    #expect(throws: ContractsError.audienceSize(0)) { try decode(json) }
}

@Test func captionIsOneShortLine() throws {
    #expect(try Caption(String(repeating: "爽", count: 40)).text.count == 40)
    #expect(throws: ContractsError.captionLength(41)) { try Caption(String(repeating: "爽", count: 41)) }
    #expect(throws: ContractsError.captionLength(0)) { try Caption(" ") }
    #expect(throws: ContractsError.multilineCaption) { try Caption("第一行\n第二行") }
}

private func trainingJSON(_ training: String) -> String {
    #"{"version":1,"id":"11111111-1111-1111-1111-111111111111","member":"22222222-2222-2222-2222-222222222222","day":"2025-10-17","createdAt":"2025-10-18T00:00:00Z","audience":["33333333-3333-3333-3333-333333333333"],"kind":"trained","training":"#
        + training + "}"
}

@Test func customSportIsReadAndWrittenWithItsName() throws {
    let checkIn = try decode(trainingJSON(#"{"sport":"custom","customSport":" 飞盘高尔夫 ","minutes":40}"#))
    #expect(try checkIn.entry == .trained(Training(activity: .custom(try CustomSport("飞盘高尔夫")), minutes: 40)))
    #expect(try encode(checkIn).contains(#""training":{"customSport":"飞盘高尔夫","minutes":40,"sport":"custom"}"#))
}

@Test func customSportNameMustFitAndGoWithCustom() throws {
    #expect(throws: ContractsError.customSportLength(21)) { try CustomSport(String(repeating: "练", count: 21)) }
    #expect(throws: ContractsError.multilineCustomSport) { try CustomSport("飞盘\n高尔夫") }
    #expect(throws: ContractsError.multilineCustomSport) { try CustomSport("飞盘\t高尔夫") }
    #expect(throws: ContractsError.multilineCustomSport) { try CustomSport("飞盘\u{0}") }
    #expect(try CustomSport("飞盘 高尔夫 🏃‍♀️").name == "飞盘 高尔夫 🏃‍♀️")
    #expect(throws: ContractsError.strayCustomSport) {
        try decode(trainingJSON(#"{"sport":"run","customSport":"飞盘","minutes":40}"#))
    }
    #expect(throws: DecodingError.self) { try decode(trainingJSON(#"{"sport":"custom","minutes":40}"#)) }
}

@Test func unknownSportIsRejected() {
    #expect(throws: ContractsError.unknownSport("padel")) { try decode(trainingJSON(#"{"sport":"padel","minutes":60}"#)) }
    #expect(throws: ContractsError.unknownSport("")) { try decode(trainingJSON(#"{"sport":"","minutes":60}"#)) }
}

@Test func photosAreOneToThreeDistinctWithTheFirstAsCover() throws {
    let a = try PhotoRef(path: "m/a.jpg")
    let b = try PhotoRef(path: "m/b.jpg")
    let c = try PhotoRef(path: "m/c.jpg")
    let photos = try Photos([a, b, c])
    #expect(photos.cover == a)
    #expect(photos.withCover(c)?.all == [c, a, b])
    #expect(try photos.withCover(PhotoRef(path: "m/z.jpg")) == nil)
    #expect(throws: ContractsError.photoCount(0)) { try Photos([]) }
    #expect(throws: ContractsError.photoCount(4)) { try Photos([a, b, c, try PhotoRef(path: "m/d.jpg")]) }
    #expect(throws: ContractsError.repeatedPhoto) { try Photos([a, a]) }
    #expect(throws: ContractsError.photoCount(0)) { try decode(trainingJSON(#"{"sport":"run","minutes":30,"photos":[]}"#)) }
}

@Test func everySportHasOneCategoryAndEveryCategoryHasSports() {
    #expect(Sport.allCases.count == 52)
    #expect(SportCategory.allCases.allSatisfy { !$0.sports.isEmpty })
    #expect(SportCategory.everyday.sports == [.dogWalk, .walkCommute, .bikeCommute, .deepClean, .moving, .strollerWalk, .gardening])
}
