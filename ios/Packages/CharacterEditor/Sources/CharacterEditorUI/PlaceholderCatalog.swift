import AvatarArt
import AvatarDomain
import CharacterEditorDomain

extension Catalog {
    /// What the placeholder character's bundled art offers: the species, stores, clothes and
    /// props in its `editor.json`, every bundled hair and face part, and their preset colors.
    public static func placeholder() throws(AvatarError) -> Catalog {
        let choices = try PlaceholderCharacter.editorChoices()
        var variants = choices.wear.mapValues { $0.map(\.id) }
        for slot in ["hair"] + PlaceholderCharacter.faceSlots {
            variants[slot] = PlaceholderCharacter.variants(for: slot)
        }
        var swatches: [Slot: [String: [RGBAColor]]] = [:]
        var originals: [Slot: [String: RGBAColor]] = [:]
        // Typed piece by piece: as one literal, Xcode's type checker gives up on it.
        let bodies: [String] = choices.species.flatMap(\.bodies)
        var recolorable: [(Slot, [String])] = [("body", bodies)]
        for slot: Slot in ["hair", "eyes", "brows"] + Catalog.clothingSlots {
            recolorable.append((slot, variants[slot] ?? []))
        }
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
        var storeOf: [String: String] = [:]
        for piece in choices.wear.values.joined() {
            storeOf[piece.id] = piece.store
        }
        return Catalog(
            species: choices.species, variants: variants, props: choices.props, swatches: swatches,
            originals: originals,
            defaults: try PlaceholderCharacter.rig().defaults.filter { Catalog.dressSlots.contains($0.key) },
            stores: choices.stores, storeOf: storeOf)
    }
}
