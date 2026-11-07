#if os(iOS)
/// 本周目标's count for the poster at 上场.
extension SignUpModel {
    /// The template's training days from today on: what this week plans, since the first week
    /// counts only from the day the member joined.
    var plannedThisWeek: Int {
        week?.trainingDays(from: daysGone) ?? 0
    }
}
#endif
