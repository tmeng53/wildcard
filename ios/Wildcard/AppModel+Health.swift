import Backend
import Foundation
import HealthUI

extension AppModel {
    /// Apple Health through HealthKit, one for the app: a member signing in again keeps it, and
    /// what it shares by default is this phone's. Kept in the app group, so the home screen
    /// widgets offer the same workout 今天's card does.
    static let health: HealthConnection = {
        let defaults = AppGroup.defaults ?? .standard
        HealthConnection.share(from: .standard, to: defaults)
        return HealthConnection(library: HealthKitLibrary(defaults: defaults), defaults: defaults)
    }()
}
