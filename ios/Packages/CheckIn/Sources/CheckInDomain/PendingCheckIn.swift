import Contracts
import Foundation

/// A check-in made on the phone and not yet saved by the server. Its id, day and time are fixed
/// when the member posts, so sending it again, however late, saves the same check-in once.
public struct PendingCheckIn: Hashable, Sendable, Identifiable {
    public let id: CheckInID
    public let member: MemberID
    /// The day it counts for: `postedDay`, or one of the days before it (补打卡).
    public let day: LocalDay
    /// The member's day when they made it.
    public let postedDay: LocalDay
    public let createdAt: Timestamp
    public let audience: Audience
    /// 发布到动态: off only records it.
    public let inFeed: Bool
    public let draft: CheckInDraft
    /// The draft's photos already uploaded, by `PreparedPhoto.id`, so a retry doesn't upload
    /// them again.
    public var uploaded: [UUID: PhotoRef]

    public init(
        id: CheckInID, member: MemberID, day: LocalDay, postedDay: LocalDay? = nil, createdAt: Timestamp,
        audience: Audience, inFeed: Bool = true, draft: CheckInDraft, uploaded: [UUID: PhotoRef] = [:]
    ) {
        self.id = id
        self.member = member
        self.day = day
        self.postedDay = postedDay ?? day
        self.createdAt = createdAt
        self.audience = audience
        self.inFeed = inFeed
        self.draft = draft
        self.uploaded = uploaded
    }

    /// The draft's photos still to upload, in order.
    public var photosToUpload: [PreparedPhoto] {
        draft.photos.filter { uploaded[$0.id] == nil }
    }

    /// The check-in to save, once every photo is uploaded; nil before.
    public func checkIn() throws(CheckInError) -> CheckIn? {
        let uploads = draft.photos.compactMap { photo in uploaded[photo.id].map { (ref: $0, size: photo.size) } }
        guard uploads.count == draft.photos.count else { return nil }
        do {
            let refs = try uploads.map { upload throws(ContractsError) in
                try PhotoRef(path: upload.ref.path, size: upload.size)
            }
            let photos = refs.isEmpty ? nil : try Photos(refs)
            let entry: CheckIn.Entry =
                switch draft {
                case .trained(let activity, let minutes, let body):
                    .trained(
                        Training(
                            activity: activity, minutes: minutes, startTime: body.startTime, photos: photos,
                            caption: try body.caption.map(Caption.init), workout: body.workout, place: body.place))
                case .healthyMeal(let body):
                    .healthyMeal(
                        Meal(
                            photos: photos, caption: try body.caption.map(Caption.init), place: body.place,
                            rating: body.rating))
                case .cheatMeal(let body):
                    .cheatMeal(
                        Meal(
                            photos: photos, caption: try body.caption.map(Caption.init), place: body.place,
                            rating: body.rating))
                case .disclaimer(let disclaimer, _):
                    .disclaimer(try Disclaimer(disclaimer.text, restDay: disclaimer.restDay, photos: photos))
                }
            return CheckIn(
                id: id, member: member, day: day, postedDay: postedDay, createdAt: createdAt, audience: audience,
                inFeed: inFeed, entry: entry)
        } catch {
            // `PostBody` and `Disclaimer` already keep to these rules.
            throw .refused
        }
    }
}
