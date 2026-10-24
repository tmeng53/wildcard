import AvatarDomain

extension PlaceholderCharacter {
    /// When the drop touches the ground, in seconds; from then on the figure stays on its canvas.
    public static let dropLands = 0.55

    /// How far above its spot the drop starts a figure, in the rig's points.
    public static let dropHeight = 420.0

    /// Drops in from above and lands on its spot with weight, as the squad does when a new scene
    /// is revealed: a squash on touch-down, knees giving, dust from both feet, a small bounce
    /// and a wobble, then rest. The same for every look and persona; nothing turns or spins.
    ///
    /// It starts 420 points above the spot, so like the entrance it leaves the canvas: draw it
    /// with a `crop` that reaches above the stage, and play it without blending
    /// (`CharacterPlayer.play(_:blending: false)`) so it doesn't slide up from where it stood.
    /// The shadow stays on the ground and grows as the figure nears it.
    public static func drop() throws(AvatarError) -> Clip {
        try Clip.decode(file("moves/drop.json"))
    }
}
