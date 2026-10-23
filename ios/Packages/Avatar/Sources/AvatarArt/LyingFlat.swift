import AvatarDomain

extension PlaceholderCharacter {
    /// 躺平, for a 请假条 day on the 战报 (`moves/flat.json`): lets itself fall flat on its back
    /// under gravity, breathes slowly with its eyes shut, and one foot taps. It doesn't get up:
    /// it ends lying down, so a screen holds it (`lyingFlatFrom` seconds in it is down) and plays
    /// it without blending back. Falling and lying down it reaches `lyingFlatReach` points past
    /// either side of the canvas, so the screen leaves that room. Played at `persona`'s tempo.
    public static func lyingFlat(persona: Persona) throws(AvatarError) -> Clip {
        try Clip.decode(file("moves/flat.json")).atTempo(persona.accentTempo)
    }

    /// When the fall lands, in seconds at the 戏精's tempo (1); divide by a persona's
    /// `accentTempo` for theirs.
    public static let lyingFlatFrom = 0.95

    /// How far past either side of the canvas the figure reaches, in canvas points.
    public static let lyingFlatReach = 45.0
}
