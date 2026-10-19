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

@Test func standingStillHoldsTheRestPose() throws {
    let figure = try figure()
    let performance = Performance(figure: figure, idle: try figure.bind(.still))
    #expect(performance.pose(at: 0.4) == figure.restPose)
    #expect(performance.pose(at: 7.3) == figure.restPose)
}
