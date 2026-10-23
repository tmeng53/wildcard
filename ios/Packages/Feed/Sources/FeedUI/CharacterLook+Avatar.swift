#if os(iOS)
import AvatarArt
import AvatarDomain
import Contracts

extension CharacterLook {
    /// The look as the character player draws it. A swatch that isn't `#rrggbb` is left out, so
    /// the slot keeps its art's color.
    var outfit: Outfit {
        Outfit(
            Dictionary(uniqueKeysWithValues: variants.map { (Slot($0.key), $0.value) }),
            colors: Dictionary(
                uniqueKeysWithValues: colors.compactMap { slot, hex in
                    RGBAColor(hex: hex).map { (Slot(slot), $0) }
                }))
    }

    /// How it moves; a persona this build doesn't know plays energetic.
    var moves: Persona { Persona(rawValue: persona) ?? .energetic }

    /// The species its body belongs to (`cat`, `person`, ...), for the species' own moves.
    var species: String? {
        guard let body = variants["body"], let choices = try? PlaceholderCharacter.editorChoices() else { return nil }
        return choices.species.first { $0.bodies.contains(body) }?.id
    }
}
#endif
