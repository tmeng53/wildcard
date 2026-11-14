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

@Test func nightIsFromElevenAtNightToSixInTheMorning() {
    #expect(DayPhase(hour: 5) == .night)
    #expect(DayPhase(hour: 6) == .day)
    #expect(DayPhase(hour: 19) == .day)
    #expect(DayPhase(hour: 22) == .day)
    #expect(DayPhase(hour: 23) == .night)
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
    // On the track, each row stands in the middle of the lane it falls in, never on a line.
    #expect(Set(StageLayout.of(.track).floor.map(\.y)) == [626, 556, 488.5, 437.5, 335.5])
    #expect(Set(StageLayout.of(.tennis).floor.map(\.y)) == [626, 556, 486, 346])
    #expect(Set(StageLayout.of(.pool).floor.map(\.y)) == [626, 556, 486])
    #expect(!StageLayout.of(.track).floor.contains(point(195, 626)))
}

@Test func nobodyOnTheTrackStandsOnALaneLine() {
    // Feet and the ring around them (about 11 points either side at the front) clear every line.
    let feet =
        StageLayout.of(.track).floor.map(\.y)
        + StageLayout.of(.track).stations.flatMap { station in
            (0..<station.capacity).compactMap { station.lane(ofSlot: $0)?.y }
        }
    for y in feet {
        #expect(StageLayout.trackLines.allSatisfy { abs($0 - y) >= 20 }, "\(y)")
    }
}

@Test func everyoneIsDrawnWholeOnTheScreenAtEveryMoment() {
    for scene in SceneTheme.allCases {
        let layout = StageLayout.of(scene)
        for spot in layout.floor {
            #expect(StageLayout.fitsOnScreen(spot, scale: StageLayout.scale(atDepth: spot.y)), "\(scene) \(spot)")
        }
        for station in layout.stations {
            for slot in 0..<station.capacity {
                for second in stride(from: 0.0, through: 30, by: 0.25) {
                    let position = SquadStage.position(on: station, slot: slot, at: second)
                    #expect(
                        StageLayout.fitsOnScreen(position.point, scale: position.scale),
                        "\(scene) \(station.kind) \(slot) \(second)")
                }
            }
        }
    }
    // Me, front and centre.
    #expect(StageLayout.fitsOnScreen(StageLayout.mySpot, scale: StageLayout.myScale))
}

@Test func everySceneHasRoomForTheWholeSquad() {
    for scene in SceneTheme.allCases {
        #expect(StageLayout.of(scene).floor.count >= 7, "\(scene)")
    }
}

@Test func nobodyIsDrawnOverAnotherOrStandsOnALaneSomeoneIsRunning() {
    let sports: [SceneTheme: Sport] = [
        .track: "run", .pool: "swim", .gym: "strength", .tennis: "tennis", .climbing: "climb", .ski: "ski",
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
            // Nobody's feet are in the way of a lane someone runs or swims.
            let lanes = stage.placements.values.compactMap { placement -> Double? in
                guard case .station(let kind, let slot) = placement else { return nil }
                return stage.layout.station(kind)?.lane(ofSlot: slot)?.y
            }
            #expect(scene != .track || lanes.count == min(trainers, 7), "\(scene) \(trainers)")
            for spot in spots {
                #expect(!lanes.contains { spot.y > $0 - 46 && spot.y < $0 + 30 }, "\(scene) \(trainers): \(spot)")
            }
        }
    }
}

@Test func everyonesWholeBodyShowsAboveTheHeadsInFront() {
    // Tracy, 2026-11-14: on the snowfield the back row stood half a body behind the front one and
    // showed only their heads.
    for scene in SceneTheme.allCases {
        for coach in [false, true] {
            var stage = SquadStage(layout: .of(scene))
            stage.arrange((1...7).map { member($0, .notYet) }, coach: coach)
            var figures = stage.placements.values.compactMap { placement -> StageRect? in
                guard case .floor(let spot) = placement else { return nil }
                return StageLayout.figure(at: spot, scale: StageLayout.scale(atDepth: spot.y))
            }
            #expect(figures.count == 7, "\(scene) coach: \(coach)")
            // The coach keeps them clear of itself only while there is room, which
            // nobodyStandsUnderTheCoachsBubbleOrBehindItWhileThereIsRoom covers.
            figures.append(StageLayout.figure(at: StageLayout.mySpot, scale: StageLayout.myScale))
            for front in figures {
                for back in figures where back.maxY < front.maxY && back.minX < front.maxX && front.minX < back.maxX {
                    // The feet behind are no lower than the top of the head in front, give or take.
                    #expect(back.maxY <= front.minY + 2, "\(scene) coach: \(coach): \(back) behind \(front)")
                }
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
    #expect(stage.placements[id(1)] == .floor(point(195, 335.5)))
    #expect(stage.placements[id(3)] == .floor(point(81, 437.5)))
}

@Test func peopleStandingRightOfMeAreNotMirrored() {
    var stage = SquadStage(layout: .of(.track))
    stage.arrange([member(1, .disclaimer, 30), member(2, .disclaimer, 10)])
    // Drawn as on their player card, so a prop stays in the same hand on both.
    let positions = [id(1), id(2)].compactMap { stage.position(of: $0, at: 0) }
    #expect(positions.map(\.point.x).contains { $0 > StageLayout.mySpot.x })
    #expect(positions.map(\.facing) == [1, 1])
}

@Test func theShyTakeTheFreeSpotFurthestBack() {
    var stage = SquadStage(layout: .of(.track))
    stage.arrange([member(1, .notYet, shy: true), member(2, .notYet)])
    #expect(stage.placements[id(1)] == .floor(point(195, 335.5)))
    #expect(stage.placements[id(2)] == .floor(point(81, 556)))
}

@Test func whoeverStandsOnALaneSomeoneStartsRunningStepsOffEveryoneElseStays() {
    var stage = SquadStage(layout: .of(.track))
    let squad = (1...5).map { member($0, .notYet) }
    stage.arrange(squad)
    #expect(stage.placements[id(3)] == .floor(point(195, 335.5)))

    // The first runner takes lane 1, so whoever stood in it steps off.
    stage.arrange(squad + [member(6, .trained(.sport("run")), 1)])
    #expect(stage.placements[id(6)] == .station(.jogging, slot: 0))
    #expect(stage.placements[id(1)] == .floor(point(81, 556)))
    #expect(stage.placements[id(2)] == .floor(point(309, 556)))
    #expect(stage.placements[id(3)] == .floor(point(195, 488.5)))
    #expect(stage.placements[id(4)] == .floor(point(81, 437.5)))
    #expect(stage.placements[id(5)] == .floor(point(309, 437.5)))
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

@Test func runnersAndSwimmersGoBackAndForthTurningBeforeTheEdge() {
    let track = StageLayout.of(.track)
    guard let jogging = track.stations.first(where: { $0.kind == .jogging }),
        let pool = StageLayout.of(.pool).stations.first
    else {
        Issue.record("missing stations")
        return
    }
    // One runner per lane in turn, in the middle of lanes 1 to 3; 310 wide at 52 a second, so
    // out for under 6 seconds, then back, turning before the screen's edge.
    #expect(SquadStage.position(on: jogging, slot: 0, at: 0).point == point(40, 335.5))
    #expect(SquadStage.position(on: jogging, slot: 0, at: 2).point == point(144, 335.5))
    #expect(SquadStage.position(on: jogging, slot: 0, at: 7).point == point(350 - (364 - 310), 335.5))
    #expect(SquadStage.position(on: jogging, slot: 0, at: 7).facing == -1)
    #expect(SquadStage.position(on: jogging, slot: 2, at: 0).point.y == 437.5)
    // 310 wide at 34 a second: out for 9.1 seconds, then back.
    #expect(SquadStage.position(on: pool, slot: 0, at: 5).point == point(210, 328))
    #expect(SquadStage.position(on: pool, slot: 0, at: 10).point.x == 350 - (340 - 310))
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

@Test func theCoachStandsOnTheFrontRowsLeftEdgeAsBigAsMe() {
    #expect(StageLayout.coachScale == StageLayout.myScale)
    for scene in [SceneTheme.gym, .pool, .track, .tennis, .climbing] {
        let sideline = StageLayout.of(scene).sideline
        // The front row's leftmost spot (43, 626), moved in just enough to draw the coach whole.
        #expect(sideline?.y == 626)
        #expect(sideline.map { abs($0.x - 48.8) < 0.001 } == true)
        #expect(sideline.map { StageLayout.fitsOnScreen($0, scale: StageLayout.coachScale) } == true)
    }
}

@Test func teammatesLeaveTheSidelineToTheCoach() {
    let squad = (1...7).map { member($0, .notYet) }
    var stage = SquadStage(layout: .of(.gym))
    stage.arrange(squad, coach: true)
    let spots = floorSpots(stage)
    #expect(spots.count == 7)
    #expect(!spots.contains(StagePoint(x: 43, y: 626)))
    // Without a coach, a squad this big uses it.
    stage = SquadStage(layout: .of(.gym))
    stage.arrange(squad)
    #expect(stage.placements.values.contains(.floor(StagePoint(x: 43, y: 626))))
}

@Test func nobodyStandsUnderTheCoachsBubbleOrBehindItWhileThereIsRoom() {
    let layout = StageLayout.of(.gym)
    // Just behind the coach, where its 战术板 bubble hid a teammate (beta feedback).
    #expect(layout.coachCovers(StagePoint(x: 80, y: 549)))
    #expect(!layout.coachCovers(StagePoint(x: 300, y: 549)))
    for scene in [SceneTheme.gym, .pool, .track, .tennis, .climbing] {
        var stage = SquadStage(layout: .of(scene))
        stage.arrange((1...4).map { member($0, .notYet) }, coach: true)
        let spots = floorSpots(stage)
        #expect(spots.count == 4)
        #expect(!spots.contains { StageLayout.of(scene).coachCovers($0) }, "\(scene): \(spots)")
    }
}

@Test func aBigSquadStillAllStandsOnTheSceneWithACoach() {
    for scene in [SceneTheme.gym, .pool, .track, .tennis, .climbing] {
        var stage = SquadStage(layout: .of(scene))
        stage.arrange((1...7).map { member($0, .notYet) }, coach: true)
        #expect(stage.placements.count == 7, "\(scene)")
    }
}

private func floorSpots(_ stage: SquadStage) -> [StagePoint] {
    stage.placements.values.compactMap { placement -> StagePoint? in
        if case .floor(let spot) = placement { spot } else { nil }
    }
}

@Test func someoneEatingTheirLatestPostEatsOnTheFloorAndSleepsAtNight() {
    var stage = SquadStage(layout: .of(.track))
    let ranThenAte = StageMember(
        id: id(1), status: .trained(.sport("run")), firstCheckInAt: at(1), keepsToTheBack: false, eating: .healthyMeal)
    let ate = StageMember(id: id(2), status: .notYet, firstCheckInAt: at(2), keepsToTheBack: false, eating: .cheatMeal)
    stage.arrange([ranThenAte, ate])
    // Off the track: eating, not running.
    #expect(stage.placements[id(1)].map { if case .floor = $0 { true } else { false } } == true)
    #expect(stage.pose(of: ranThenAte, at: .day) == .eating(.healthyMeal))
    #expect(stage.pose(of: ate, at: .day) == .eating(.cheatMeal))
    #expect(stage.pose(of: ate, at: .night) == .asleep)
    #expect(stage.cheerers([ranThenAte, ate], at: .day) == [id(1), id(2)])
}
