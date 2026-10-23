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
