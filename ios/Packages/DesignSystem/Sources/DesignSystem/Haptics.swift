/// The app's haptics: one named feel per moment, each paired with the motion it lands on. A
/// moment gets one meaningful tap, never a buzz, and only the moments listed here get one, so
/// the phone stays quiet the rest of the time. Screens play them by name, never their own.
public enum Haptic: String, CaseIterable, Sendable {
    /// Picking an option, a swatch, a tab or a style: a light tick, on `Motion.change`.
    case pick
    /// Something you asked for arrives: the check-in capsules opening, drafts landing. On
    /// `Motion.sheet`.
    case appear
    /// A tap that can't do anything right now, such as a check-in kind already used today: a
    /// soft knock with the shake.
    case refuse
    /// Each step while a status ring draws itself closed: a small, crisp tick.
    case tick
    /// The ring closing on a check-in: the one heavy hit, on `Motion.celebrate`.
    case checkIn
    /// The score turning over to its new count: a light tap after the celebration.
    case score
    /// The character landing on the scene after 上场: a medium thud.
    case land
    /// A teammate's reaction arriving on your check-in: a soft tap.
    case reaction
    /// A pat landing on a teammate (拍一拍): a short, light tap at the moment of contact.
    case poke
    /// A carton bursting open on a scene pick, as its flaps fly: one heavy hit, the reveal's only
    /// one.
    case unbox

    /// How many ticks a status ring plays while it draws itself closed.
    public static let ringTicks = 3
}
