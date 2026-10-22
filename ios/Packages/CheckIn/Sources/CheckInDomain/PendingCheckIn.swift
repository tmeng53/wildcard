import Contracts
import Foundation

/// A check-in made on the phone and not yet saved by the server. Its id, day and time are fixed
/// when the member posts, so sending it again, however late, saves the same check-in once.
public struct PendingCheckIn: Hashable, Sendable, Identifiable {
    public let id: CheckInID
    public let member: MemberID
    public let day: LocalDay
    public let createdAt: Timestamp
    public let audience: Audience
    public let draft: CheckInDraft
    /// The draft's photos already uploaded, by `PreparedPhoto.id`, so a retry doesn't upload
    /// them again.
    public var uploaded: [UUID: PhotoRef]

    public init(
        id: CheckInID, member: MemberID, day: LocalDay, createdAt: Timestamp, audience: Audience, draft: CheckInDraft,
        uploaded: [UUID: PhotoRef] = [:]
    ) {
        self.id = id
        self.member = member
        self.day = day
        self.createdAt = createdAt
        self.audience = audience
        self.draft = draft
        self.uploaded = uploaded
    }

    /// The draft's photos still to upload, in order.
    public var photosToUpload: [PreparedPhoto] {
        draft.photos.filter { uploaded[$0.id] == nil }
    }

    /// The check-in to save, once every photo is uploaded; nil before.
    public func checkIn() throws(CheckInError) -> CheckIn? {
        let refs = draft.photos.compactMap { uploaded[$0.id] }
        guard refs.count == draft.photos.count else { return nil }
        do {
            let photos = refs.isEmpty ? nil : try Photos(refs)
            let entry: CheckIn.Entry =
                switch draft {
                case .trained(let activity, let body):
                    .trained(Training(activity: activity, photos: photos, caption: try body.caption.map(Caption.init)))
                case .healthyMeal(let body):
                    .healthyMeal(Meal(photos: photos, caption: try body.caption.map(Caption.init)))
                case .cheatMeal(let body):
                    .cheatMeal(Meal(photos: photos, caption: try body.caption.map(Caption.init)))
                case .disclaimer(let disclaimer): .disclaimer(disclaimer)
                }
            return CheckIn(id: id, member: member, day: day, createdAt: createdAt, audience: audience, entry: entry)
        } catch {
            // `PostBody` and `Disclaimer` already keep to these rules.
            throw .refused
        }
    }
}
