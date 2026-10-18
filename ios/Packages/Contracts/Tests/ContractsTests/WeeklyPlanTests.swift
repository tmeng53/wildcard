import Contracts
import Foundation
import Testing

private let memberID = MemberID(UUID(uuidString: "22222222-2222-2222-2222-222222222222")!)

@Test func planEncodesToTheWireShape() throws {
    let plan = try WeeklyPlan(
        member: memberID, weekStart: try LocalDay("2025-10-20"),
        days: [
            .train(.run), .rest, .train(.strength), .train(nil), .rest, .train(.yoga), .rest,
        ])
    let json = String(decoding: try WireJSON.encoder().encode(plan), as: UTF8.self)
    #expect(
        json
            == #"{"days":[{"kind":"train","sport":"run"},{"kind":"rest"},{"kind":"train","sport":"strength"},{"kind":"train"},{"kind":"rest"},{"kind":"train","sport":"yoga"},{"kind":"rest"}],"member":"22222222-2222-2222-2222-222222222222","version":1,"weekStart":"2025-10-20"}"#
    )
    #expect(try WireJSON.decoder().decode(WeeklyPlan.self, from: Data(json.utf8)) == plan)
}

@Test func planNeedsSevenDays() {
    #expect(throws: ContractsError.planLength(6)) {
        try WeeklyPlan(member: memberID, weekStart: try LocalDay("2025-10-20"), days: Array(repeating: .rest, count: 6))
    }
}

@Test func restDayWithASportIsRejected() {
    let json =
        #"{"version":1,"member":"22222222-2222-2222-2222-222222222222","weekStart":"2025-10-20","days":[{"kind":"rest","sport":"run"},{"kind":"rest"},{"kind":"rest"},{"kind":"rest"},{"kind":"rest"},{"kind":"rest"},{"kind":"rest"}]}"#
    #expect(throws: ContractsError.payloadMismatch("rest")) {
        try WireJSON.decoder().decode(WeeklyPlan.self, from: Data(json.utf8))
    }
}

@Test func unknownPlanVersionIsRejected() {
    let json = #"{"version":2,"member":"22222222-2222-2222-2222-222222222222","weekStart":"2025-10-20","days":[]}"#
    #expect(throws: ContractsError.unsupportedVersion(2)) {
        try WireJSON.decoder().decode(WeeklyPlan.self, from: Data(json.utf8))
    }
}
