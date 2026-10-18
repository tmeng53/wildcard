import CheckInDomain
import Contracts
import DesignSystem
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
    /// Characters, counted as people see them. The API allows 60 (Check-in API, PR #25).
    public static let captionLimit = 60

    public let photos: [PreparedPhoto]
    public let caption: String?

    /// Keeps at most `Photos.maxCount` photos, and the caption trimmed, on one line and cut to
    /// `captionLimit`; an empty caption is none.
    public init(photos: [PreparedPhoto], caption: String) {
        self.photos = Array(photos.prefix(Photos.maxCount))
        let line = Self.fitCaption(caption).trimmingCharacters(in: .whitespaces)
        self.caption = line.isEmpty ? nil : line
    }

    public var cover: PreparedPhoto? { photos.first }

    /// What the caption field keeps while typing: no line breaks, at most `captionLimit`.
    static func fitCaption(_ text: String) -> String {
        String(text.filter { !$0.isNewline }.prefix(captionLimit))
    }
}

/// A check-in as the compose step and the 免责声明 card hand it over. The service adds the
/// member, the day, the time and the squads.
public enum CheckInDraft: Hashable, Sendable {
    case trained(Activity, PostBody)
    case healthyMeal(PostBody)
    case cheatMeal(PostBody)
    case disclaimer(Disclaimer)

    var meaning: Meaning {
        switch self {
        case .trained: .trained
        case .healthyMeal: .fresh
        case .cheatMeal: .indulgence
        case .disclaimer: .disclaimer
        }
    }
}
