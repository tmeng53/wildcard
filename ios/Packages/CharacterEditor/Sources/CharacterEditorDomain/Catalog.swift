import AvatarArt
import AvatarDomain

/// Everything the editor offers: bodies by species, the variants of every other slot, the
/// props of this release, and the preset colors per variant. A plain value, so the draft's
/// rules test without the bundle; `CharacterEditorUI` reads the real one from the art.
public struct Catalog: Hashable, Sendable {
    public var species: [EditorChoices.Species]
    /// The variants of every slot but `body` and `prop`, in display order.
    public var variants: [Slot: [String]]
    public var props: [String]
    /// The preset colors per slot and variant; a variant left out keeps its art's colors.
    public var swatches: [Slot: [String: [RGBAColor]]]
    /// The color a recolorable variant shows before any swatch is picked (the 原色 swatch).
    public var originals: [Slot: [String: RGBAColor]]

    public init(
        species: [EditorChoices.Species], variants: [Slot: [String]], props: [String],
        swatches: [Slot: [String: [RGBAColor]]], originals: [Slot: [String: RGBAColor]]
    ) {
        (self.species, self.variants, self.props) = (species, variants, props)
        (self.swatches, self.originals) = (swatches, originals)
    }

    /// The preset colors `variant` offers in `slot`; empty when it keeps its art's colors.
    public func swatches(for slot: Slot, wearing variant: String) -> [RGBAColor] {
        swatches[slot]?[variant] ?? []
    }

    public func species(of body: String) -> EditorChoices.Species? {
        species.first { $0.bodies.contains(body) }
    }

    /// The slots picked by tiles, besides `body`: what a look may wear.
    public static let dressSlots: [Slot] = ["hair", "hat", "top", "bottom", "prop"]
}
