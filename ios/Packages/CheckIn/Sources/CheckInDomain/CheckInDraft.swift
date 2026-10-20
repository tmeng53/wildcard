import Contracts
import Foundation

/// A photo ready to post: resized and compressed on the phone (`PhotoPreparation`), so upload
/// and storage stay small. Its id only tells photos apart on screen.
public struct PreparedPhoto: Hashable, Sendable, Identifiable {
    public let id: UUID
    /// JPEG, at most `PhotoPreparation.maxPixelSize` on the long edge.
    public let jpeg: Data

    public init(id: UUID = UUID(), jpeg: Data) {
        self.id = id
        self.jpeg = jpeg
    }
}

/// What a 练了 or a meal carries: up to three photos, the first the cover, and a line.
public struct PostBody: Hashable, Sendable {
    public let photos: [PreparedPhoto]
    public let caption: String?

    /// Keeps at most `Photos.maxCount` photos, and the caption trimmed, on one line and cut to
    /// `Caption.maxLength`; an empty caption is none.
    public init(photos: [PreparedPhoto], caption: String) {
        self.photos = Array(photos.prefix(Photos.maxCount))
        let line = Self.fitCaption(caption).trimmingCharacters(in: .whitespaces)
        self.caption = line.isEmpty ? nil : line
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
    case trained(Activity, PostBody)
    case healthyMeal(PostBody)
    case cheatMeal(PostBody)
    case disclaimer(Disclaimer)

    /// The photos to upload before the check-in is saved, the cover first.
    public var photos: [PreparedPhoto] {
        switch self {
        case .trained(_, let body), .healthyMeal(let body), .cheatMeal(let body): body.photos
        case .disclaimer: []
        }
    }
}
