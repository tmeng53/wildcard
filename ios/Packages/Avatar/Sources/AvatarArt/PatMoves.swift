import AvatarDomain

/// 拍一拍 on the home scene: one character pats a teammate from where it stands, and the teammate
/// takes it their persona's way. Both play at their own speed, so the pat lands on the reaction's
/// first frame.
extension PlaceholderCharacter {
    /// The pat, `moves/pat.json`: a quick jab of the right arm from where the character stands,
    /// the approved interaction's poke without its hop across.
    public static func patMove() throws(AvatarError) -> Clip {
        try Clip.decode(file("moves/pat.json"))
    }

    /// How a `persona` takes a pat, `moves/patted/<persona>.json`: 淡人 barely blinks, 高能量
    /// jumps and cheers, 显眼包 turns it into a pose, 戏精 staggers, 社恐 shrinks away.
    public static func pattedMove(_ persona: Persona) throws(AvatarError) -> Clip {
        try Clip.decode(file("moves/patted/\(persona.rawValue).json"))
    }

    /// When in the pat the hand lands, in seconds from its start: when the reaction starts and
    /// the one haptic plays.
    public static let patContact = 0.72

    /// How far past the canvas a pat or its reaction reaches, in canvas points: 戏精 staggers
    /// back and lies down for a moment, so a screen that plays them draws the figure with this
    /// much room to either side, above and below its feet.
    public static let patReachSideways = 120.0
    public static let patReachAbove = 60.0
    public static let patReachBelow = 16.0
}
