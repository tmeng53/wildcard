import CheckInDomain
import Contracts
import Foundation

/// Check-ins waiting to go out, kept in files on the device so they survive the app closing:
/// `outbox.json` and each photo beside it. The member's: keep it in their `MemberFolders` folder.
public actor DeviceOutbox: Outbox {
    private let list: URL
    private let photos: URL

    /// - Parameter directory: where to keep them, such as Application Support.
    public init(directory: URL) {
        list = directory.appending(path: "outbox.json")
        photos = directory.appending(path: "outbox-photos", directoryHint: .isDirectory)
    }

    public func load() async -> [PendingCheckIn] {
        guard let data = try? Data(contentsOf: list), let kept = try? JSONDecoder().decode(Kept.self, from: data),
            kept.version == 1
        else { return [] }
        return kept.pending.compactMap { try? $0.pending(photos: photos) }
    }

    public func save(_ pending: [PendingCheckIn]) async {
        do {
            try FileManager.default.createDirectory(at: photos, withIntermediateDirectories: true)
            for post in pending {
                for photo in post.photosToUpload {
                    let file = photos.appending(path: "\(photo.id.uuidString).jpg")
                    if !FileManager.default.fileExists(atPath: file.path()) {
                        try DeviceJSON.write(photo.jpeg, to: file)
                    }
                }
            }
            try DeviceJSON.write(
                try JSONEncoder().encode(Kept(version: 1, pending: pending.map(Stored.init))), to: list)
            // Photos no post still needs to upload.
            let needed = Set(pending.flatMap(\.photosToUpload).map { "\($0.id.uuidString).jpg" })
            for name in (try? FileManager.default.contentsOfDirectory(atPath: photos.path())) ?? []
            where !needed.contains(name) {
                try? FileManager.default.removeItem(at: photos.appending(path: name))
            }
        } catch {
            // Kept in memory by the store; it goes out while the app stays open.
        }
    }

    /// Stored JSON, so it carries a `version`.
    private struct Kept: Codable {
        let version: Int
        let pending: [Stored]
    }

    /// One post as kept: its fields, and its photos by id with the path of those uploaded.
    private struct Stored: Codable {
        let id: CheckInID
        let member: MemberID
        let day: LocalDay
        /// Missing on posts kept before 补打卡: those were posted the day they count for.
        let postedDay: LocalDay?
        let createdAt: Timestamp
        let audience: [SquadID]
        /// 发布到动态; missing on posts kept before it, where an empty audience meant not posted
        /// (the server takes it the same way).
        let inFeed: Bool?
        let kind: String
        let sport: String?
        let customSport: String?
        let minutes: Int?
        /// A 训练's start, `HH:mm`; missing on the rest and on posts kept before it.
        let startTime: String?
        let caption: String?
        let text: String?
        /// A 休息 rather than a 请假条; missing on posts kept before it existed.
        let restDay: Bool?
        let photos: [StoredPhoto]
        /// A 训练's workout from Health, as posted; missing on the rest and on posts kept before it.
        let workout: Workout?
        /// The place tagged on a 训练 or a meal; missing on the rest and on posts kept before it.
        let place: StoredPlace?

        init(_ post: PendingCheckIn) {
            id = post.id
            member = post.member
            day = post.day
            postedDay = post.postedDay
            createdAt = post.createdAt
            audience = post.audience.squads
            inFeed = post.inFeed
            photos = post.draft.photos.map {
                StoredPhoto(
                    id: $0.id, path: post.uploaded[$0.id]?.path, width: $0.size?.width, height: $0.size?.height)
            }
            var sport: String?
            var customSport: String?
            var minutes: Int?
            var caption: String?
            var text: String?
            var restDay: Bool?
            workout = post.draft.workout
            var startTime: String?
            var place: Place?
            switch post.draft {
            case .trained(let activity, let workoutMinutes, let body):
                kind = "trained"
                minutes = workoutMinutes?.value
                startTime = body.startTime?.wire
                caption = body.caption
                place = body.place
                switch activity {
                case .sport(let listed): sport = listed.rawValue
                case .custom(let custom): customSport = custom.name
                }
            case .healthyMeal(let body):
                kind = "healthyMeal"
                caption = body.caption
                place = body.place
            case .cheatMeal(let body):
                kind = "cheatMeal"
                caption = body.caption
                place = body.place
            case .disclaimer(let disclaimer, _):
                kind = "disclaimer"
                text = disclaimer.text
                restDay = disclaimer.restDay ? true : nil
            }
            self.restDay = restDay
            self.startTime = startTime
            self.place = place.map(StoredPlace.init)
            (self.sport, self.customSport, self.minutes, self.caption, self.text) = (
                sport, customSport, minutes, caption, text
            )
        }

        func pending(photos directory: URL) throws -> PendingCheckIn? {
            var prepared: [PreparedPhoto] = []
            var uploaded: [UUID: PhotoRef] = [:]
            for photo in photos {
                let size = try photo.size()
                if let path = photo.path {
                    uploaded[photo.id] = try PhotoRef(path: path)
                    prepared.append(PreparedPhoto(id: photo.id, jpeg: Data(), size: size))
                } else {
                    let jpeg = try Data(contentsOf: directory.appending(path: "\(photo.id.uuidString).jpg"))
                    prepared.append(PreparedPhoto(id: photo.id, jpeg: jpeg, size: size))
                }
            }
            let trained = kind == "trained"
            let start = startTime.flatMap { try? StartTime(wire: $0) }
            let body = PostBody(
                photos: prepared, caption: caption ?? "", workout: trained ? workout : nil,
                startTime: trained ? start : nil, place: place.flatMap(\.place))
            let draft: CheckInDraft
            switch kind {
            case "trained":
                let minutes = try minutes.map(WorkoutMinutes.init)
                if let sport, let listed = Sport(rawValue: sport) {
                    draft = .trained(.sport(listed), minutes, body)
                } else if let customSport {
                    draft = .trained(.custom(try CustomSport(customSport)), minutes, body)
                } else {
                    return nil
                }
            case "healthyMeal": draft = .healthyMeal(body)
            case "cheatMeal": draft = .cheatMeal(body)
            case "disclaimer":
                guard let text else { return nil }
                draft = .disclaimer(try Disclaimer(text, restDay: restDay ?? false), photos: prepared)
            default: return nil
            }
            return PendingCheckIn(
                id: id, member: member, day: day, postedDay: postedDay, createdAt: createdAt,
                audience: try Audience(audience), inFeed: inFeed ?? !audience.isEmpty, draft: draft,
                uploaded: uploaded)
        }
    }

    /// A tagged place as the outbox keeps it.
    private struct StoredPlace: Codable {
        let name: String
        let appleID: String?
        let category: String?
        let latitude: Double
        let longitude: Double

        init(_ place: Place) {
            (name, appleID, category) = (place.name, place.appleID, place.category)
            (latitude, longitude) = (place.latitude, place.longitude)
        }

        /// Nil for one this build can no longer read: the post goes out without it.
        var place: Place? {
            try? Place(
                name: name, appleID: appleID, category: category, latitude: latitude, longitude: longitude)
        }
    }
}

/// A kept post's photo: its id, its size in pixels (missing on posts kept before sizes were
/// sent), and its path once uploaded.
private struct StoredPhoto: Codable {
    let id: UUID
    let path: String?
    let width: Int?
    let height: Int?

    func size() throws(ContractsError) -> PhotoSize? {
        guard let width, let height else { return nil }
        return try PhotoSize(width: width, height: height)
    }
}
