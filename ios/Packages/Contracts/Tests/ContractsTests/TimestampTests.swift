import Foundation
import Testing
import Contracts

@Test func readsWhatSupabaseReturns() throws {
    #expect(try Timestamp("2025-10-18T00:00:00.123456+00:00").millisecondsSince1970 == 1_760_745_600_123)
    #expect(try Timestamp("2025-10-18T08:00:00.5+08:00").millisecondsSince1970 == 1_760_745_600_500)
    #expect(try Timestamp("2025-10-18T00:00:00Z").millisecondsSince1970 == 1_760_745_600_000)
}

@Test func writesMillisecondsInUTC() {
    #expect(Timestamp(millisecondsSince1970: 1_760_745_600_007).description == "2025-10-18T00:00:00.007Z")
    #expect(Timestamp(millisecondsSince1970: -1).description == "1969-12-31T23:59:59.999Z")
}

@Test func aDateWithMicrosecondsRoundTripsThroughTheWire() throws {
    let made = Timestamp(Date(timeIntervalSince1970: 1_760_745_600.123456))
    let wire = try WireJSON.encoder().encode([made])
    #expect(try WireJSON.decoder().decode([Timestamp].self, from: wire) == [made])
    #expect(made.millisecondsSince1970 == 1_760_745_600_123)
}

@Test func nonISOTimestampsAreRejected() {
    #expect(throws: ContractsError.invalidTimestamp("2025-10-18 00:00:00")) { try Timestamp("2025-10-18 00:00:00") }
    #expect(throws: ContractsError.invalidTimestamp("2025-10-18T00:00:00.Z")) { try Timestamp("2025-10-18T00:00:00.Z") }
}
