import AvatarArt
import AvatarDomain

/// Everything the editor offers: bodies by species, the variants of every other slot, the
/// props of this release, the preset colors per variant, and what a slot left empty wears. A
/// plain value, so the draft's rules test without the bundle; `CharacterEditorUI` reads the
/// real one from the art.
public struct Catalog: Hashable, Sendable {
    public var species: [EditorChoices.Species]
    /// The variants of every slot but `body` and `prop`, in display order: hair, the face's
    /// slots, hats, tops, bottoms and shoes.
    public var variants: [Slot: [String]]
    public var props: [String]
    /// The preset colors per slot and variant; a variant left out keeps its art's colors.
    public var swatches: [Slot: [String: [RGBAColor]]]
    /// The color a recolorable variant shows before any swatch is picked (the 原色 swatch).
    public var originals: [Slot: [String: RGBAColor]]
    /// What a slot the look leaves empty wears anyway: the rig's round eyes, smile and sneakers.
    public var defaults: [Slot: String]

    public init(
        species: [EditorChoices.Species], variants: [Slot: [String]], props: [String],
        swatches: [Slot: [String: [RGBAColor]]], originals: [Slot: [String: RGBAColor]],
        defaults: [Slot: String] = [:]
    ) {
        (self.species, self.variants, self.props) = (species, variants, props)
        (self.swatches, self.originals, self.defaults) = (swatches, originals, defaults)
    }

    /// The preset colors `variant` offers in `slot`; empty when it keeps its art's colors.
    public func swatches(for slot: Slot, wearing variant: String) -> [RGBAColor] {
        swatches[slot]?[variant] ?? []
    }

    public func species(of body: String) -> EditorChoices.Species? {
        species.first { $0.bodies.contains(body) }
    }
}
