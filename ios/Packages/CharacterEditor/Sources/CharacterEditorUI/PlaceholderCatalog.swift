import AvatarArt
import AvatarDomain
import CharacterEditorDomain

extension Catalog {
    /// What the placeholder character's bundled art offers: the species, hats, shoes and props in
    /// its `editor.json`, every bundled hair, face part, top and bottom, their preset colors, and
    /// the rig's defaults for slots left empty.
    public static func placeholder() throws(AvatarError) -> Catalog {
        let choices = try PlaceholderCharacter.editorChoices()
        var variants: [Slot: [String]] = ["hat": choices.hats, "shoes": choices.shoes]
        for slot in ["hair", "top", "bottom"] + PlaceholderCharacter.faceSlots {
            variants[slot] = PlaceholderCharacter.variants(for: slot)
        }
        var swatches: [Slot: [String: [RGBAColor]]] = [:]
        var originals: [Slot: [String: RGBAColor]] = [:]
        let recolorable: [(Slot, [String])] =
            [("body", choices.species.flatMap(\.bodies))]
            + (["hair", "eyes", "brows", "top", "bottom"] as [Slot]).map { ($0, variants[$0] ?? []) }
        for (slot, names) in recolorable {
            for name in names {
                let colors = PlaceholderCharacter.swatches(for: slot, wearing: name)
                guard !colors.isEmpty, let tones = PlaceholderCharacter.tones(for: slot, wearing: name) else {
                    continue
                }
                swatches[slot, default: [:]][name] = colors
                originals[slot, default: [:]][name] = tones.base
            }
        }
        return Catalog(
            species: choices.species, variants: variants, props: choices.props, swatches: swatches,
            originals: originals, defaults: try PlaceholderCharacter.rig().defaults)
    }
}
