import Foundation

/// A store on the character editor's 商店街, a prop or a piece of clothing in a store that the
/// member unlocked by training: `checkIns` 练了 in one of `sports` (any sport when empty). Never
/// taken back. Starters (WARM-UP, the tumbler, the dumbbell and every piece without a rule) are
/// everyone's and never unlocked.
public struct Unlock: Hashable, Sendable {
    public enum Kind: String, Hashable, Sendable {
        case store, prop, piece
    }

    public let kind: Kind
    /// Its id in the art, such as `deuce`, `racket` or `lap-bib`.
    public let id: String
    /// When the member made the check-in that unlocked it.
    public let unlockedAt: Date
    public let sports: [Sport]
    public let checkIns: Int

    public init(kind: Kind, id: String, unlockedAt: Date, sports: [Sport], checkIns: Int) {
        (self.kind, self.id, self.unlockedAt, self.sports, self.checkIns) = (kind, id, unlockedAt, sports, checkIns)
    }
}

/// A piece of clothing that stays locked in its store, even an open one, until the member's
/// training reaches its rule: the editor shows it as a 「？」 box until then.
public struct LockedPiece: Hashable, Sendable {
    /// The piece's id in the art, such as `lap-bib`.
    public let id: String
    /// How many more 练了 in its sports open it, 1 or more.
    public let checkInsToGo: Int

    public init(id: String, checkInsToGo: Int) {
        (self.id, self.checkInsToGo) = (id, checkInsToGo)
    }
}

/// Everything the member unlocked, and the pieces still locked.
public struct UnlockStanding: Hashable, Sendable {
    /// The stores, props and pieces unlocked, the earliest first.
    public let unlocks: [Unlock]
    public let lockedPieces: [LockedPiece]

    public init(unlocks: [Unlock], lockedPieces: [LockedPiece]) {
        (self.unlocks, self.lockedPieces) = (unlocks, lockedPieces)
    }
}
