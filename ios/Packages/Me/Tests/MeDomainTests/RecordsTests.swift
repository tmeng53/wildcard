import Contracts
import Testing

@testable import MeDomain

private func records(hours: [Int: Int] = [:], weekdays: [Int] = [0, 0, 0, 0, 0, 0, 0], minutes: Int = 0)
    -> WildcardRecords
{
    var clock = Array(repeating: 0, count: 24)
    for (hour, count) in hours { clock[hour] = count }
    return WildcardRecords(
        trainedDays: weekdays.reduce(0, +), minutes: minutes, longestMinutes: nil, longestStreak: nil, mealStreak: nil,
        hours: clock, weekdays: weekdays, sports: [], sportCount: 0, squad: nil)
}

@Test func theUsualHourIsTheMostTrainedTheLatestOnATie() {
    #expect(records(hours: [7: 3, 19: 7, 20: 5]).usualHour == 19)
    #expect(records(hours: [7: 4, 19: 4]).usualHour == 19)
    #expect(records().usualHour == nil)
}

@Test func theBusiestWeekdayIsTheFirstOnATie() {
    #expect(records(weekdays: [5, 6, 3, 4, 4, 3, 2]).busiestWeekday == 1)
    #expect(records(weekdays: [2, 0, 2, 0, 0, 0, 0]).busiestWeekday == 0)
    #expect(records().busiestWeekday == nil)
}

@Test func hoursTrainedRoundDown() {
    #expect(records(minutes: 1290).hoursTrained == 21)
    #expect(records(minutes: 59).hoursTrained == 0)
}

@Test func theRunStillGoingBreaksTheRecordOnceItReachesIt() throws {
    let run = { (days: Int) in
        WildcardRecords.Streak(
            days: days, first: try LocalDay(year: 2026, month: 11, day: 1),
            last: try LocalDay(year: 2026, month: 11, day: 1))
    }
    #expect(WildcardRecords.breaksRecord(current: try run(6), longest: try run(6)))
    #expect(!WildcardRecords.breaksRecord(current: try run(3), longest: try run(6)))
    #expect(!WildcardRecords.breaksRecord(current: nil, longest: try run(6)))
    #expect(!WildcardRecords.breaksRecord(current: nil, longest: nil))
}

@Test func aFailedReadSaysSo() async {
    let service = FakeService(sample)
    await service.fail(with: .unavailable)
    let model = await RecordsModel(service: service)
    await model.reload()
    #expect(await model.load == .failed(.unavailable))
}
