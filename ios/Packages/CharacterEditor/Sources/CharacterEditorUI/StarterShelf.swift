import Contracts
import Synchronization

/// The 商店街 of a member who hasn't trained yet (`AppCatalog.starterShelf`), for an editor opened
/// before the member's own street is read, such as sign-up's first screen and the sample squad.
/// It starts empty, and the app sets it at launch and whenever it reads the API's catalog.
public final class StarterShelf: Sendable {
    /// The app's starter street.
    public static let shared = StarterShelf()

    private let shelf = Mutex<Shelf>(.empty)

    public init() {}

    public func show(_ shelf: Shelf) { self.shelf.withLock { $0 = shelf } }

    public var current: Shelf { shelf.withLock { $0 } }
}
