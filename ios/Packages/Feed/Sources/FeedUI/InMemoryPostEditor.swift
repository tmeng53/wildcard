#if os(iOS)
import CheckInDomain
import CheckInUI
import Contracts
import FeedDomain
import Foundation

/// Edits and deletes the sample member's posts in an `InMemoryFeedSource`, for builds without
/// the API: a photo just added is kept in memory under a path of its own, as an upload would be.
@MainActor
public final class InMemoryPostEditor: PostEditing {
    private let source: InMemoryFeedSource
    public let recentActivities: [Activity]

    public init(source: InMemoryFeedSource, recentActivities: [Activity] = []) {
        self.source = source
        self.recentActivities = recentActivities
    }

    public func save(_ edit: PostEdit) async throws(CheckInError) -> CheckIn {
        var uploaded: [UUID: PhotoRef] = [:]
        var added: [String: Data] = [:]
        for photo in edit.newPhotos {
            let path = "\(edit.original.member)/\(photo.id.uuidString.lowercased())"
            guard let ref = try? PhotoRef(path: path) else { throw .refused }
            uploaded[photo.id] = ref
            added[path] = photo.jpeg
        }
        let checkIn = try edit.checkIn(uploaded: uploaded)
        do throws(FeedError) {
            try await source.replace(checkIn, adding: added)
        } catch {
            throw .refused
        }
        return checkIn
    }

    public func delete(_ checkIn: CheckInID) async throws(CheckInError) {
        do throws(FeedError) {
            try await source.delete(checkIn)
        } catch {
            throw .refused
        }
    }
}
#endif
