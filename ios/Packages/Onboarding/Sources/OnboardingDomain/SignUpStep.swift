/// Where a new member is in sign-up, in order. The open screen and 上场 frame the four task
/// steps the header counts. Whoever made their squad then picks where it trains, and drops onto
/// it rather than playing 上场.
public enum SignUpStep: Int, CaseIterable, Comparable, Sendable {
    /// The open screen: the squad of characters and 通过 Apple 继续.
    case welcome
    /// 角色和昵称: the character editor.
    case character
    /// 你的小队: join by invite code or make one.
    case squad
    /// 平时练什么？
    case sports
    /// 一周练几天？, on the week's poster.
    case week
    /// 这周在哪练？: only for whoever made the squad. Five cartons; the one picked opens, and the
    /// member drops onto it at home (Tracy, 2026-10-23: 「selecting a new scene always do the
    /// open and drop」). Not counted in the header.
    case scene
    /// 上场: the entrance into a squad joined, then home.
    case entrance

    /// The steps the header counts, 「第 1 步，共 4 步」 to 「第 4 步，共 4 步」.
    public static let counted: [SignUpStep] = [.character, .squad, .sports, .week]

    /// This step's number in the header, or nil for the open screen, 这周在哪练？ and 上场.
    public var number: Int? {
        Self.counted.firstIndex(of: self).map { $0 + 1 }
    }

    public var next: SignUpStep? { SignUpStep(rawValue: rawValue + 1) }

    /// Where 一周练几天？ goes: whoever made the squad picks its scene; whoever joined one goes
    /// straight to 上场 and the squad's welcome (Tracy, 2026-10-23: 「joining a new team should
    /// always do the join and teammates welcome effect」).
    public static func afterWeek(madeTheSquad: Bool) -> SignUpStep {
        madeTheSquad ? .scene : .entrance
    }

    /// Where back goes: the open screen signs out, so there is no back from it, and none from
    /// 上场, which the squad has already seen.
    public var previous: SignUpStep? {
        self == .entrance ? nil : SignUpStep(rawValue: rawValue - 1)
    }

    public static func < (lhs: SignUpStep, rhs: SignUpStep) -> Bool { lhs.rawValue < rhs.rawValue }
}
