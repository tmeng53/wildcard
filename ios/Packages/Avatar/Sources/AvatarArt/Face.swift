import AvatarDomain

extension PlaceholderCharacter {
    /// The face a person's look picks: eyes, brows, mouth, cheeks and glasses. Animals keep
    /// the rig's default face for now, their coat doing the work.
    public static let faceSlots: [Slot] = ["eyes", "brows", "mouth", "cheeks", "glasses"]

    /// The bodies that are people (a skin tone) rather than animals.
    public static let people: Set<String> = ["peach", "tan"]

    /// The slots the character editor offers a look with this body, in the editor's order:
    /// people get hair and a face, animals neither.
    public static func slots(for body: String) -> [Slot] {
        let worn: [Slot] = ["hat", "top", "bottom", "prop"]
        return people.contains(body) ? ["body", "hair"] + faceSlots + worn : ["body"] + worn
    }
}

extension Outfit {
    /// Dyes the hair, and the brows with it unless the look gave them a color of their own:
    /// brows follow the hair until someone picks them separately.
    public mutating func dyeHair(_ color: RGBAColor) {
        if colors["brows"] == colors["hair"] { colors["brows"] = color }
        colors["hair"] = color
    }
}
