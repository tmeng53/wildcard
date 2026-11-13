#if os(iOS)
import CheckInDomain
import Contracts

/// Saves edits of the member's own posts and deletes them. The app passes the home's store, so
/// the home counts again; previews pass the sample squad.
@MainActor
public protocol PostEditing: AnyObject {
    /// The sports a 训练's picker offers first.
    var recentActivities: [Activity] { get }
    func save(_ edit: PostEdit) async throws(CheckInError) -> CheckIn
    func delete(_ checkIn: CheckInID) async throws(CheckInError)
    /// What 一起练 offers on an edit of a 训练 on `day`; none by default.
    func together(on day: LocalDay, workout: Workout?, startTime: StartTime?) -> TrainingTogether
}

extension PostEditing {
    public func together(on day: LocalDay, workout: Workout?, startTime: StartTime?) -> TrainingTogether { .none }
}

extension TodayStore: PostEditing {
    public func save(_ edit: PostEdit) async throws(CheckInError) -> CheckIn {
        try await self.edit(edit)
    }

    public func together(on day: LocalDay, workout: Workout?, startTime: StartTime?) -> TrainingTogether {
        home?.together(on: day, workout: workout, startTime: startTime) ?? .none
    }
}
#endif
