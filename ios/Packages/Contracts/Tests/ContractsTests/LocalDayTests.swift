import Testing
import Contracts

@Test func parsesAndPrintsTheSameDay() throws {
    #expect(try LocalDay("2024-02-29").description == "2024-02-29")
    #expect(try LocalDay(year: 2026, month: 1, day: 5).description == "2026-01-05")
}

@Test(arguments: ["2025-02-29", "2025-13-01", "2025-04-31", "2025-1-01", "20251017", "", "2025-10-1x"])
func rejectsDaysThatDontExist(text: String) {
    #expect(throws: ContractsError.invalidDay(text)) { try LocalDay(text) }
}

@Test func ordersByCalendar() throws {
    #expect(try LocalDay("2025-12-31") < LocalDay("2026-01-01"))
    #expect(!(try LocalDay("2026-01-01") < LocalDay("2026-01-01")))
}
