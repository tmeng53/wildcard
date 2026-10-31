import Contracts
import Foundation
import Testing

private let memberID = MemberID(UUID(uuidString: "22222222-2222-2222-2222-222222222222")!)

@Test func planKeepsItsSevenDaysInOrder() throws {
    let days: [PlanDay] = [
        .train(.sport("run")), .rest, .train(.sport("strength")), .train(nil), .rest,
        .train(.custom(try CustomSport("飞盘"))), .rest,
    ]
    let plan = try WeeklyPlan(member: memberID, weekStart: try LocalDay("2025-10-20"), days: days)
    #expect(plan.days == days)
    #expect(plan.weekStart.description == "2025-10-20")
}

@Test func planNeedsSevenDays() {
    #expect(throws: ContractsError.planLength(6)) {
        try WeeklyPlan(member: memberID, weekStart: try LocalDay("2025-10-20"), days: Array(repeating: .rest, count: 6))
    }
}
