import Contracts
import Synchronization

/// The 商店街 of a member who hasn't trained yet (`AppCatalog.starterStock`), for an editor opened
/// before the member's own street is read, such as sign-up's first screen and the sample squad.
/// It starts empty, and the app sets it at launch and whenever it reads the API's catalog.
public final class StarterStock: Sendable {
    /// The app's starter street.
    public static let shared = StarterStock()

    private let stock = Mutex<StreetStock>(.empty)

    public init() {}

    public func show(_ stock: StreetStock) { self.stock.withLock { $0 = stock } }

    public var current: StreetStock { stock.withLock { $0 } }
}
