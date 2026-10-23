import AvatarDomain

/// A move any character can play once, for a moment in the app: cheering a teammate on, a
/// 名场面, being poked. Each is `moves/<raw value>.json`, the same for every look, played at the
/// persona's tempo; it ends at rest, so the idle picks up without a jump. Which moment plays
/// which move is the screen's call.
public enum Move: String, CaseIterable, Sendable {
    /// 伸懒腰: arms up beside the head and a big stretch, for an idle moment.
    case stretch
    /// 打瞌睡: the head nods off, then jerks awake.
    case doze
    /// 踢腿热身: knee lifts and a little bounce.
    case warmup
    /// 加油: fist pumps beside the head.
    case pump
    /// 名场面: strikes a pose, no spin.
    case pose
    /// 笑死: laughs and bends over.
    case laugh
    /// 被戳: jumps in surprise, then looks around.
    case poked
    /// 放纵餐: pats a full belly.
    case fullbelly
    /// 撞头庆祝: leans in for a head bump.
    case bump
    /// 打招呼: hops with both arms flung up, a big "hi!" (as designed, not a side-to-side wave).
    case wave
}

extension PlaceholderCharacter {
    /// How far past the canvas a move may reach, in canvas points: leaning, kicking and bending
    /// over go up to this far to either side, and a startled jump this far above. A screen that
    /// plays moves leaves that much room around the figure (or draws it with a `crop` that wide).
    public static let moveReachSideways = 40.0
    public static let moveReachAbove = 12.0

    /// `move` at `persona`'s tempo (`accentTempo`): a deadpan character stretches slowly.
    public static func clip(for move: Move, persona: Persona) throws(AvatarError) -> Clip {
        try Clip.decode(file("moves/\(move.rawValue).json")).atTempo(persona.accentTempo)
    }
}
