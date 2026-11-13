import Contracts
import Foundation

/// A photo on a post being written or edited: one already saved on it, or one just picked.
public enum ComposedPhoto: Hashable, Sendable, Identifiable {
    case saved(PhotoRef)
    case new(PreparedPhoto)

    public var id: String {
        switch self {
        case .saved(let photo): "saved:\(photo.path)"
        case .new(let photo): "new:\(photo.id.uuidString)"
        }
    }

    /// The photos of a saved post, the cover first.
    public static func of(_ checkIn: CheckIn) -> [ComposedPhoto] {
        (checkIn.entry.photos?.all ?? []).map(ComposedPhoto.saved)
    }
}

extension CheckIn.Entry {
    /// The entry's photos, the cover first; nil when it has none.
    public var photos: Photos? {
        switch self {
        case .trained(let training): training.photos
        case .healthyMeal(let meal), .cheatMeal(let meal): meal.photos
        case .disclaimer(let disclaimer): disclaimer.photos
        }
    }

    /// The line the member wrote: a caption, or a 请假条's text.
    public var line: String? {
        switch self {
        case .trained(let training): training.caption?.text
        case .healthyMeal(let meal), .cheatMeal(let meal): meal.caption?.text
        case .disclaimer(let disclaimer): disclaimer.text
        }
    }

    /// The place the member tagged; a 请假条 never has one.
    public var place: Place? {
        switch self {
        case .trained(let training): training.place
        case .healthyMeal(let meal), .cheatMeal(let meal): meal.place
        case .disclaimer: nil
        }
    }
}

/// A saved post as the member edits it: its own fields and photos, all of them. The kind, the
/// day, the time and the squads it went to stay as posted.
public struct PostEdit: Hashable, Sendable {
    public let original: CheckIn
    /// The sport and minutes, for a 练了; ignored for the other kinds.
    public let activity: Activity
    public let minutes: WorkoutMinutes?
    /// When a 练了 started, if the member picked it.
    public let startTime: StartTime?
    /// The caption, or a 请假条's text.
    public let line: String
    /// At most `Photos.maxCount`, the cover first.
    public let photos: [ComposedPhoto]
    /// A 训练's workout as it is to be: numbers struck out since are gone, and its tile placed
    /// among the photos or taken off.
    public let workout: Workout?
    /// The place as it is to be: nil takes a tagged one off. Ignored for a 请假条.
    public let place: Place?
    /// A meal's 健康 and 好吃 as they are to be; ignored for the other kinds. A rating, once
    /// given, is only changed, never taken off.
    public let rating: MealRating?

    public init(
        original: CheckIn, activity: Activity, minutes: WorkoutMinutes?, line: String, photos: [ComposedPhoto],
        workout: Workout? = nil, startTime: StartTime? = nil, place: Place? = nil, rating: MealRating? = nil
    ) {
        self.original = original
        self.activity = activity
        self.minutes = minutes
        self.startTime = startTime
        self.line = line
        self.photos = Array(photos.prefix(Photos.maxCount))
        self.workout = workout
        self.place = place
        self.rating = rating
    }

    /// The photos still to upload, in order.
    public var newPhotos: [PreparedPhoto] {
        photos.compactMap { if case .new(let photo) = $0 { photo } else { nil } }
    }

    /// The check-in as edited, once each new photo is uploaded (`uploaded`, by
    /// `PreparedPhoto.id`). Throws `.refused` for one that breaks a rule `Contracts` checks.
    public func checkIn(uploaded: [UUID: PhotoRef]) throws(CheckInError) -> CheckIn {
        do {
            let refs = try photos.map { photo throws(ContractsError) -> PhotoRef in
                switch photo {
                case .saved(let saved): return saved
                case .new(let new):
                    guard let ref = uploaded[new.id] else { throw .photoCount(0) }
                    return try PhotoRef(path: ref.path, size: new.size)
                }
            }
            let photos = refs.isEmpty ? nil : try Photos(refs)
            let fitted = PostBody(photos: [], caption: line).caption
            let caption = try fitted.map(Caption.init)
            let entry: CheckIn.Entry =
                switch original.entry {
                case .trained:
                    .trained(
                        Training(
                            activity: activity, minutes: minutes, startTime: startTime, photos: photos,
                            caption: caption, workout: workout, place: place))
                case .healthyMeal:
                    .healthyMeal(Meal(photos: photos, caption: caption, place: place, rating: rating))
                case .cheatMeal: .cheatMeal(Meal(photos: photos, caption: caption, place: place, rating: rating))
                case .disclaimer(let old): .disclaimer(try Disclaimer(line, restDay: old.restDay, photos: photos))
                }
            return CheckIn(
                id: original.id, member: original.member, day: original.day, postedDay: original.postedDay,
                createdAt: original.createdAt,
                audience: original.audience, inFeed: original.inFeed, entry: entry)
        } catch {
            throw .refused
        }
    }
}
