import Foundation

/// A member's plan for one week: which days they train and which are rest days.
/// Planned rest days keep the training streak without a check-in. The rules
/// (locking days once they start, carrying last week's plan over) live in the
/// `CheckIn` package, not here.
public struct WeeklyPlan: Hashable, Sendable, Codable {
    /// The only wire `version` this build writes and reads.
    public static let currentVersion = 1

    public let member: MemberID
    /// The plan's first day. Its weekday is the member's chosen week start.
    public let weekStart: LocalDay
    /// Exactly seven days, `weekStart` first.
    public let days: [PlanDay]

    public init(member: MemberID, weekStart: LocalDay, days: [PlanDay]) throws(ContractsError) {
        guard days.count == 7 else { throw .planLength(days.count) }
        self.member = member
        self.weekStart = weekStart
        self.days = days
    }

    private enum CodingKeys: String, CodingKey { case version, member, weekStart, days }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decode(Int.self, forKey: .version)
        guard version == Self.currentVersion else { throw ContractsError.unsupportedVersion(version) }
        try self.init(
            member: try container.decode(MemberID.self, forKey: .member),
            weekStart: try container.decode(LocalDay.self, forKey: .weekStart),
            days: try container.decode([PlanDay].self, forKey: .days)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.currentVersion, forKey: .version)
        try container.encode(member, forKey: .member)
        try container.encode(weekStart, forKey: .weekStart)
        try container.encode(days, forKey: .days)
    }
}

/// One planned day: train (optionally naming the sport) or 休息.
public enum PlanDay: Hashable, Sendable, Codable {
    case train(Sport?)
    case rest

    private enum CodingKeys: String, CodingKey { case kind, sport }
    private enum Kind: String, Codable { case train, rest }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .train: self = .train(try container.decodeIfPresent(Sport.self, forKey: .sport))
        case .rest:
            guard !container.contains(.sport) else { throw ContractsError.payloadMismatch(Kind.rest.rawValue) }
            self = .rest
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .train(let sport):
            try container.encode(Kind.train, forKey: .kind)
            try container.encodeIfPresent(sport, forKey: .sport)
        case .rest:
            try container.encode(Kind.rest, forKey: .kind)
        }
    }
}
