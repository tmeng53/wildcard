#if os(iOS)
import AvatarArt
import AvatarDomain
import CheckInDomain
import Contracts
import Foundation

/// The coach on the home's sideline: a tap starts its pep talk and opens its page, the cards it
/// has for the member (Tracy, 2026-11-08). While its page has a card not seen yet, its phone shows
/// a dot and it whistles again and again (Tracy, 2026-11-09).
extension TodayModel {
    /// The coach's 战术板 line while its day lasts, for its 简历.
    public var coachLine: CoachNote? { store.coachLine }

    /// Whether the coach's phone shows its dot: its page has a card not seen yet.
    var coachHasNews: Bool { store.hasUnseenCoachCards }

    /// Reads the squad's coach again, after it was hired, changed or fired, and stands the new
    /// one (or its empty spot) on the sideline; also after its page, where a note seen takes the
    /// dot away.
    public func reloadCoach() async {
        await store.loadCoach()
        placeSquad()
    }

    /// The coach's empty spot was tapped: 教练招聘会 opens, routed as the app routes a notice.
    func tapVacancy() {
        guard arrival == nil else { return }
        openDestination?(.coaches)
    }

    /// The coach whistles once more because its page has news.
    func coachWhistlesForNews() {
        cast.coachWhistlesForNews()
    }

    /// The coach was tapped: it gives its pep talk and its page opens.
    func tapCoach() {
        guard arrival == nil else { return }
        cast.coachTalks()
        openCoach()
    }

    /// The member's own character, as the coach's page stands them by the coach.
    public var myCharacter: (look: Outfit, persona: Persona) { (myLook, myPersona) }

    /// Everyone else in the squad, as they made their characters (a stand-in before), in the
    /// order the home lists them, for the coach's line to everyone.
    public var squadmateCharacters: [(look: Outfit, persona: Persona)] {
        guard let home else { return [] }
        return home.today.members.filter { $0.member != home.member }.map {
            (SquadCast.look(of: $0), SquadCast.persona(of: $0))
        }
    }

    /// The coach on the sideline, as last read; nil while the squad has none.
    public var sidelineCoach: CoachSpeaker? { store.coach?.coach }

    /// The day's challenge I accepted from the coach, while its day lasts.
    var myChallenge: DayChallenge? { store.acceptedChallenge }

    /// 我完成了 on today's challenge.
    func completeChallenge() {
        Task { await store.completeChallenge() }
    }

    /// The squad on the home, whose coach's page opens.
    public var squadID: SquadID? { home?.squad.id }
}
#endif
