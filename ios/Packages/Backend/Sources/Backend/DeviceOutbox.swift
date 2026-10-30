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
        let createdAt: Timestamp
        let audience: [SquadID]
        let kind: String
        let sport: String?
        let customSport: String?
        let minutes: Int?
        let caption: String?
        let text: String?
        let photos: [StoredPhoto]

        init(_ post: PendingCheckIn) {
            id = post.id
            member = post.member
            day = post.day
            createdAt = post.createdAt
            audience = post.audience.squads
            photos = post.draft.photos.map { StoredPhoto(id: $0.id, path: post.uploaded[$0.id]?.path) }
            var sport: String?
            var customSport: String?
            var minutes: Int?
            var caption: String?
            var text: String?
            switch post.draft {
            case .trained(let activity, let workoutMinutes, let body):
                kind = "trained"
                minutes = workoutMinutes?.value
                caption = body.caption
                switch activity {
                case .sport(let listed): sport = listed.rawValue
                case .custom(let custom): customSport = custom.name
                }
            case .healthyMeal(let body):
                kind = "healthyMeal"
                caption = body.caption
            case .cheatMeal(let body):
                kind = "cheatMeal"
                caption = body.caption
            case .disclaimer(let disclaimer):
                kind = "disclaimer"
                text = disclaimer.text
            }
            (self.sport, self.customSport, self.minutes, self.caption, self.text) = (
                sport, customSport, minutes, caption, text
            )
        }

        func pending(photos directory: URL) throws -> PendingCheckIn? {
            var prepared: [PreparedPhoto] = []
            var uploaded: [UUID: PhotoRef] = [:]
            for photo in photos {
                if let path = photo.path {
                    uploaded[photo.id] = try PhotoRef(path: path)
                    prepared.append(PreparedPhoto(id: photo.id, jpeg: Data()))
                } else {
                    let jpeg = try Data(contentsOf: directory.appending(path: "\(photo.id.uuidString).jpg"))
                    prepared.append(PreparedPhoto(id: photo.id, jpeg: jpeg))
                }
            }
            let body = PostBody(photos: prepared, caption: caption ?? "")
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
                draft = .disclaimer(try Disclaimer(text))
            default: return nil
            }
            return PendingCheckIn(
                id: id, member: member, day: day, createdAt: createdAt, audience: try Audience(audience), draft: draft,
                uploaded: uploaded)
        }
    }
}

/// A kept post's photo: its id, and its path once uploaded.
private struct StoredPhoto: Codable {
    let id: UUID
    let path: String?
}
