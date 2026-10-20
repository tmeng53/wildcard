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
}

@Test func nightIsFromSevenInTheEveningToSixInTheMorning() {
    #expect(DayPhase(hour: 5) == .night)
    #expect(DayPhase(hour: 6) == .day)
    #expect(DayPhase(hour: 18) == .day)
    #expect(DayPhase(hour: 19) == .night)
    #expect(DayPhase(hour: 0) == .night)
}

@Test func teammatesAreSizedByDepthAndIAmTheBiggest() {
    #expect(StageLayout.scale(atDepth: 200) == 0.21)
    #expect(abs(StageLayout.scale(atDepth: 460) - 0.25) < 1e-9)
    #expect(StageLayout.scale(atDepth: 700) == 0.29)
    #expect(StageLayout.myScale == 0.34)
    #expect(StageLayout.mySpot == point(195, 676))
}

@Test func theFloorFillsLikeATeamPhotoFrontRowFirstFromTheMiddleOut() {
    let floor = StageLayout.of(.track).floor
    // The middle of the front row is mine.
    #expect(
        Array(floor.prefix(8)) == [
            point(103, 626), point(287, 626), point(149, 556), point(241, 556),
            point(57, 556), point(333, 556), point(195, 486), point(103, 486),
        ])
    #expect(!floor.contains(point(195, 626)))
}

@Test func everySceneHasRoomForTheWholeSquadOnItsFloor() {
    for scene in SceneTheme.allCases {
        #expect(StageLayout.of(scene).floor.count >= 7, "\(scene)")
    }
}

@Test func nobodyIsDrawnOverAnotherOnTheFloorOrThePlayingArea() {
    // Some floor spots sit near playing-area spots, which fill while the equipment is idle.
    for scene in SceneTheme.allCases {
        for trainers in 0...7 {
            var stage = SquadStage(layout: .of(scene))
            stage.arrange(
                (1...7).map { number in
                    number <= trainers
                        ? member(number, .trained(nil), Int64(number))
                        : member(number, .notYet, shy: number.isMultiple(of: 2))
                })
            let spots = stage.placements.values.compactMap { placement -> StagePoint? in
                switch placement {
                case .field(let spot), .floor(let spot): spot
                case .station: nil
                }
            }
            #expect(spots.count == 7, "\(scene) \(trainers)")
            for (index, spot) in spots.enumerated() {
                for other in spots[(index + 1)...] {
                    #expect(!StageLayout.crowds(spot, other), "\(scene) \(trainers): \(spot) \(other)")
                }
            }
        }
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
    #expect(stage.placements[id(4)] == .floor(point(103, 626)))
    #expect(stage.placements[id(2)] == .floor(point(287, 626)))
    #expect(stage.placements[id(1)] == .floor(point(149, 556)))
    #expect(stage.placements[id(3)] == .floor(point(241, 556)))
}

@Test func theShyTakeTheLastFreeSpot() {
    var stage = SquadStage(layout: .of(.track))
    stage.arrange([member(1, .notYet, shy: true), member(2, .notYet)])
    #expect(stage.placements[id(1)] == .floor(StageLayout.of(.track).floor.last ?? point(0, 0)))
    #expect(stage.placements[id(2)] == .floor(point(103, 626)))
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
    #expect(stage.placements[id(1)] == .field(point(175, 438)))
    #expect(stage.placements[id(2)] == .field(point(255, 438)))

    // Once a runner is on the track, the yogi trains on the open floor instead.
    stage.arrange([
        member(1, .trained(.sport(.yoga)), 1), member(2, .trained(nil), 2), member(3, .trained(.sport(.run)), 3),
    ])
    #expect(stage.placements[id(3)] == .station(.jogging, slot: 0))
    #expect(stage.placements[id(1)] == .floor(point(103, 626)))
    #expect(stage.placements[id(2)] == .floor(point(287, 626)))
}

@Test func peopleKeepTheirSpotWhenTheirStatusChanges() {
    var stage = SquadStage(layout: .of(.pool))
    stage.arrange([member(1, .notYet), member(2, .notYet), member(3, .notYet)])
    #expect(stage.placements[id(3)] == .floor(point(149, 556)))

    // Teammate 3 checks in first; nobody moves to make room for them.
    stage.arrange([member(1, .notYet), member(2, .notYet), member(3, .disclaimer, 1)])
    #expect(stage.placements[id(1)] == .floor(point(103, 626)))
    #expect(stage.placements[id(2)] == .floor(point(287, 626)))
    #expect(stage.placements[id(3)] == .floor(point(149, 556)))

    // A swimmer goes to the water; the others stay put.
    stage.arrange([member(1, .trained(.sport(.swim)), 2), member(2, .notYet), member(3, .disclaimer, 1)])
    #expect(stage.placements[id(1)] == .station(.swimming, slot: 0))
    #expect(stage.placements[id(2)] == .floor(point(287, 626)))
    #expect(stage.placements[id(3)] == .floor(point(149, 556)))
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
    // Three lanes filled in turn, two runners each, half a lap apart; the back lane is faster
    // and the front lane runs the other way.
    #expect(SquadStage.position(on: jogging, slot: 0, at: 0).point == point(-30, 354))
    #expect(SquadStage.position(on: jogging, slot: 1, at: 0).point == point(195, 354))
    #expect(SquadStage.position(on: jogging, slot: 0, at: 2).point == point(82, 354))
    #expect(SquadStage.position(on: jogging, slot: 2, at: 2).point == point(66, 405))
    #expect(SquadStage.position(on: jogging, slot: 4, at: 1).point == point(372, 456))
    #expect(SquadStage.position(on: jogging, slot: 4, at: 1).facing == -1)
    // 318 wide at 34 a second: out for 9.35 seconds, then back.
    #expect(SquadStage.position(on: pool, slot: 0, at: 5).point == point(206, 328))
    #expect(SquadStage.position(on: pool, slot: 0, at: 10).point.x == 354 - (340 - 318))
    #expect(SquadStage.position(on: pool, slot: 0, at: 10).facing == -1)
}

@Test func climbersAreDrawnSmallerToFitTheWall() {
    var stage = SquadStage(layout: .of(.climbing))
    stage.arrange([member(1, .trained(.sport(.climb)), 1)])
    #expect(stage.position(of: id(1), at: 0) == StagePosition(point: point(132, 422), facing: 1, scale: 0.19))
}

@Test func everyoneAwakeWhoIsNotTrainingCheersAndNobodyAtNight() {
    var stage = SquadStage(layout: .of(.pool))
    let people = [
        member(1, .trained(.sport(.swim)), 1), member(2, .notYet), member(3, .disclaimer, 2),
        member(4, .trained(.sport(.run)), 3), member(5, .restDay),
    ]
    stage.arrange(people)
    // Swimmers and the runner keep going.
    #expect(stage.cheerers(people, at: .day) == [id(2), id(3), id(5)])
    #expect(stage.cheerers(people, at: .night) == [])
}

@Test func someoneTrainingOnTheFloorKeepsTheirSpotWhenOthersCheckIn() {
    var stage = SquadStage(layout: .of(.pool))
    stage.arrange([member(1, .notYet), member(2, .notYet), member(3, .trained(.sport(.run)), 5)])
    #expect(stage.placements[id(3)] == .floor(point(103, 626)))
    // The pool has no playing area, so starting to train or a teammate arriving moves nobody.
    stage.arrange([
        member(1, .trained(.sport(.yoga)), 2), member(2, .disclaimer, 3), member(3, .trained(.sport(.run)), 5),
    ])
    #expect(stage.placements[id(1)] == .floor(point(287, 626)))
    #expect(stage.placements[id(2)] == .floor(point(149, 556)))
    #expect(stage.placements[id(3)] == .floor(point(103, 626)))
}

@Test func onlyStartingToTrainMovesSomeoneOntoThePlayingArea() {
    var stage = SquadStage(layout: .of(.climbing))
    let trainers = (1...5).map { member($0, .trained(.sport(.yoga)), Int64($0)) }
    stage.arrange(trainers)
    // Four spots at the foot of the wall; the fifth trains on the floor.
    #expect(stage.placements[id(5)] == .floor(point(103, 626)))

    // A spot on the playing area frees up; the one already training on the floor stays put.
    stage.arrange([member(1, .disclaimer, 1)] + trainers.dropFirst())
    #expect(stage.placements[id(5)] == .floor(point(103, 626)))

    // Someone who starts training now takes it.
    stage.arrange([member(1, .disclaimer, 1)] + trainers.dropFirst() + [member(6, .trained(nil), 6)])
    if case .field = stage.placements[id(6)] {
    } else {
        Issue.record("expected the playing area, got \(String(describing: stage.placements[id(6)]))")
    }
}
