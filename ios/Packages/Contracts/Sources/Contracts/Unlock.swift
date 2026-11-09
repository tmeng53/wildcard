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

/// Everything the member unlocked, what they claimed, and the 商店街 as it stands for them.
public struct UnlockStanding: Hashable, Sendable {
    /// The stores, props and pieces unlocked, the earliest first.
    public let unlocks: [Unlock]
    /// The unlocked pieces the member claimed (领取) into their wardrobe.
    public let claimed: Set<String>
    public let stock: StreetStock
    /// What was given the member, in their wardrobe on no store's rack and worn without 领取: the
    /// coach's gifts they opened (拆开), then the pieces the team gave, each the earliest given
    /// first. An unopened gift waits in its box on the coach page.
    public let gifts: [String]

    public init(unlocks: [Unlock], claimed: Set<String> = [], stock: StreetStock, gifts: [String] = []) {
        (self.unlocks, self.claimed, self.stock, self.gifts) = (unlocks, claimed, stock, gifts)
    }
}
