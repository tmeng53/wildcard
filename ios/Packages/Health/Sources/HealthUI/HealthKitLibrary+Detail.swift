#if canImport(HealthKit) && os(iOS)
extension HealthKitLibrary {
    /// How much of each workout a read brings.
    public enum Detail: Sendable {
        /// Everything a post needs: the numbers, the route and the chart's series.
        case full
        /// The numbers alone, no route, series or resting heart rate, as a widget's summary shows
        /// them: a read that fits a widget extension's memory and time (a ski day's runs, which
        /// come from its route, are left out).
        case numbers
    }
}
#endif
