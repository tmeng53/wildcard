import Contracts
import Foundation

/// A photo ready to post: resized and compressed on the phone (`PhotoPreparation`), so upload
/// and storage stay small. Its id tells photos apart, on screen and in the outbox, which
/// records the ones already uploaded.
public struct PreparedPhoto: Hashable, Sendable, Identifiable {
    public let id: UUID
    /// JPEG, at most `PhotoUploadSize` (1080 px on the short edge, 1920 on the long).
    public let jpeg: Data
    /// The JPEG's size in pixels, sent with the check-in so the feed shows the photo at its
    /// shape. Nil only on a post kept from before sizes were sent.
    public let size: PhotoSize?

    public init(id: UUID, jpeg: Data, size: PhotoSize?) {
        self.id = id
        self.jpeg = jpeg
        self.size = size
    }
}

/// What a 训练 or a meal carries: up to three photos, the first the cover, a line, and for a 训练
/// posted from Health its workout as posted (only the numbers kept, its tile placed among the
/// photos). A meal never has a workout.
public struct PostBody: Hashable, Sendable {
    public let photos: [PreparedPhoto]
    public let caption: String?
    public let workout: Workout?

    /// Keeps at most `Photos.maxCount` photos, and the caption trimmed, on one line and cut to
    /// `Caption.maxLength`; an empty caption is none.
    public init(photos: [PreparedPhoto], caption: String, workout: Workout? = nil) {
        self.photos = Array(photos.prefix(Photos.maxCount))
        let line = Self.fitCaption(caption).trimmingCharacters(in: .whitespaces)
        self.caption = line.isEmpty ? nil : line
        self.workout = workout
    }

    public var cover: PreparedPhoto? { photos.first }

    /// What the caption field keeps while typing: no line breaks, at most `Caption.maxLength`.
    public static func fitCaption(_ text: String) -> String {
        String(text.filter { !$0.isNewline }.prefix(Caption.maxLength))
    }
}

/// A check-in as the compose step and the 请假条 card hand it over. `TodayStore` adds the
/// id, the member, the day, the time and the squad.
public enum CheckInDraft: Hashable, Sendable {
    /// 练了: the sport, how many minutes if the member said, and the post.
    case trained(Activity, WorkoutMinutes?, PostBody)
    case healthyMeal(PostBody)
    case cheatMeal(PostBody)
    case disclaimer(Disclaimer)

    /// The workout a 训练 was posted from; nil for one made by hand and for the other kinds.
    public var workout: Workout? {
        if case .trained(_, _, let body) = self { body.workout } else { nil }
    }

    /// The photos to upload before the check-in is saved, the cover first.
    public var photos: [PreparedPhoto] {
        switch self {
        case .trained(_, _, let body), .healthyMeal(let body), .cheatMeal(let body): body.photos
        case .disclaimer: []
        }
    }
}
