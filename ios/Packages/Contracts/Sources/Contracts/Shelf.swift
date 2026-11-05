/// The character editor's 商店街 as it stands for a member now: which stores are open and which
/// pieces they may see. The server works it out from the stores', pieces' and switches' rows
/// (`GET /me/unlocks`, `shelf`), so a limited store such as POWDER DAY opens and closes as data,
/// and the app only draws it.
public struct Shelf: Hashable, Sendable {
    /// A store on the street, in its order.
    public struct Store: Hashable, Sendable {
        /// Its id in the art, such as `powder`.
        public let id: String
        /// Whether it is open now (its switch on). A closed store shows only what the member owns.
        public let isOpen: Bool

        public init(id: String, isOpen: Bool) {
            (self.id, self.isOpen) = (id, isOpen)
        }
    }

    /// Where a piece stands for the member.
    public enum State: Hashable, Sendable {
        /// Unlocked: worn all year, whatever the switches.
        case owned
        /// A starter that is out now.
        case available
        /// Still to earn, `toGo` more 练了: a 「？」 box.
        case locked(toGo: Int)
    }

    /// A piece the member may see.
    public struct Piece: Hashable, Sendable {
        /// Its id in the art, such as `powder-tuna`.
        public let id: String
        /// The store it hangs in.
        public let store: String
        public let state: State

        public init(id: String, store: String, state: State) {
            (self.id, self.store, self.state) = (id, store, state)
        }
    }

    public let stores: [Store]
    /// Every piece the member may see; one left out is not shown.
    public let pieces: [Piece]

    public init(stores: [Store], pieces: [Piece]) {
        (self.stores, self.pieces) = (stores, pieces)
    }

    /// Nothing on the street.
    public static let empty = Shelf(stores: [], pieces: [])
}
