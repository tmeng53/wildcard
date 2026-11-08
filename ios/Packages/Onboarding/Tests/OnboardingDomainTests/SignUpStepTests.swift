import Contracts
import OnboardingDomain
import Testing

struct SignUpStepTests {
    @Test func theHeaderCountsSixTaskSteps() {
        #expect(SignUpStep.allCases.map(\.number) == [nil, 1, 2, 3, 4, 5, 6, nil, nil])
        #expect(SignUpStep.counted.count == 6)
    }

    @Test func stepsGoInTheApprovedOrder() {
        #expect(SignUpStep.welcome.next == .character)
        #expect(SignUpStep.character.next == .squad)
        #expect(SignUpStep.squad.next == .sports)
        #expect(SignUpStep.sports.next == .health)
        #expect(SignUpStep.health.next == .location)
        #expect(SignUpStep.location.next == .week)
        #expect(SignUpStep.week.next == .scene)
        #expect(SignUpStep.scene.next == .entrance)
        #expect(SignUpStep.entrance.next == nil)
    }

    @Test func onlyWhoeverMadeTheSquadPicksItsScene() {
        #expect(SignUpStep.afterWeek(madeTheSquad: true) == .scene)
        #expect(SignUpStep.afterWeek(madeTheSquad: false) == .entrance)
        #expect(SignUpStep.scene.previous == .week)
    }

    @Test func aStepThatCantBeDoneIsSkippedBothWays() {
        #expect(SignUpStep.sports.next(hasHealth: true, hasLocation: true) == .health)
        #expect(SignUpStep.sports.next(hasHealth: false, hasLocation: true) == .location)
        #expect(SignUpStep.sports.next(hasHealth: false, hasLocation: false) == .week)
        #expect(SignUpStep.health.next(hasHealth: true, hasLocation: false) == .week)
        #expect(SignUpStep.week.previous(hasHealth: true, hasLocation: true) == .location)
        #expect(SignUpStep.week.previous(hasHealth: true, hasLocation: false) == .health)
        #expect(SignUpStep.week.previous(hasHealth: false, hasLocation: false) == .sports)
        #expect(SignUpStep.location.previous(hasHealth: false, hasLocation: true) == .sports)
    }

    @Test func thereIsNoGoingBackFromTheOpenScreenOrTheEntrance() {
        #expect(SignUpStep.welcome.previous == nil)
        #expect(SignUpStep.entrance.previous == nil)
        #expect(SignUpStep.week.previous == .location)
        #expect(SignUpStep.location.previous == .health)
        #expect(SignUpStep.health.previous == .sports)
        #expect(SignUpStep.character.previous == .welcome)
    }
}

struct SquadDraftTests {
    @Test func anInviteOpensOnJoinWithItsCode() throws {
        let draft = SquadDraft(invite: try InviteCode("K7M2QX9P"), suggestedName: "Tracy 的小队", timeZone: "Asia/Taipei")
        #expect(draft.choice == .join)
        #expect(draft.code == (try InviteCode("K7M2QX9P")))
        #expect(draft.codeLetters == Array("K7M2QX9P"))
    }

    @Test func withoutAnInviteItOpensOnCreateWithTheSuggestedName() throws {
        let draft = SquadDraft(invite: nil, suggestedName: "Tracy 的小队", timeZone: "Asia/Taipei")
        #expect(draft.choice == .create)
        #expect(draft.name == (try SquadName("Tracy 的小队")))
        #expect(draft.timeZone == "Asia/Taipei")
        #expect(draft.code == nil)
    }

    @Test func aHalfTypedCodeShowsButIsNoCodeYet() {
        var draft = SquadDraft(invite: nil, suggestedName: "", timeZone: "Asia/Taipei")
        draft.typedCode = "k7m-2"
        #expect(draft.codeLetters == Array("K7M2"))
        #expect(draft.code == nil)
        draft.typedCode = "k7m2-qx9p-zz"
        #expect(draft.codeLetters == Array("K7M2QX9P"))
        #expect(draft.code == nil)
    }

    @Test func aNameTooLongIsNoName() {
        var draft = SquadDraft(invite: nil, suggestedName: "", timeZone: "Asia/Taipei")
        #expect(draft.name == nil)
        draft.typedName = String(repeating: "腿", count: SquadName.maxLength + 1)
        #expect(draft.name == nil)
    }
}

struct SportPicksTests {
    @Test func theCharacterWearsTheLatestPick() {
        var picks = SportPicks()
        #expect(picks.wearing == nil)
        #expect(picks.toggle(.sport("run")) == .picked)
        #expect(picks.toggle(.sport("strength")) == .picked)
        #expect(picks.wearing == .sport("strength"))
        #expect(picks.picked == [.sport("run"), .sport("strength")])
    }

    @Test func takingOffTheWornSportChangesBackToTheOneBefore() {
        var picks = SportPicks([.sport("run"), .sport("strength")])
        #expect(picks.toggle(.sport("strength")) == .removed(changed: true))
        #expect(picks.wearing == .sport("run"))
        #expect(picks.toggle(.sport("run")) == .removed(changed: true))
        #expect(picks.wearing == nil)
    }

    @Test func takingOffAnotherSportKeepsWhatIsWorn() {
        var picks = SportPicks([.sport("run"), .sport("strength")])
        #expect(picks.toggle(.sport("run")) == .removed(changed: false))
        #expect(picks.wearing == .sport("strength"))
    }
}
