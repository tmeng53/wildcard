import Foundation

/// A coach's id, such as `xiaohun`. Never changes.
public struct CoachID: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral {
    public let rawValue: String

    /// Nil for anything that can't be a coach's id: 2 to 40 lowercase letters, digits and
    /// dashes, starting with a letter.
    public init?(rawValue: String) {
        let scalars = rawValue.unicodeScalars
        guard (2...40).contains(scalars.count), let first = scalars.first, ("a"..."z").contains(first),
            scalars.allSatisfy({ ("a"..."z").contains($0) || ("0"..."9").contains($0) || $0 == "-" })
        else { return nil }
        self.rawValue = rawValue
    }

    /// For the samples' own coaches.
    public init(stringLiteral id: String) { rawValue = id }
}

/// A coach as 教练市场 and its 简历 show it: the same coach for every squad. Its words come from
/// the API, so a new coach needs no app release.
public struct Coach: Hashable, Sendable, Identifiable {
    public let id: CoachID
    public let name: String
    /// Its 头衔, next to its name, such as 混混教练.
    public let title: String
    public let catchphrase: String
    /// 履历.
    public let background: String
    /// The number in 执教.
    public let yearsCoaching: Int
    /// What 执教 says after the years, such as 热情满格.
    public let experience: String
    /// 风格.
    public let style: String
    public let tags: [String]
    /// 期望待遇.
    public let pay: String

    public init(
        id: CoachID, name: String, title: String, catchphrase: String, background: String, yearsCoaching: Int,
        experience: String, style: String, tags: [String], pay: String
    ) {
        (self.id, self.name, self.title, self.catchphrase) = (id, name, title, catchphrase)
        (self.background, self.yearsCoaching, self.experience) = (background, yearsCoaching, experience)
        (self.style, self.tags, self.pay) = (style, tags, pay)
    }
}

/// A squad's coach, as its members see it in 小队设置.
public struct SquadCoach: Hashable, Sendable {
    /// The coach the squad hired, and when.
    public struct Hire: Hashable, Sendable {
        public let coach: Coach
        public let since: Date

        public init(coach: Coach, since: Date) {
            self.coach = coach
            self.since = since
        }
    }

    /// Nil while the squad has no coach.
    public let hire: Hire?
    /// The member is the captain, the only one who hires, changes and fires the coach.
    public let canHire: Bool

    public init(hire: Hire?, canHire: Bool) {
        self.hire = hire
        self.canHire = canHire
    }
}
