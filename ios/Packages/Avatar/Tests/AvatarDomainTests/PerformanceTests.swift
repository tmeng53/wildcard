import AvatarDomain
import Testing

/// Idle holds the arm at 0°; the cheer swings it from 0° to 100° over one second.
private func setUp() throws -> (Figure, BoundClip, BoundClip) {
    let figure = try figure()
    let idle = try figure.bind(clip("idle", duration: 2, loops: true, [track("arm", .rotation, [(0, 0)])]))
    let cheer = try figure.bind(
        clip("cheer", duration: 1, loops: false, [track("arm", .rotation, [(0, 0), (1, 100)])]))
    return (figure, idle, cheer)
}

@Test func aOneShotClipHandsBackToIdle() throws {
    let (figure, idle, cheer) = try setUp()
    var performance = Performance(figure: figure, idle: idle, startingAt: 0, blendDuration: 0.2)
    performance.play(cheer, at: 10)
    #expect(performance.clipName(at: 10.5) == "cheer")
    #expect(performance.pose(at: 10.5).parts[1].rotation == 50)
    #expect(performance.clipName(at: 11) == "idle")
    // Halfway through the blend back, smoothstep is exactly halfway too.
    #expect(abs(performance.pose(at: 11.1).parts[1].rotation - 50) < 1e-9)
    #expect(performance.pose(at: 11.2).parts[1].rotation == 0)
}

/// Standing still (Reduce Motion) holds the idle's first frame, whatever plays on top: an idle
/// that starts with the arm at 30° stands with it at 30°, not at rest.
@Test func standingStillHoldsTheIdlesFirstFrame() throws {
    let (figure, _, cheer) = try setUp()
    let raised = try figure.bind(clip("idle", duration: 2, loops: true, [track("arm", .rotation, [(0, 30), (2, 30)])]))
    var performance = Performance(figure: figure, idle: raised)
    performance.play(cheer, at: 1)
    #expect(performance.stillPose.parts[1].rotation == 30)
    #expect(figure.restPose.parts[1].rotation == 0)
}

/// Mid-change, standing still already shows where the change ends up: the new outfit's idle.
@Test func standingStillMidChangeHoldsTheNewIdlesFirstFrame() throws {
    let (figure, idle, cheer) = try setUp()
    var performance = Performance(figure: figure, idle: idle)
    let dressed = try AvatarDomainTests.figure(Outfit(["top": "tee"]))
    let raised = try dressed.bind(
        clip("idle", duration: 2, loops: true, [track("arm", .rotation, [(0, 30), (2, 30)])]))
    performance.change(into: dressed, idle: raised, leaving: cheer, arriving: try dressed.bind(cheer.clip), at: 1)
    #expect(performance.stillPose.parts[1].rotation == 30)
    #expect(performance.stillPose.parts.count == dressed.parts.count)
}

@Test func changesBlendFromWhatIsOnScreen() throws {
    let (figure, idle, cheer) = try setUp()
    var performance = Performance(figure: figure, idle: idle, blendDuration: 0.2)
    performance.play(cheer, at: 1)
    // Cheering again mid-cheer starts from the arm's current 50°, not from rest.
    performance.play(cheer, at: 1.5)
    #expect(performance.pose(at: 1.5).parts[1].rotation == 50)
    // 0.1 s in: the new cheer is at 10°, halfway blended from 50°.
    #expect(abs(performance.pose(at: 1.6).parts[1].rotation - 30) < 1e-9)
    #expect(abs(performance.pose(at: 1.7).parts[1].rotation - 20) < 1e-9)
}

@Test func aNewOutfitCarriesOnFromThePoseOnScreen() throws {
    let (figure, idle, cheer) = try setUp()
    var performance = Performance(figure: figure, idle: idle, blendDuration: 0.2)
    performance.play(cheer, at: 1)
    // Dressed mid-cheer, with the arm at 50°: the new idle blends down from there.
    let dressed = try AvatarDomainTests.figure(Outfit(["top": "tee"]))
    let restyled = Performance(continuing: performance, figure: dressed, idle: try dressed.bind(idle.clip), at: 1.5)
    #expect(restyled.figure == dressed)
    #expect(restyled.pose(at: 1.5).parts[1].rotation == 50)
    #expect(abs(restyled.pose(at: 1.6).parts[1].rotation - 25) < 1e-9)
    #expect(restyled.pose(at: 1.7).parts[1].rotation == 0)
}

@Test func aClipCanCutInWithoutBlending() throws {
    let (figure, idle, cheer) = try setUp()
    var performance = Performance(figure: figure, idle: idle, blendDuration: 0.2)
    performance.play(cheer, at: 1)
    // Mid-cheer at 50°: cutting to a fresh cheer starts it at 0°, where blending would hold 50°.
    performance.play(cheer, at: 1.5, blending: false)
    #expect(performance.pose(at: 1.5).parts[1].rotation == 0)
    #expect(abs(performance.pose(at: 1.6).parts[1].rotation - 10) < 1e-9)
}

@Test func standingStillHoldsTheRestPose() throws {
    let figure = try figure()
    let performance = Performance(figure: figure, idle: try figure.bind(.still))
    #expect(performance.pose(at: 0.4) == figure.restPose)
    #expect(performance.pose(at: 7.3) == figure.restPose)
}

/// Picking a sport: the arm goes out to 30° in the old clothes, the tee goes on at the end of
/// that, the way back plays from 30° to 0°, then the sport's move loops in the tee.
@Test func aChangeOfClothesSwapsTheFigureMidHop() throws {
    let (figure, idle, _) = try setUp()
    let dressed = try AvatarDomainTests.figure(Outfit(["top": "tee"]))
    let out = try figure.bind(
        clip("hopOut", duration: 0.2, loops: false, [track("arm", .rotation, [(0, 0), (0.2, 30)])]))
    let back = try dressed.bind(
        clip("hopIn", duration: 0.4, loops: false, [track("arm", .rotation, [(0, 30), (0.4, 0)])]))
    let move = try dressed.bind(
        clip("move", duration: 1, loops: true, [track("arm", .rotation, [(0, 0), (0.5, -60), (1, 0)])]))
    var performance = Performance(figure: figure, idle: idle, blendDuration: 0)
    performance.change(into: dressed, idle: move, leaving: out, arriving: back, at: 1)
    #expect(performance.figure(at: 1.1) == figure)
    #expect(performance.clipName(at: 1.1) == "hopOut")
    #expect(abs(performance.pose(at: 1.1).parts[1].rotation - 15) < 1e-9)
    #expect(performance.figure(at: 1.2) == dressed)
    #expect(performance.clipName(at: 1.3) == "hopIn")
    #expect(abs(performance.pose(at: 1.4).parts[1].rotation - 15) < 1e-9)
    #expect(performance.clipName(at: 1.7) == "move")
    #expect(abs(performance.pose(at: 2.1).parts[1].rotation - -60) < 1e-9)
    // The figure it started in stays what `figure` names; later plays carry on in the tee.
    #expect(performance.figure == figure)
    performance.play(idle, at: 3)
    #expect(performance.figure == dressed)
}

/// With a blend longer than the squash, the pop up carries on from the pose on screen at the
/// swap instead of snapping to its own first frame.
@Test func theHopBlendsAcrossTheSwap() throws {
    let (figure, idle, cheer) = try setUp()
    let dressed = try AvatarDomainTests.figure(Outfit(["top": "tee"]))
    let out = try figure.bind(
        clip("hopOut", duration: 0.1, loops: false, [track("arm", .rotation, [(0, 0), (0.1, 0)])]))
    let back = try dressed.bind(
        clip("hopIn", duration: 0.4, loops: false, [track("arm", .rotation, [(0, 0), (0.4, 0)])]))
    var performance = Performance(figure: figure, idle: idle, blendDuration: 0.2)
    performance.play(cheer, at: 0)
    // Mid-cheer at 50°, the squash starts blending down to 0° but has 0.1 s of a 0.2 s blend.
    performance.change(into: dressed, idle: idle, leaving: out, arriving: back, at: 0.5)
    let before = performance.pose(at: 0.6 - 1e-6).parts[1].rotation
    #expect(abs(before - 25) < 1e-3)
    #expect(abs(performance.pose(at: 0.6).parts[1].rotation - 25) < 1e-9)
    #expect(performance.pose(at: 0.8).parts[1].rotation == 0)
}

/// Blends take the short way round: an arm at 340° swings on 20° to 360°, the same as 0°.
@Test func rotationsBlendTheShortWay() {
    var start = Pose(parts: [PartPose()])
    start.parts[0].rotation = 340
    let halfway = start.blended(to: Pose(parts: [PartPose()]), amount: 0.5)
    #expect(abs(halfway.parts[0].rotation - -10) < 1e-9)
}

/// A clip played mid-hop stops the change: the character stays in the clothes on screen.
@Test func playingMidHopKeepsTheClothesOnScreen() throws {
    let (figure, idle, cheer) = try setUp()
    let dressed = try AvatarDomainTests.figure(Outfit(["top": "tee"]))
    let out = try figure.bind(
        clip("hopOut", duration: 0.2, loops: false, [track("arm", .rotation, [(0, 0), (0.2, 30)])]))
    var performance = Performance(figure: figure, idle: idle, blendDuration: 0)
    performance.change(into: dressed, idle: idle, leaving: out, arriving: out, at: 1)
    performance.play(cheer, at: 1.1)
    #expect(performance.figure(at: 5) == figure)
    #expect(performance.clipName(at: 1.5) == "cheer")
}
