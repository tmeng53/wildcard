import Foundation

/// One check-in: 练了, 吃得干净 or 今日免责声明. This is the shape the app stores
/// and the backend receives; the rules about how many a day and streaks live in
/// the `CheckIn` package, not here.
public struct CheckIn: Hashable, Sendable, Codable {
    /// The only wire `version` this build writes and reads.
    public static let currentVersion = 1

    public let id: CheckInID
    public let member: MemberID
    /// The member's local day the check-in counts for.
    public let day: LocalDay
    /// When it was made, for ordering on the track. Not used to pick the day.
    public let createdAt: Date
    public let entry: Entry

    public init(id: CheckInID, member: MemberID, day: LocalDay, createdAt: Date, entry: Entry) {
        self.id = id
        self.member = member
        self.day = day
        self.createdAt = createdAt
        self.entry = entry
    }

    public enum Entry: Hashable, Sendable {
        /// 练了
        case trained(Training)
        /// 吃得干净
        case ateClean(Meal)
        /// 今日免责声明: a rest day with the member's excuse.
        case disclaimer(Disclaimer)
    }

    private enum CodingKeys: String, CodingKey {
        case version, id, member, day, createdAt, kind, training, meal, disclaimer
    }

    private enum Kind: String, Codable {
        case trained, ateClean, disclaimer
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decode(Int.self, forKey: .version)
        guard version == Self.currentVersion else { throw ContractsError.unsupportedVersion(version) }
        id = try container.decode(CheckInID.self, forKey: .id)
        member = try container.decode(MemberID.self, forKey: .member)
        day = try container.decode(LocalDay.self, forKey: .day)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        entry = switch try container.decode(Kind.self, forKey: .kind) {
        case .trained: .trained(try container.decode(Training.self, forKey: .training))
        case .ateClean: .ateClean(try container.decode(Meal.self, forKey: .meal))
        case .disclaimer: .disclaimer(try container.decode(Disclaimer.self, forKey: .disclaimer))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.currentVersion, forKey: .version)
        try container.encode(id, forKey: .id)
        try container.encode(member, forKey: .member)
        try container.encode(day, forKey: .day)
        try container.encode(createdAt, forKey: .createdAt)
        switch entry {
        case .trained(let training):
            try container.encode(Kind.trained, forKey: .kind)
            try container.encode(training, forKey: .training)
        case .ateClean(let meal):
            try container.encode(Kind.ateClean, forKey: .kind)
            try container.encode(meal, forKey: .meal)
        case .disclaimer(let disclaimer):
            try container.encode(Kind.disclaimer, forKey: .kind)
            try container.encode(disclaimer, forKey: .disclaimer)
        }
    }
}

/// A sport a member trains. New sports are a contract change.
public enum Sport: String, CaseIterable, Hashable, Sendable, Codable {
    case run, strength, yoga, pilates, swim, cycle, ball, climb, hike, dance, other
}

/// 练了: what was trained and for how long, with an optional photo.
public struct Training: Hashable, Sendable, Codable {
    public static let minutesRange = 1...600

    public let sport: Sport
    public let minutes: Int
    public let photo: PhotoRef?

    public init(sport: Sport, minutes: Int, photo: PhotoRef? = nil) throws(ContractsError) {
        guard Self.minutesRange.contains(minutes) else { throw .minutesOutOfRange(minutes) }
        self.sport = sport
        self.minutes = minutes
        self.photo = photo
    }

    private enum CodingKeys: String, CodingKey { case sport, minutes, photo }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            sport: try container.decode(Sport.self, forKey: .sport),
            minutes: try container.decode(Int.self, forKey: .minutes),
            photo: try container.decodeIfPresent(PhotoRef.self, forKey: .photo)
        )
    }
}

/// 吃得干净: which meal, with an optional photo. No calories or macros, ever, in v1.
public struct Meal: Hashable, Sendable, Codable {
    public enum Slot: String, CaseIterable, Hashable, Sendable, Codable {
        case breakfast, lunch, dinner, snack
    }

    public let slot: Slot
    public let photo: PhotoRef?

    public init(slot: Slot, photo: PhotoRef? = nil) {
        self.slot = slot
        self.photo = photo
    }
}

/// 今日免责声明: the member's one-line excuse for resting today.
public struct Disclaimer: Hashable, Sendable, Codable {
    /// Characters, counted as people see them (a Chinese character or emoji is one).
    public static let maxLength = 40

    public let text: String

    public init(_ text: String) throws(ContractsError) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...Self.maxLength).contains(trimmed.count) else { throw .disclaimerLength(trimmed.count) }
        self.text = trimmed
    }

    private enum CodingKeys: String, CodingKey { case text }

    public init(from decoder: Decoder) throws {
        try self.init(try decoder.container(keyedBy: CodingKeys.self).decode(String.self, forKey: .text))
    }
}

/// Where a check-in photo lives in storage, relative to the photos bucket.
public struct PhotoRef: Hashable, Sendable, Codable {
    public let path: String

    public init(path: String) throws(ContractsError) {
        guard !path.isEmpty else { throw .emptyPhotoPath }
        self.path = path
    }

    private enum CodingKeys: String, CodingKey { case path }

    public init(from decoder: Decoder) throws {
        try self.init(path: try decoder.container(keyedBy: CodingKeys.self).decode(String.self, forKey: .path))
    }
}
