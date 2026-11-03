import Foundation

/// A store on the character editor's 商店街, or a prop, that the member unlocked by training:
/// `checkIns` 练了 in one of `sports` (any sport when empty). Never taken back. Starters (WARM-UP,
/// the tumbler and the dumbbell) are everyone's and never unlocked.
public struct Unlock: Hashable, Sendable {
    public enum Kind: String, Hashable, Sendable {
        case store, prop
    }

    public let kind: Kind
    /// The store's or prop's id in the art, such as `deuce` or `racket`.
    public let id: String
    /// When the member made the check-in that unlocked it.
    public let unlockedAt: Date
    public let sports: [Sport]
    public let checkIns: Int

    public init(kind: Kind, id: String, unlockedAt: Date, sports: [Sport], checkIns: Int) {
        (self.kind, self.id, self.unlockedAt, self.sports, self.checkIns) = (kind, id, unlockedAt, sports, checkIns)
    }
}
