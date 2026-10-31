import AvatarDomain

extension PlaceholderCharacter {
    /// The move the prop `outfit` holds has of its own (`moves/props/<prop>.json`), played once
    /// whenever the character editor changes the look: a dumbbell's two presses, a racket's
    /// swing. Nil when the look holds nothing, or a prop without a move.
    public static func propMove(for outfit: Outfit) throws(AvatarError) -> Clip? {
        guard let prop = outfit.variants["prop"], let data = try? file("moves/props/\(prop).json") else { return nil }
        return try Clip.decode(data)
    }
}

extension PlaceholderCharacter {
    /// What a character plays once when its member taps it on the home: the move of the prop it
    /// holds (the kit's, once it trained today) at the persona's tempo, or, holding none with a
    /// move, the persona's cheer.
    public static func signatureMove(wearing outfit: Outfit, persona: Persona) throws(AvatarError) -> Clip {
        if let move = try propMove(for: outfit) { return try move.atTempo(persona.accentTempo) }
        return try clip("cheer", persona: persona, species: species(of: outfit))
    }
}
