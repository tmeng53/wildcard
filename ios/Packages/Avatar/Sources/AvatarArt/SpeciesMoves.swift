import AvatarDomain

extension PlaceholderCharacter {
    /// A persona's `idle` or `cheer`, with the moves of a species on top (an `editor.json`
    /// species id): a cat's yawn, a dog's wag, a rabbit's ears. Each species' moves are
    /// `accents/<species>/<name>.json`; one that has none for this clip plays the persona's
    /// clip as it is.
    public static func clip(_ name: String, persona: Persona, species: String?) throws(AvatarError) -> Clip {
        let clip = try clip(name, persona: persona)
        guard let species, let data = try? file("accents/\(species)/\(name).json")
        else { return clip }
        return try clip.accented(by: Clip.decode(data), tempo: persona.accentTempo, strength: persona.accentStrength)
    }

    /// The species `editor.json` groups an outfit's body under, whose moves its clips play with;
    /// nil for a body it doesn't list.
    public static func species(of outfit: Outfit) -> String? {
        guard let body = outfit.variants["body"] else { return nil }
        return speciesByBody[body]
    }

    private static let speciesByBody: [String: String] = {
        guard let choices = try? editorChoices() else { return [:] }
        var byBody: [String: String] = [:]
        for species in choices.species {
            for body in species.bodies { byBody[body] = species.id }
        }
        return byBody
    }()
}

extension Persona {
    /// How fast a species' idle moves and a sport's move play for this persona: a deadpan cat
    /// yawns and swims slowly, an energetic dog wags and swims fast.
    public var accentTempo: Double {
        switch self {
        case .deadpan: 0.7
        case .energetic: 1.4
        case .showoff: 1.1
        case .drama: 0.9
        case .shy: 0.85
        }
    }

    /// How far a species' moves go for this persona.
    public var accentStrength: Double {
        switch self {
        case .deadpan: 0.6
        case .energetic: 1.2
        case .showoff: 1.1
        case .drama: 1.3
        case .shy: 0.7
        }
    }
}
