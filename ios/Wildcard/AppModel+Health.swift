import HealthUI

extension AppModel {
    /// Apple Health through HealthKit, one for the app: a member signing in again keeps it, and
    /// what it shares by default is this phone's.
    static let health = HealthConnection(library: HealthKitLibrary())
}
