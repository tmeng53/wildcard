import Foundation

/// One check-in: 练了, 健康餐, 坦白放纵餐 or 今日免责声明. This is the shape the app
/// stores and the backend receives; the rules (how many a day, which conflict,
/// weekly counts, deleting) live in the `CheckIn` package, not here.
public struct CheckIn: Hashable, Sendable, Codable {
    /// The only wire `version` this build writes and reads.
    public static let currentVersion = 1

    public let id: CheckInID
    public let member: MemberID
    /// The member's local day the check-in counts for.
    public let day: LocalDay
    /// When it was made, for ordering on the track. Not used to pick the day.
    public let createdAt: Timestamp
    /// The squads it was sent to. Squads not listed see the member as not checked in.
    public let audience: Audience
    public let entry: Entry

    public init(
        id: CheckInID, member: MemberID, day: LocalDay, createdAt: Timestamp, audience: Audience, entry: Entry
    ) {
        self.id = id
        self.member = member
        self.day = day
        self.createdAt = createdAt
        self.audience = audience
        self.entry = entry
    }

    public enum Entry: Hashable, Sendable {
        /// 练了
        case trained(Training)
        /// 健康餐: counts toward the week's healthy meals.
        case healthyMeal(Meal)
        /// 坦白放纵餐: shown as a confession, never counts toward anything.
        case cheatMeal(Meal)
        /// 今日免责声明: a rest day with the member's excuse.
        case disclaimer(Disclaimer)
    }

    private enum CodingKeys: String, CodingKey {
        case version, id, member, day, createdAt, audience, kind, training, meal, disclaimer
    }

    private enum Kind: String, Codable {
        case trained, healthyMeal, cheatMeal, disclaimer

        var payloadKey: CodingKeys {
            switch self {
            case .trained: .training
            case .healthyMeal, .cheatMeal: .meal
            case .disclaimer: .disclaimer
            }
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decode(Int.self, forKey: .version)
        guard version == Self.currentVersion else { throw ContractsError.unsupportedVersion(version) }
        id = try container.decode(CheckInID.self, forKey: .id)
        member = try container.decode(MemberID.self, forKey: .member)
        day = try container.decode(LocalDay.self, forKey: .day)
        createdAt = try container.decode(Timestamp.self, forKey: .createdAt)
        audience = try container.decode(Audience.self, forKey: .audience)
        let kind = try container.decode(Kind.self, forKey: .kind)
        let payloads: [CodingKeys] = [.training, .meal, .disclaimer].filter(container.contains)
        guard payloads == [kind.payloadKey] else { throw ContractsError.payloadMismatch(kind.rawValue) }
        entry =
            switch kind {
            case .trained: .trained(try container.decode(Training.self, forKey: .training))
            case .healthyMeal: .healthyMeal(try container.decode(Meal.self, forKey: .meal))
            case .cheatMeal: .cheatMeal(try container.decode(Meal.self, forKey: .meal))
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
        try container.encode(audience, forKey: .audience)
        switch entry {
        case .trained(let training):
            try container.encode(Kind.trained, forKey: .kind)
            try container.encode(training, forKey: .training)
        case .healthyMeal(let meal):
            try container.encode(Kind.healthyMeal, forKey: .kind)
            try container.encode(meal, forKey: .meal)
        case .cheatMeal(let meal):
            try container.encode(Kind.cheatMeal, forKey: .kind)
            try container.encode(meal, forKey: .meal)
        case .disclaimer(let disclaimer):
            try container.encode(Kind.disclaimer, forKey: .kind)
            try container.encode(disclaimer, forKey: .disclaimer)
        }
    }
}

/// 练了: what was trained and for how long, with optional photos and a line.
public struct Training: Hashable, Sendable, Codable {
    public static let minutesRange = 1...600

    public let activity: Activity
    public let minutes: Int
    public let photos: Photos?
    public let caption: Caption?

    public init(
        activity: Activity, minutes: Int, photos: Photos? = nil, caption: Caption? = nil
    ) throws(ContractsError) {
        guard Self.minutesRange.contains(minutes) else { throw .minutesOutOfRange(minutes) }
        self.activity = activity
        self.minutes = minutes
        self.photos = photos
        self.caption = caption
    }

    private enum CodingKeys: String, CodingKey { case sport, customSport, minutes, photos, caption }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard let activity = try container.decodeActivityIfPresent(sport: .sport, custom: .customSport) else {
            throw DecodingError.keyNotFound(
                CodingKeys.sport, .init(codingPath: container.codingPath, debugDescription: "练了 needs a sport"))
        }
        try self.init(
            activity: activity,
            minutes: try container.decode(Int.self, forKey: .minutes),
            photos: try container.decodeIfPresent(Photos.self, forKey: .photos),
            caption: try container.decodeIfPresent(Caption.self, forKey: .caption)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeActivity(activity, sport: .sport, custom: .customSport)
        try container.encode(minutes, forKey: .minutes)
        try container.encodeIfPresent(photos, forKey: .photos)
        try container.encodeIfPresent(caption, forKey: .caption)
    }
}

/// A 健康餐 or 坦白放纵餐: which meal, with optional photos and a line. No calories or
/// macros, ever, in v1.
public struct Meal: Hashable, Sendable, Codable {
    public enum Slot: String, CaseIterable, Hashable, Sendable, Codable {
        case breakfast, lunch, dinner, snack
    }

    public let slot: Slot
    public let photos: Photos?
    public let caption: Caption?

    public init(slot: Slot, photos: Photos? = nil, caption: Caption? = nil) {
        self.slot = slot
        self.photos = photos
        self.caption = caption
    }
}

/// 今日免责声明: the member's one-line excuse for resting today.
public struct Disclaimer: Hashable, Sendable, Codable {
    /// Characters, counted as people see them (a Chinese character or emoji is one).
    public static let maxLength = 80

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

/// The optional one line under a 练了 or meal photo.
public struct Caption: Hashable, Sendable, Codable {
    /// Characters, counted as people see them.
    public static let maxLength = 40

    public let text: String

    public init(_ text: String) throws(ContractsError) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.contains(where: \.isNewline) else { throw .multilineCaption }
        guard (1...Self.maxLength).contains(trimmed.count) else { throw .captionLength(trimmed.count) }
        self.text = trimmed
    }

    public init(from decoder: Decoder) throws {
        try self.init(try decoder.singleValueContainer().decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(text)
    }
}

/// The squads a check-in goes to: at least one, at most `maxSquads`, no repeats.
public struct Audience: Hashable, Sendable, Codable {
    /// A member is in at most this many squads.
    public static let maxSquads = 3

    /// In the order the member picked them.
    public let squads: [SquadID]

    public init(_ squads: [SquadID]) throws(ContractsError) {
        guard (1...Self.maxSquads).contains(squads.count) else { throw .audienceSize(squads.count) }
        guard Set(squads).count == squads.count else { throw .repeatedSquad }
        self.squads = squads
    }

    public init(from decoder: Decoder) throws {
        try self.init(try decoder.singleValueContainer().decode([SquadID].self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(squads)
    }
}

/// A check-in's photos: one to `maxCount`, no repeats, in the order the member set.
/// The first is the cover, the one the feed and 战报 show. On the wire, an array.
public struct Photos: Hashable, Sendable, Codable {
    public static let maxCount = 3

    public let all: [PhotoRef]

    public var cover: PhotoRef { all[0] }

    public init(_ photos: [PhotoRef]) throws(ContractsError) {
        guard (1...Self.maxCount).contains(photos.count) else { throw .photoCount(photos.count) }
        guard Set(photos).count == photos.count else { throw .repeatedPhoto }
        all = photos
    }

    /// For a reordering of photos already checked, which keeps count and distinctness.
    private init(reordering photos: [PhotoRef]) { all = photos }

    /// The same photos with `photo` moved to the front as the cover; nil if it isn't one of them.
    public func withCover(_ photo: PhotoRef) -> Photos? {
        guard let index = all.firstIndex(of: photo) else { return nil }
        var reordered = all
        reordered.insert(reordered.remove(at: index), at: 0)
        return Photos(reordering: reordered)
    }

    public init(from decoder: Decoder) throws {
        try self.init(try decoder.singleValueContainer().decode([PhotoRef].self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(all)
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
