import Contracts
import DesignSystem
import Foundation
import Testing

@testable import CheckInDomain

private func id(_ number: Int) -> MemberID {
    MemberID(UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", number)) ?? UUID())
}

private func at(_ minute: Int64) -> Timestamp {
    Timestamp(millisecondsSince1970: 1_760_000_000_000 + minute * 60_000)
}

private func member(_ number: Int, _ status: StageStatus, _ minute: Int64? = nil, shy: Bool = false) -> StageMember {
    StageMember(id: id(number), status: status, firstCheckInAt: minute.map(at), keepsToTheBack: shy)
}

private func point(_ across: Double, _ y: Double) -> StagePoint { StagePoint(x: across, y: y) }

@Test func aDayIsTrainedThenOnLeaveThenRestThenNotYet() {
    let run = Activity.sport(.run)
    #expect(StageStatus(training: .trained, activity: run, plannedRest: true) == .trained(run))
    #expect(StageStatus(training: .disclaimer, activity: nil, plannedRest: true) == .disclaimer)
    #expect(StageStatus(training: .notCheckedIn, activity: nil, plannedRest: true) == .restDay)
    #expect(StageStatus(training: .notCheckedIn, activity: nil, plannedRest: false) == .notYet)
    #expect(StageStatus.trained(run).ring == .checkedIn)
    #expect(StageStatus.disclaimer.ring == .checkedIn)
    #expect(StageStatus.restDay.ring == .restDay)
    #expect(StageStatus.notYet.ring == .none)
}

@Test func nightIsFromSevenInTheEveningToSixInTheMorning() {
    #expect(DayPhase(hour: 5) == .night)
    #expect(DayPhase(hour: 6) == .day)
    #expect(DayPhase(hour: 18) == .day)
    #expect(DayPhase(hour: 19) == .night)
    #expect(DayPhase(hour: 0) == .night)
}

@Test func teammatesAreSizedByDepthAndIAmTheBiggest() {
    #expect(StageLayout.scale(atDepth: 200) == 0.17)
    #expect(abs(StageLayout.scale(atDepth: 460) - 0.21) < 1e-9)
    #expect(StageLayout.scale(atDepth: 700) == 0.25)
    #expect(StageLayout.myScale == 0.28)
    #expect(StageLayout.mySpot == point(195, 676))
}

@Test func theFloorFillsLikeATeamPhotoFrontRowFirstFromTheMiddleOut() {
    let floor = StageLayout.of(.track).floor
    // The middle of the front row is mine.
    #expect(
        Array(floor.prefix(8)) == [
            point(115, 626), point(275, 626), point(35, 626), point(355, 626),
            point(155, 566), point(235, 566), point(75, 566), point(315, 566),
        ])
    #expect(!floor.contains(point(195, 626)))
}

@Test func everySceneHasRoomForTheWholeSquadOnItsFloor() {
    for scene in SceneTheme.allCases {
        #expect(StageLayout.of(scene).floor.count >= 7, "\(scene)")
    }
}

@Test func theEarliestCheckInGetsTheBestSpotAndNotCheckedInComeLast() {
    var stage = SquadStage(layout: .of(.track))
    stage.arrange([
        member(1, .notYet),
        member(2, .disclaimer, 30),
        member(3, .restDay),
        member(4, .disclaimer, 10),
    ])
    #expect(stage.placements[id(4)] == .floor(point(115, 626)))
    #expect(stage.placements[id(2)] == .floor(point(275, 626)))
    #expect(stage.placements[id(1)] == .floor(point(35, 626)))
    #expect(stage.placements[id(3)] == .floor(point(355, 626)))
}

@Test func theShyTakeTheLastFreeSpot() {
    var stage = SquadStage(layout: .of(.track))
    stage.arrange([member(1, .notYet, shy: true), member(2, .notYet)])
    #expect(stage.placements[id(1)] == .floor(StageLayout.of(.track).floor.last ?? point(0, 0)))
    #expect(stage.placements[id(2)] == .floor(point(115, 626)))
}

@Test func aMatchingSportUsesTheScenesEquipmentInCheckInOrder() {
    var stage = SquadStage(layout: .of(.gym))
    stage.arrange([
        member(1, .trained(.sport(.strength)), 20),
        member(2, .trained(.sport(.strength)), 5),
        member(3, .trained(.sport(.strength)), 30),
        member(4, .trained(.sport(.yoga)), 40),
    ])
    #expect(stage.placements[id(2)] == .station(.squatRack, slot: 0))
    #expect(stage.placements[id(1)] == .station(.squatRack, slot: 1))
    // The racks are full, so the third lifter takes the dumbbells.
    #expect(stage.placements[id(3)] == .station(.dumbbells, slot: 0))
    #expect(stage.placements[id(4)] == .station(.yogaMat, slot: 0))
}

@Test func whileTheEquipmentIsIdleOtherSportsTrainOnThePlayingArea() {
    var stage = SquadStage(layout: .of(.track))
    stage.arrange([member(1, .trained(.sport(.yoga)), 1), member(2, .trained(nil), 2)])
    #expect(stage.placements[id(1)] == .field(point(175, 408)))
    #expect(stage.placements[id(2)] == .field(point(255, 408)))

    // Once a runner is on the track, the yogi trains on the open floor instead.
    stage.arrange([
        member(1, .trained(.sport(.yoga)), 1), member(2, .trained(nil), 2), member(3, .trained(.sport(.run)), 3),
    ])
    #expect(stage.placements[id(3)] == .station(.jogging, slot: 0))
    #expect(stage.placements[id(1)] == .floor(point(115, 626)))
    #expect(stage.placements[id(2)] == .floor(point(275, 626)))
}

@Test func peopleKeepTheirSpotWhenTheirStatusChanges() {
    var stage = SquadStage(layout: .of(.pool))
    stage.arrange([member(1, .notYet), member(2, .notYet), member(3, .notYet)])
    #expect(stage.placements[id(3)] == .floor(point(35, 626)))

    // Teammate 3 checks in first; nobody moves to make room for them.
    stage.arrange([member(1, .notYet), member(2, .notYet), member(3, .disclaimer, 1)])
    #expect(stage.placements[id(1)] == .floor(point(115, 626)))
    #expect(stage.placements[id(2)] == .floor(point(275, 626)))
    #expect(stage.placements[id(3)] == .floor(point(35, 626)))

    // A swimmer goes to the water; the others stay put.
    stage.arrange([member(1, .trained(.sport(.swim)), 2), member(2, .notYet), member(3, .disclaimer, 1)])
    #expect(stage.placements[id(1)] == .station(.swimming, slot: 0))
    #expect(stage.placements[id(2)] == .floor(point(275, 626)))
    #expect(stage.placements[id(3)] == .floor(point(35, 626)))
}

@Test func someoneOnEquipmentKeepsTheirSlotWhenAnEarlierTeammateArrives() {
    var stage = SquadStage(layout: .of(.climbing))
    stage.arrange([member(1, .trained(.sport(.climb)), 30)])
    #expect(stage.placements[id(1)] == .station(.topRope, slot: 0))
    stage.arrange([member(1, .trained(.sport(.climb)), 30), member(2, .trained(.sport(.climb)), 10)])
    #expect(stage.placements[id(1)] == .station(.topRope, slot: 0))
    #expect(stage.placements[id(2)] == .station(.topRope, slot: 1))
}

@Test func posesFollowTheStatusAndAtNightOnlyTrainingStaysAwake() {
    var stage = SquadStage(layout: .of(.tennis))
    let people = [
        member(1, .trained(.sport(.tennis)), 1), member(2, .trained(.sport(.run)), 2),
        member(3, .disclaimer, 3), member(4, .restDay), member(5, .notYet),
    ]
    stage.arrange(people)
    #expect(
        people.map { stage.pose(of: $0, at: .day) } == [
            .station(.rally), .inPlace(.sport(.run)), .holdingSign, .sitting, .standing,
        ])
    #expect(
        people.map { stage.pose(of: $0, at: .night) } == [
            .station(.rally), .inPlace(.sport(.run)), .asleep, .asleep, .asleep,
        ])
}

@Test func runnersLapTheTrackEvenlySpacedAndSwimmersTurnAtTheWall() {
    let track = StageLayout.of(.track)
    guard let jogging = track.stations.first(where: { $0.kind == .jogging }),
        let pool = StageLayout.of(.pool).stations.first
    else {
        Issue.record("missing stations")
        return
    }
    // Two lanes, two runners each, half a lap apart; the inner lane runs the other way.
    #expect(SquadStage.position(on: jogging, slot: 0, at: 0).point == point(-30, 371))
    #expect(SquadStage.position(on: jogging, slot: 2, at: 0).point == point(195, 371))
    #expect(SquadStage.position(on: jogging, slot: 0, at: 2).point == point(66, 371))
    #expect(SquadStage.position(on: jogging, slot: 1, at: 1).point == point(372, 422))
    #expect(SquadStage.position(on: jogging, slot: 1, at: 1).facing == -1)
    // 318 wide at 34 a second: out for 9.35 seconds, then back.
    #expect(SquadStage.position(on: pool, slot: 0, at: 5).point == point(206, 294))
    #expect(SquadStage.position(on: pool, slot: 0, at: 10).point.x == 354 - (340 - 318))
    #expect(SquadStage.position(on: pool, slot: 0, at: 10).facing == -1)
}

@Test func climbersAreDrawnSmallerToFitTheWall() {
    var stage = SquadStage(layout: .of(.climbing))
    stage.arrange([member(1, .trained(.sport(.climb)), 1)])
    #expect(stage.position(of: id(1), at: 0) == StagePosition(point: point(132, 392), facing: 1, scale: 0.19))
}

@Test func cheersGoNearestFirstAndSkipSwimmersAndSleepers() {
    var stage = SquadStage(layout: .of(.pool))
    let people = [
        member(1, .trained(.sport(.swim)), 1), member(2, .notYet), member(3, .disclaimer, 2),
        member(4, .trained(.sport(.run)), 3),
    ]
    stage.arrange(people)
    // The pool is in use, so the runner trains on the floor: 3 (checked in first) at (115, 626)
    // and 4 at (275, 626) are equally near me and keep check-in order; 2 is at (35, 626).
    #expect(stage.cheerers(people, at: .day) == [id(3), id(4), id(2)])
    #expect(stage.cheerers(people, at: .night) == [id(4)])
}

@Test func theCardListsCheckInsInOrderThenRestDaysThenTheRest() {
    let people = [
        member(1, .notYet), member(2, .restDay), member(3, .trained(nil), 20), member(4, .disclaimer, 5),
        member(5, .restDay),
    ]
    #expect(SquadStage.cardOrder(people).map(\.id) == [id(4), id(3), id(2), id(5), id(1)])
}
