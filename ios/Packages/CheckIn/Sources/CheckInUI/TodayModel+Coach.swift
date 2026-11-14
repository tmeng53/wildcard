#if os(iOS)
import AvatarArt
import AvatarDomain
import CheckInDomain
import Contracts
import DesignSystemUI
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

    /// The coach does one of its habits, by day on a plain scene.
    func coachDoesAHabit() {
        guard stagePhase == .day, step == .scene, !isBurstOpen, arrival == nil else { return }
        cast.coachDoesAHabit()
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

    /// Everyone in the squad by id, me too, as they made their characters (a stand-in before), for a
    /// coach message that names who stands with the coach.
    public var squadCharactersByMember: [MemberID: (look: Outfit, persona: Persona)] {
        guard let home else { return [:] }
        var characters: [MemberID: (look: Outfit, persona: Persona)] = [:]
        for member in home.today.members {
            characters[member.member] = (SquadCast.look(of: member), SquadCast.persona(of: member))
        }
        // Mine as I'm dressed now, as the coach's page stands me beside the coach.
        characters[home.member] = myCharacter
        return characters
    }

    /// The coach on the sideline, as last read; nil while the squad has none.
    public var sidelineCoach: CoachSpeaker? { store.coach?.coach }

    /// The day's challenge I accepted from the coach, while its day lasts.
    var myChallenge: DayChallenge? { store.acceptedChallenge }

    /// Where this phone keeps the challenge, by its note, the coach last pumped its fist for.
    static let cheeredChallengeKey = "today.cheeredChallenge"

    /// The coach pumps its fist once for each challenge I accepted, the first time the home shows
    /// it on this phone: right after I accept it, or on the next open after accepting elsewhere.
    func cheerAcceptedChallenge() {
        guard let note = myChallenge?.note, defaults.string(forKey: Self.cheeredChallengeKey) != note else { return }
        defaults.set(note, forKey: Self.cheeredChallengeKey)
        cast.coachCheersTheChallenge()
    }

    /// 我完成了 on today's challenge: the coach who set it claps.
    func completeChallenge() {
        guard myChallenge?.challenge.completedBy == nil else { return }
        cast.coachClaps()
        Task { await store.completeChallenge() }
    }

    /// The coach's head on today's challenge row was tapped: the challenge's card on its page opens.
    func openMyChallenge() {
        guard let myChallenge else { return }
        openChallenge(myChallenge)
    }

    /// What the coach said that I haven't seen, for its row on the squad card: its name and the
    /// start of its newest line (a coach message's first line in the app's language), a gift
    /// without one saying 送你一样东西.
    var coachNews: CoachNewsLine? {
        guard let card = store.newestUnseenCoachCard else { return nil }
        let line =
            card.newsLine ?? card.message?.cards.first?.line.localized(in: [AppLanguage.current.rawValue])
            ?? String(copyKey: "送你一样东西", bundle: Bundle.module.inAppLanguage)
        return CoachNewsLine(name: card.coach.name, line: line)
    }

    /// The coach whose words wait unseen, whose head starts its row.
    var coachNewsSpeaker: CoachSpeaker? { store.newestUnseenCoachCard?.coach }

    /// The coach's row on the squad card was tapped: its page opens on what it said today.
    func openCoachNews() {
        guard arrival == nil else { return }
        openCoach()
    }

    /// The squad on the home, whose coach's page opens.
    public var squadID: SquadID? { home?.squad.id }
}
#endif
