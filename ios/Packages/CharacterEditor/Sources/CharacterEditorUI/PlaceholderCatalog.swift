import AvatarArt
import AvatarDomain
import CharacterEditorDomain

extension Catalog {
    /// What the placeholder character's bundled art offers: the species, hats and props in its
    /// `editor.json`, every bundled hair, top and bottom, and their preset colors.
    public static func placeholder() throws(AvatarError) -> Catalog {
        let choices = try PlaceholderCharacter.editorChoices()
        var variants: [Slot: [String]] = ["hat": choices.hats]
        for slot: Slot in ["hair", "top", "bottom"] {
            variants[slot] = PlaceholderCharacter.variants(for: slot)
        }
        var swatches: [Slot: [String: [RGBAColor]]] = [:]
        var originals: [Slot: [String: RGBAColor]] = [:]
        let recolorable: [(Slot, [String])] = [
            ("body", choices.species.flatMap(\.bodies)), ("hair", variants["hair"] ?? []),
            ("top", variants["top"] ?? []), ("bottom", variants["bottom"] ?? []),
        ]
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
            originals: originals)
    }
}
