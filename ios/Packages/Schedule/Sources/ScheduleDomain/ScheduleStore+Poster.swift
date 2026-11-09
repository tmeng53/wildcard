import Contracts

extension ScheduleStore {
    /// What the member trains at on day `index` (Monday 0) of the week or 我的每周计划 shown, as
    /// its lane shows it (`WeekSheet.activity`, the board's days while they change); nil for a
    /// rest day, a day with no sport picked, or before the week has loaded.
    public func shownActivity(on index: Int) -> Activity? {
        if showsTemplate {
            guard let days = board?.days, days.indices.contains(index), case .train(let activity?) = days[index]
            else { return nil }
            return activity
        }
        guard let sheet else { return nil }
        return sheet.activity(on: index, plan: sheet.plan)
    }
}
