import CheckInDomain
import Contracts
import Testing

private let third = MemberID(id(4))

private func member(
    _ id: MemberID, _ status: StageStatus, at minute: Int64? = nil, shy: Bool = false
) -> StageMember {
    StageMember(
        id: id, status: status, firstCheckInAt: minute.map { Timestamp(millisecondsSince1970: $0 * 60_000) },
        keepsToTheBack: shy)
}

private let run = Activity.sport("run")
private let yoga = Activity.sport("yoga")
private let shortWeek = WeekCount(trainedDays: 3, plannedDays: 10)

@Test func nobodyTrainedCelebratesNothing() {
    let members = [member(myID, .notYet), member(mate, .restDay)]
    #expect(SquadCelebration.pick(myself: myID, members: members, squadWeek: shortWeek, shown: []) == nil)
}

@Test func aWeekReachedWavesFirst() {
    let members = [member(myID, .trained(run), at: 1), member(mate, .trained(run), at: 2)]
    let week = WeekCount(trainedDays: 10, plannedDays: 10)
    #expect(SquadCelebration.pick(myself: myID, members: members, squadWeek: week, shown: []) == .wave)
    #expect(
        SquadCelebration.pick(myself: myID, members: members, squadWeek: week, shown: [.wave])
            == .stack(top: mate, bottom: myID))
}

@Test func aSquadOfOneNeverWaves() {
    let week = WeekCount(trainedDays: 4, plannedDays: 4)
    #expect(
        SquadCelebration.pick(myself: myID, members: [member(myID, .trained(run), at: 1)], squadWeek: week, shown: [])
            == nil)
}

@Test func theSameSportStacksTheLaterOneOnTop() {
    let members = [
        member(myID, .trained(yoga), at: 1), member(mate, .trained(run), at: 5), member(third, .trained(run), at: 3),
    ]
    #expect(
        SquadCelebration.pick(myself: myID, members: members, squadWeek: shortWeek, shown: [])
            == .stack(top: mate, bottom: third))
}

@Test func differentSportsBumpMeAndTheFirstTeammate() {
    let members = [
        member(myID, .trained(yoga), at: 9), member(mate, .trained(run), at: 5), member(third, .trained(nil), at: 2),
    ]
    #expect(
        SquadCelebration.pick(myself: myID, members: members, squadWeek: shortWeek, shown: [])
            == .bump(mine: myID, mate: third, dodged: false))
}

@Test func aShyTeammateDodgesTheBump() {
    let members = [member(myID, .trained(yoga), at: 1), member(mate, .trained(run), at: 2, shy: true)]
    #expect(
        SquadCelebration.pick(myself: myID, members: members, squadWeek: shortWeek, shown: [])
            == .bump(mine: myID, mate: mate, dodged: true))
}

@Test func noBumpUntilITrained() {
    let members = [member(myID, .disclaimer), member(mate, .trained(run), at: 2), member(third, .trained(yoga), at: 3)]
    #expect(SquadCelebration.pick(myself: myID, members: members, squadWeek: shortWeek, shown: []) == nil)
}

@Test func eachKindPlaysOnceADay() {
    let members = [member(myID, .trained(run), at: 1), member(mate, .trained(run), at: 2)]
    #expect(
        SquadCelebration.pick(myself: myID, members: members, squadWeek: shortWeek, shown: [.stack])
            == .bump(mine: myID, mate: mate, dodged: false))
    #expect(SquadCelebration.pick(myself: myID, members: members, squadWeek: shortWeek, shown: [.stack, .bump]) == nil)
}
