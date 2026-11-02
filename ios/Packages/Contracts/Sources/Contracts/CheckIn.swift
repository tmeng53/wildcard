import Foundation

/// One check-in: 练了, 健康餐, 坦白放纵餐 or 今日请假条, as the app holds it. The wire shape
/// comes from the API's OpenAPI document (`APIContract` maps between the two); the rules (how
/// many a day, which conflict, weekly counts, deleting) live in the `CheckIn` package.
public struct CheckIn: Hashable, Sendable {
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
        /// 今日请假条: a rest day with the member's excuse.
        case disclaimer(Disclaimer)
    }
}

/// 练了: what was trained, with optional minutes, photos and a line.
public struct Training: Hashable, Sendable {
    public let activity: Activity
    public let minutes: WorkoutMinutes?
    public let photos: Photos?
    public let caption: Caption?

    public init(activity: Activity, minutes: WorkoutMinutes? = nil, photos: Photos? = nil, caption: Caption? = nil) {
        self.activity = activity
        self.minutes = minutes
        self.photos = photos
        self.caption = caption
    }
}

/// How long a 练了 took, in whole minutes. Never asked for: a 练了 without it is just as much a 练了.
public struct WorkoutMinutes: Hashable, Sendable {
    /// The API's range; `APIContract`'s tests fail when the two differ.
    public static let range = 1...600

    public let value: Int

    public init(_ value: Int) throws(ContractsError) {
        guard Self.range.contains(value) else { throw .workoutMinutes(value) }
        self.value = value
    }
}

/// A 健康餐 or 坦白放纵餐, with optional photos and a line. No meal type, calories or macros,
/// ever, in v1.
public struct Meal: Hashable, Sendable {
    public let photos: Photos?
    public let caption: Caption?

    public init(photos: Photos? = nil, caption: Caption? = nil) {
        self.photos = photos
        self.caption = caption
    }
}

/// 今日请假条: the member's excuse for resting today, at most `maxLength` characters, with
/// optional photos. The text may span lines.
public struct Disclaimer: Hashable, Sendable {
    /// Characters, counted as people see them (a Chinese character or emoji is one). The API's
    /// limit; `APIContract`'s tests fail when the two differ.
    public static let maxLength = 80

    public let text: String
    public let photos: Photos?

    public init(_ text: String, photos: Photos? = nil) throws(ContractsError) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...Self.maxLength).contains(trimmed.count) else { throw .disclaimerLength(trimmed.count) }
        self.text = trimmed
        self.photos = photos
    }
}

/// The optional one line under a 练了 or meal photo.
public struct Caption: Hashable, Sendable {
    /// Characters, counted as people see them. The API's limit; `APIContract`'s tests fail
    /// when the two differ.
    public static let maxLength = 60

    public let text: String

    public init(_ text: String) throws(ContractsError) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.contains(where: \.isNewline) else { throw .multilineCaption }
        guard (1...Self.maxLength).contains(trimmed.count) else { throw .captionLength(trimmed.count) }
        self.text = trimmed
    }
}

/// The squads a check-in is shared to: at most `maxSquads`, no repeats. A post is the
/// member's own; one shared to no squad only they see.
public struct Audience: Hashable, Sendable {
    /// A member is in at most this many squads.
    public static let maxSquads = 3

    /// In the order the member picked them.
    public let squads: [SquadID]

    public init(_ squads: [SquadID]) throws(ContractsError) {
        guard squads.count <= Self.maxSquads else { throw .audienceSize(squads.count) }
        guard Set(squads).count == squads.count else { throw .repeatedSquad }
        self.squads = squads
    }
}

/// A check-in's photos: one to `maxCount`, no repeats, in the order the member set.
/// The first is the cover, the one the feed and 战报 show.
public struct Photos: Hashable, Sendable {
    public static let maxCount = 3

    public let all: [PhotoRef]

    public var cover: PhotoRef { all[0] }

    public init(_ photos: [PhotoRef]) throws(ContractsError) {
        guard (1...Self.maxCount).contains(photos.count) else { throw .photoCount(photos.count) }
        guard Set(photos.map(\.path)).count == photos.count else { throw .repeatedPhoto }
        all = photos
    }

    /// For a reordering of photos already checked, which keeps count and distinctness.
    private init(reordering photos: [PhotoRef]) { all = photos }

    /// The same photos with `photo` moved to the front as the cover; nil if it isn't one of them.
    public func withCover(_ photo: PhotoRef) -> Photos? {
        guard let index = all.firstIndex(where: { $0.path == photo.path }) else { return nil }
        var reordered = all
        reordered.insert(reordered.remove(at: index), at: 0)
        return Photos(reordering: reordered)
    }
}

/// A check-in photo: its name in storage, as `POST /photo-uploads` gave it, its size, and on a
/// saved check-in the URL to view it. Two are the same photo when their paths are: the view URL
/// is signed afresh on every list.
public struct PhotoRef: Hashable, Sendable {
    public let path: String
    /// Its width and height in pixels, so the feed lays it out at its shape before it loads.
    /// Nil on photos saved before sizes were sent.
    public let size: PhotoSize?
    /// Where to `GET` the photo, on check-ins the API sent. It stops working after a while;
    /// listing again gives fresh ones. Nil on a check-in the app is about to send.
    public let viewURL: URL?

    public init(path: String, size: PhotoSize? = nil, viewURL: URL? = nil) throws(ContractsError) {
        guard !path.isEmpty else { throw .emptyPhotoPath }
        self.path = path
        self.size = size
        self.viewURL = viewURL
    }

    public static func == (lhs: PhotoRef, rhs: PhotoRef) -> Bool { lhs.path == rhs.path }

    public func hash(into hasher: inout Hasher) { hasher.combine(path) }
}

/// A photo's width and height in pixels, each within `sideRange`.
public struct PhotoSize: Hashable, Sendable {
    /// The API's bounds, well past the 1080 pixels the app uploads.
    public static let sideRange = 1...10_000

    public let width: Int
    public let height: Int

    public init(width: Int, height: Int) throws(ContractsError) {
        guard Self.sideRange.contains(width), Self.sideRange.contains(height) else {
            throw .photoSize(width: width, height: height)
        }
        self.width = width
        self.height = height
    }

    /// Width over height: above 1 is landscape, below 1 portrait.
    public var aspectRatio: Double { Double(width) / Double(height) }
}
