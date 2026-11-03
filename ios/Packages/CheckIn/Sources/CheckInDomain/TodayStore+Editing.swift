import Contracts
import Foundation

// Editing and deleting the member's own posts.
extension TodayStore {
    /// Saves an edit of one of the member's own posts: uploads its new photos, then the post as
    /// edited. Never queued: the member is looking at the post and waits for it.
    public func edit(_ edit: PostEdit) async throws(CheckInError) -> CheckIn {
        for photo in edit.newPhotos where editUploads[photo.id] == nil {
            editUploads[photo.id] = try await backend.upload(photo)
        }
        let saved = try await backend.edit(try edit.checkIn(uploaded: editUploads))
        editUploads = [:]
        if var home = savedHome, let index = home.checkIns.firstIndex(where: { $0.id == saved.id }) {
            home.checkIns[index] = saved
            savedHome = home
        }
        await refresh()
        return saved
    }

    /// Deletes one of the member's own posts. One still in the outbox never goes out.
    public func delete(_ id: CheckInID) async throws(CheckInError) {
        if pending.contains(where: { $0.id == id }) { await drop(id) }
        try await backend.delete(id)
        if var home = savedHome {
            home.checkIns.removeAll { $0.id == id }
            savedHome = home
        }
        await refresh()
    }
}
