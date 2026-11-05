import Contracts
import DesignSystemUI
import Foundation
import Observation
import Synchronization

/// The sports list this app shows now, the one every picker and label reads. It starts as the
/// copy the app keeps (the last one the API served, else the one it ships with) and changes when
/// a newer one arrives, so screens showing sports redraw. Any thread may read it, so a label is
/// as easy to use off the main actor as on it.
public final class SportList: Observable, Sendable {
    /// The app's list. The app sets it at launch and whenever it reads the API's.
    public static let shared = SportList()

    private let registrar = ObservationRegistrar()
    private let current = Mutex(SportCatalog.empty)

    init() {}

    public var catalog: SportCatalog {
        registrar.access(self, keyPath: \.catalog)
        return current.withLock { $0 }
    }

    public func show(_ catalog: SportCatalog) {
        guard current.withLock({ $0 != catalog }) else { return }
        registrar.withMutation(of: self, keyPath: \.catalog) { current.withLock { $0 = catalog } }
    }
}

extension CatalogNames {
    /// The words in the language the app speaks now (`AppLanguage`, which a pick in the app
    /// changes at once).
    public var localized: String { localized(in: [AppLanguage.current.rawValue]) }
}
