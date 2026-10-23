import AvatarDomain
import Contracts

// A member's look as the API keeps it (`CharacterLook`, ids and `#RRGGBB` swatches) and as the
// character player draws it (`Outfit` and `Persona`). Ids pass through as data, so new art needs
// no change here; one this build doesn't know draws the slot's default.

extension Outfit {
    /// The variants and swatches a look picks. A color that isn't `#RRGGBB` is left out, so its
    /// slot keeps the art's own.
    public init(_ look: CharacterLook) {
        self.init(
            Dictionary(uniqueKeysWithValues: look.variants.map { (Slot($0.key), $0.value) }),
            colors: look.colors.reduce(into: [:]) { colors, entry in
                if let color = RGBAColor(hex: entry.value) { colors[Slot(entry.key)] = color }
            })
    }
}

extension Persona {
    /// The look's persona; one this build doesn't know moves as `.energetic`, the editor's
    /// default.
    public init(_ look: CharacterLook) {
        self = Persona(rawValue: look.persona) ?? .energetic
    }
}

extension CharacterLook {
    /// The look of a character in this outfit, moving as this persona, with each swatch as
    /// `#RRGGBB` in capitals, as the API keeps it.
    public init(outfit: Outfit, persona: Persona) {
        self.init(
            persona: persona.rawValue,
            variants: Dictionary(uniqueKeysWithValues: outfit.variants.map { ($0.key.rawValue, $0.value) }),
            colors: Dictionary(uniqueKeysWithValues: outfit.colors.map { ($0.key.rawValue, $0.value.hex) }))
    }
}
