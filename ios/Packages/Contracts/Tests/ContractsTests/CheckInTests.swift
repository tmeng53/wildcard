import Foundation
import Testing
import Contracts

private let checkInID = CheckInID(UUID(uuidString: "11111111-1111-1111-1111-111111111111")!)
private let memberID = MemberID(UUID(uuidString: "22222222-2222-2222-2222-222222222222")!)
private let createdAt = Date(timeIntervalSince1970: 1_760_745_600) // 2025-10-18T00:00:00Z

private func encode(_ checkIn: CheckIn) throws -> String {
    String(decoding: try WireJSON.encoder().encode(checkIn), as: UTF8.self)
}

private func decode(_ json: String) throws -> CheckIn {
    try WireJSON.decoder().decode(CheckIn.self, from: Data(json.utf8))
}

@Test func trainedEncodesToTheWireShape() throws {
    let checkIn = CheckIn(
        id: checkInID, member: memberID, day: try LocalDay("2025-10-17"), createdAt: createdAt,
        entry: .trained(try Training(sport: .run, minutes: 45, photo: try PhotoRef(path: "m/abc.jpg")))
    )
    #expect(try encode(checkIn) == #"{"createdAt":"2025-10-18T00:00:00Z","day":"2025-10-17","id":"11111111-1111-1111-1111-111111111111","kind":"trained","member":"22222222-2222-2222-2222-222222222222","training":{"minutes":45,"photo":{"path":"m\/abc.jpg"},"sport":"run"},"version":1}"#)
}

@Test func eachKindRoundTrips() throws {
    let entries: [CheckIn.Entry] = [
        .trained(try Training(sport: .yoga, minutes: 30)),
        .ateClean(Meal(slot: .lunch)),
        .disclaimer(try Disclaimer("下雨了，跑道在哭")),
    ]
    for entry in entries {
        let checkIn = CheckIn(id: checkInID, member: memberID, day: try LocalDay("2025-10-17"),
                              createdAt: createdAt, entry: entry)
        #expect(try decode(try encode(checkIn)) == checkIn)
    }
}

@Test func disclaimerDecodesFromWire() throws {
    let json = #"{"version":1,"id":"11111111-1111-1111-1111-111111111111","member":"22222222-2222-2222-2222-222222222222","day":"2025-10-17","createdAt":"2025-10-18T00:00:00Z","kind":"disclaimer","disclaimer":{"text":"  腿还在酸  "}}"#
    #expect(try decode(json).entry == .disclaimer(try Disclaimer("腿还在酸")))
}

@Test func unknownVersionIsRejected() {
    let json = #"{"version":2,"id":"11111111-1111-1111-1111-111111111111","member":"22222222-2222-2222-2222-222222222222","day":"2025-10-17","createdAt":"2025-10-18T00:00:00Z","kind":"ateClean","meal":{"slot":"dinner"}}"#
    #expect(throws: ContractsError.unsupportedVersion(2)) { try decode(json) }
}

@Test func outOfRangeMinutesAreRejectedOnDecode() {
    let json = #"{"version":1,"id":"11111111-1111-1111-1111-111111111111","member":"22222222-2222-2222-2222-222222222222","day":"2025-10-17","createdAt":"2025-10-18T00:00:00Z","kind":"trained","training":{"sport":"run","minutes":0}}"#
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
