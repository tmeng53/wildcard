/// The character editor's 商店街 as it stands for a member now: which stores are open and which
/// pieces they may see. The server works it out from the stores', pieces' and switches' rows
/// (`GET /me/unlocks`, `stock`), so a limited store such as POWDER DAY opens and closes as data,
/// and the app only draws it.
public struct StreetStock: Hashable, Sendable {
    /// A store on the street, in its order.
    public struct Store: Hashable, Sendable {
        /// Its id in the art, such as `powder`.
        public let id: String
        /// Whether it is open now (its switch on). A closed store shows only what the member owns.
        public let isOpen: Bool
        /// For a store the member hasn't earned yet: how many more 练了 open it. Nil once earned,
        /// for a store without a rule, and from a server that doesn't say.
        public let toGo: Int?

        public init(id: String, isOpen: Bool, toGo: Int? = nil) {
            (self.id, self.isOpen, self.toGo) = (id, isOpen, toGo)
        }
    }

    /// Where a piece stands for the member.
    public enum State: Hashable, Sendable {
        /// The member's: unlocked or claimed, worn all year whatever the switches, or a limited
        /// store's starter while it is open (it waits on 商店街 to be claimed and kept).
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
        /// The sports whose 练了 count towards it; empty for any sport.
        public let sports: [Sport]

        public init(id: String, store: String, state: State, sports: [Sport] = []) {
            (self.id, self.store, self.state, self.sports) = (id, store, state, sports)
        }
    }

    public let stores: [Store]
    /// Every piece the member may see; one left out is not shown.
    public let pieces: [Piece]

    public init(stores: [Store], pieces: [Piece]) {
        (self.stores, self.pieces) = (stores, pieces)
    }

    /// Nothing on the street.
    public static let empty = StreetStock(stores: [], pieces: [])
}
