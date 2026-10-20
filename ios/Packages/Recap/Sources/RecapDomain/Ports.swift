import Contracts

/// Where the story comes from: the API, for the signed-in member. `Backend` has the adapter.
public protocol WeekStoryService: Sendable {
    /// The squad's story for the week starting `monday`, nil while the week isn't over yet
    /// (before Sunday 8pm ET), so there is nothing to open.
    func story(squad: SquadID, week monday: LocalDay) async throws(RecapError) -> WeekStory?
}
