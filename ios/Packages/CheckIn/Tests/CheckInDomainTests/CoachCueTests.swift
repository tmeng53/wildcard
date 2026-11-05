import CheckInDomain
import Contracts
import Foundation
import Testing

private func post(_ number: Int, by member: MemberID) throws -> CheckIn {
    CheckIn(
        id: CheckInID(id(number)), member: member, day: tuesday,
        createdAt: Timestamp(millisecondsSince1970: 1_792_500_000_000 + Int64(number)),
        audience: try Audience([squadID]), entry: .trained(Training(activity: .sport("yoga"))))
}

private func home(posts: [CheckIn], mine: Int = 1, squad: Int = 14) -> Home {
    var today = sampleToday()
    today.myWeek.week.trainedDays = mine
    today.squadWeek.trainedDays = squad
    return sampleHome(today: today, checkIns: posts)
}

private func cue(from before: Home?, to now: Home) -> CoachCue? {
    CoachCue.after(before.map(CoachCue.Sighting.init), now: CoachCue.Sighting(now))
}

@Test func theCoachWhistlesWhenAPostArrives() throws {
    let first = try post(1, by: mate)
    #expect(cue(from: home(posts: [first]), to: home(posts: [first, try post(2, by: myID)])) == .whistle)
    #expect(cue(from: home(posts: [first]), to: home(posts: [first])) == nil)
}

@Test func theCoachStaysQuietTheFirstTimeItLooks() throws {
    #expect(cue(from: nil, to: home(posts: [try post(1, by: mate)])) == nil)
}

@Test func theCoachClapsWhenAWeekReachesItsGoal() throws {
    let first = try post(1, by: mate)
    let next = [first, try post(2, by: myID)]
    // My week: 4 of 5 to 5 of 5; the clap wins over the post's whistle.
    #expect(cue(from: home(posts: [first], mine: 4), to: home(posts: next, mine: 5)) == .clap)
    // The squad's: 21 of 22 to 22 of 22.
    #expect(cue(from: home(posts: [first], squad: 21), to: home(posts: next, squad: 22)) == .clap)
    // Past the goal already, another post only whistles.
    #expect(cue(from: home(posts: [first], mine: 5), to: home(posts: next, mine: 6)) == .whistle)
}
