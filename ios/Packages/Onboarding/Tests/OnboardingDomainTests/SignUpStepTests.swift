import Contracts
import OnboardingDomain
import Testing

struct SignUpStepTests {
    @Test func theHeaderCountsFourTaskSteps() {
        #expect(SignUpStep.allCases.map(\.number) == [nil, 1, 2, 3, 4, nil, nil])
        #expect(SignUpStep.counted.count == 4)
    }

    @Test func stepsGoInTheApprovedOrder() {
        #expect(SignUpStep.welcome.next == .character)
        #expect(SignUpStep.character.next == .squad)
        #expect(SignUpStep.squad.next == .sports)
        #expect(SignUpStep.sports.next == .week)
        #expect(SignUpStep.week.next == .scene)
        #expect(SignUpStep.scene.next == .entrance)
        #expect(SignUpStep.entrance.next == nil)
    }

    @Test func onlyWhoeverMadeTheSquadPicksItsScene() {
        #expect(SignUpStep.afterWeek(madeTheSquad: true) == .scene)
        #expect(SignUpStep.afterWeek(madeTheSquad: false) == .entrance)
        #expect(SignUpStep.scene.previous == .week)
    }

    @Test func thereIsNoGoingBackFromTheOpenScreenOrTheEntrance() {
        #expect(SignUpStep.welcome.previous == nil)
        #expect(SignUpStep.entrance.previous == nil)
        #expect(SignUpStep.week.previous == .sports)
        #expect(SignUpStep.character.previous == .welcome)
    }
}

struct SquadDraftTests {
    @Test func anInviteOpensOnJoinWithItsCode() throws {
        let draft = SquadDraft(invite: try InviteCode("K7M2QX9P"), suggestedName: "Tracy 的小队")
        #expect(draft.choice == .join)
        #expect(draft.code == (try InviteCode("K7M2QX9P")))
        #expect(draft.codeLetters == Array("K7M2QX9P"))
    }

    @Test func withoutAnInviteItOpensOnCreateWithTheSuggestedName() throws {
        let draft = SquadDraft(invite: nil, suggestedName: "Tracy 的小队")
        #expect(draft.choice == .create)
        #expect(draft.name == (try SquadName("Tracy 的小队")))
        #expect(draft.code == nil)
    }

    @Test func aHalfTypedCodeShowsButIsNoCodeYet() {
        var draft = SquadDraft(invite: nil, suggestedName: "")
        draft.typedCode = "k7m-2"
        #expect(draft.codeLetters == Array("K7M2"))
        #expect(draft.code == nil)
        draft.typedCode = "k7m2-qx9p-zz"
        #expect(draft.codeLetters == Array("K7M2QX9P"))
        #expect(draft.code == nil)
    }

    @Test func aNameTooLongIsNoName() {
        var draft = SquadDraft(invite: nil, suggestedName: "")
        #expect(draft.name == nil)
        draft.typedName = String(repeating: "腿", count: SquadName.maxLength + 1)
        #expect(draft.name == nil)
    }
}

struct SportPicksTests {
    @Test func theCharacterWearsTheLatestPick() {
        var picks = SportPicks()
        #expect(picks.wearing == nil)
        #expect(picks.toggle(.sport(.run)) == .picked)
        #expect(picks.toggle(.sport(.strength)) == .picked)
        #expect(picks.wearing == .sport(.strength))
        #expect(picks.picked == [.sport(.run), .sport(.strength)])
    }

    @Test func takingOffTheWornSportChangesBackToTheOneBefore() {
        var picks = SportPicks([.sport(.run), .sport(.strength)])
        #expect(picks.toggle(.sport(.strength)) == .removed(changed: true))
        #expect(picks.wearing == .sport(.run))
        #expect(picks.toggle(.sport(.run)) == .removed(changed: true))
        #expect(picks.wearing == nil)
    }

    @Test func takingOffAnotherSportKeepsWhatIsWorn() {
        var picks = SportPicks([.sport(.run), .sport(.strength)])
        #expect(picks.toggle(.sport(.run)) == .removed(changed: false))
        #expect(picks.wearing == .sport(.strength))
    }

    @Test func theListsHaveNoRepeats() {
        #expect(Set(SportPicks.common).count == SportPicks.common.count)
        #expect(SportPicks.common == [.swim, .run, .strength, .tennis, .climb, .yoga])
    }
}
