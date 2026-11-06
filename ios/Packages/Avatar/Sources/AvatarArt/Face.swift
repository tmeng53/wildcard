import AvatarDomain

extension PlaceholderCharacter {
    /// The face a look picks, people and animals alike: eyes, brows, mouth, cheeks and glasses.
    public static let faceSlots: [Slot] = ["eyes", "brows", "mouth", "cheeks", "glasses"]

    /// The cheeks an animal starts with, the blush its coat drew before animals picked a face.
    public static let animalCheeks = "rosy"

    /// Coats that still draw their own blush, so they start without cheeks: a lop's ears hang
    /// over where the cheeks go, so its blush stays in its `shine`, over the ears.
    public static let blushingCoats: Set<String> = ["lop"]
}
