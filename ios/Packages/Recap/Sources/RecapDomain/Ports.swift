import Contracts

/// Where the story comes from: the API, for the signed-in member. `Backend` has the adapter.
public protocol WeekStoryService: Sendable {
    /// The squad's story for the week starting `monday`, nil while the week isn't over yet
    /// (before Sunday 8pm ET), so there is nothing to open.
    func story(squad: SquadID, week monday: LocalDay) async throws(RecapError) -> WeekStory?
    /// The Mondays of every week the squad has a story for, the latest first (往期战报).
    func weeks(squad: SquadID) async throws(RecapError) -> [LocalDay]
    /// 催一下主办方: asks for the late titles to be tried again soon. Safe to repeat.
    func nudge(squad: SquadID, week monday: LocalDay) async throws(RecapError)
}
