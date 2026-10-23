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
    let run = Activity.sport("run")
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

@Test func everyoneCanStandAnywhereOnTheSceneTheTrackAndTheCourtIncluded() {
    // Rows 70 apart from the front all the way up the track and the court; never the net, the
    // water or the wall, and never right beside me.
    #expect(Set(StageLayout.of(.track).floor.map(\.y)) == [626, 556, 486, 416, 346])
    #expect(Set(StageLayout.of(.tennis).floor.map(\.y)) == [626, 556, 486, 346])
    #expect(Set(StageLayout.of(.pool).floor.map(\.y)) == [626, 556, 486])
    #expect(!StageLayout.of(.track).floor.contains(point(195, 626)))
}

@Test func everySceneHasRoomForTheWholeSquad() {
    for scene in SceneTheme.allCases {
        #expect(StageLayout.of(scene).floor.count >= 7, "\(scene)")
    }
}

@Test func nobodyIsDrawnOverAnotherOrStandsOnALaneSomeoneIsRunning() {
    let sports: [SceneTheme: Sport] = [
        .track: "run", .pool: "swim", .gym: "strength", .tennis: "tennis", .climbing: "climb",
    ]
    for scene in SceneTheme.allCases {
        for trainers in 0...4 {
            var stage = SquadStage(layout: .of(scene))
            stage.arrange(
                (1...7).map { number in
                    number <= trainers
                        ? member(number, .trained(.sport(sports[scene] ?? "run")), Int64(number))
                        : member(number, .notYet, shy: number.isMultiple(of: 2))
                })
            let spots = stage.placements.values.compactMap { placement -> StagePoint? in
                if case .floor(let spot) = placement { spot } else { nil }
            }
            #expect(spots.count == 7 - min(trainers, 7), "\(scene) \(trainers)")
            for (index, spot) in spots.enumerated() {
                for other in spots[(index + 1)...] {
                    #expect(!StageLayout.crowds(spot, other), "\(scene) \(trainers): \(spot) \(other)")
                }
            }
            // Runners fill lane 1 (354), then lane 2 (405); nobody's feet are in their way.
            let lanes = scene == .track ? [354.0, 405].prefix(trainers > 2 ? 2 : trainers > 0 ? 1 : 0) : []
            for spot in spots {
                #expect(!lanes.contains { spot.y > $0 - 46 && spot.y < $0 + 30 }, "\(scene) \(trainers): \(spot)")
            }
        }
    }
}

@Test func theSquadScattersOverTheSceneEarliestCheckInsPickingFirst() {
    var stage = SquadStage(layout: .of(.track))
    stage.arrange([
        member(1, .notYet),
        member(2, .disclaimer, 30),
        member(3, .restDay),
        member(4, .disclaimer, 10),
    ])
    // Each takes the free spot that keeps everyone, me included, well apart: up the track as
    // well as on the floor in front of it.
    #expect(stage.placements[id(4)] == .floor(point(81, 556)))
    #expect(stage.placements[id(2)] == .floor(point(309, 556)))
    #expect(stage.placements[id(1)] == .floor(point(157, 416)))
    #expect(stage.placements[id(3)] == .floor(point(347, 346)))
}

@Test func theShyTakeTheFreeSpotFurthestBack() {
    var stage = SquadStage(layout: .of(.track))
    stage.arrange([member(1, .notYet, shy: true), member(2, .notYet)])
    #expect(stage.placements[id(1)] == .floor(point(195, 346)))
    #expect(stage.placements[id(2)] == .floor(point(81, 556)))
}

@Test func whoeverStandsOnALaneSomeoneStartsRunningStepsOffEveryoneElseStays() {
    var stage = SquadStage(layout: .of(.track))
    let squad = (1...5).map { member($0, .notYet) }
    stage.arrange(squad)
    #expect(stage.placements[id(4)] == .floor(point(347, 346)))
    #expect(stage.placements[id(5)] == .floor(point(43, 346)))

    stage.arrange(squad + [member(6, .trained(.sport("run")), 1)])
    #expect(stage.placements[id(6)] == .station(.jogging, slot: 0))
    #expect(stage.placements[id(1)] == .floor(point(81, 556)))
    #expect(stage.placements[id(2)] == .floor(point(309, 556)))
    #expect(stage.placements[id(3)] == .floor(point(157, 416)))
    #expect(stage.placements[id(4)] == .floor(point(309, 416)))
    #expect(stage.placements[id(5)] == .floor(point(43, 626)))
}

@Test func aMatchingSportUsesTheScenesEquipmentInCheckInOrder() {
    var stage = SquadStage(layout: .of(.gym))
    stage.arrange([
        member(1, .trained(.sport("strength")), 20),
        member(2, .trained(.sport("strength")), 5),
        member(3, .trained(.sport("strength")), 30),
        member(4, .trained(.sport("yoga")), 40),
    ])
    #expect(stage.placements[id(2)] == .station(.squatRack, slot: 0))
    #expect(stage.placements[id(1)] == .station(.squatRack, slot: 1))
    // The racks are full, so the third lifter takes the dumbbells.
    #expect(stage.placements[id(3)] == .station(.dumbbells, slot: 0))
    #expect(stage.placements[id(4)] == .station(.yogaMat, slot: 0))
}

@Test func peopleKeepTheirSpotWhenTheirStatusChanges() {
    var stage = SquadStage(layout: .of(.pool))
    stage.arrange([member(1, .notYet), member(2, .notYet), member(3, .notYet)])
    #expect(stage.placements[id(3)] == .floor(point(195, 486)))

    // Teammate 3 checks in first; nobody moves to make room for them.
    stage.arrange([member(1, .notYet), member(2, .notYet), member(3, .disclaimer, 1)])
    #expect(stage.placements[id(1)] == .floor(point(81, 556)))
    #expect(stage.placements[id(2)] == .floor(point(309, 556)))
    #expect(stage.placements[id(3)] == .floor(point(195, 486)))

    // A swimmer goes to the water; the others stay put.
    stage.arrange([member(1, .trained(.sport("swim")), 2), member(2, .notYet), member(3, .disclaimer, 1)])
    #expect(stage.placements[id(1)] == .station(.swimming, slot: 0))
    #expect(stage.placements[id(2)] == .floor(point(309, 556)))
    #expect(stage.placements[id(3)] == .floor(point(195, 486)))
}

@Test func someoneOnEquipmentKeepsTheirSlotWhenAnEarlierTeammateArrives() {
    var stage = SquadStage(layout: .of(.climbing))
    stage.arrange([member(1, .trained(.sport("climb")), 30)])
    #expect(stage.placements[id(1)] == .station(.topRope, slot: 0))
    stage.arrange([member(1, .trained(.sport("climb")), 30), member(2, .trained(.sport("climb")), 10)])
    #expect(stage.placements[id(1)] == .station(.topRope, slot: 0))
    #expect(stage.placements[id(2)] == .station(.topRope, slot: 1))
}

@Test func posesFollowTheStatusAndAtNightOnlyTrainingStaysAwake() {
    var stage = SquadStage(layout: .of(.tennis))
    let people = [
        member(1, .trained(.sport("tennis")), 1), member(2, .trained(.sport("run")), 2),
        member(3, .disclaimer, 3), member(4, .restDay), member(5, .notYet),
    ]
    stage.arrange(people)
    #expect(
        people.map { stage.pose(of: $0, at: .day) } == [
            .station(.rally), .inPlace(.sport("run")), .holdingSign, .sitting, .standing,
        ])
    #expect(
        people.map { stage.pose(of: $0, at: .night) } == [
            .station(.rally), .inPlace(.sport("run")), .asleep, .asleep, .asleep,
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
    stage.arrange([member(1, .trained(.sport("climb")), 1)])
    #expect(stage.position(of: id(1), at: 0) == StagePosition(point: point(132, 422), facing: 1, scale: 0.19))
}

@Test func everyoneAwakeWhoIsNotTrainingCheersAndNobodyAtNight() {
    var stage = SquadStage(layout: .of(.pool))
    let people = [
        member(1, .trained(.sport("swim")), 1), member(2, .notYet), member(3, .disclaimer, 2),
        member(4, .trained(.sport("run")), 3), member(5, .restDay),
    ]
    stage.arrange(people)
    // Swimmers and the runner keep going.
    #expect(stage.cheerers(people, at: .day) == [id(2), id(3), id(5)])
    #expect(stage.cheerers(people, at: .night) == [])
}
