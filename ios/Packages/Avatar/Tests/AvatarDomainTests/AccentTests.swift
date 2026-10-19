import AvatarDomain
import Testing

/// Idle holds the arm at 10°; the accent waves it 20° further and back over two seconds.
private func setUp(tempo: Double = 1, strength: Double = 1) throws -> (Figure, BoundClip) {
    let figure = try figure()
    let idle = try clip("idle", duration: 3, loops: true, [track("arm", .rotation, [(0, 10)])])
    let wave = try clip("wave", duration: 2, loops: true, [track("arm", .rotation, [(0, 0), (1, 20), (2, 0)])])
    return (figure, try figure.bind(idle.accented(by: wave, tempo: tempo, strength: strength)))
}

@Test func anAccentAddsToTheClipBelowAndLoopsOnItsOwnDuration() throws {
    let (figure, idle) = try setUp()
    #expect(figure.pose(idle, at: 0).parts[1].rotation == 10)
    #expect(figure.pose(idle, at: 1).parts[1].rotation == 30)
    // The idle loops every 3 s and the accent every 2 s: at 5 s the accent is 1 s in again.
    #expect(figure.pose(idle, at: 5).parts[1].rotation == 30)
}

@Test func tempoAndStrengthChangeHowFastAndFarAnAccentMoves() throws {
    let (figure, idle) = try setUp(tempo: 2, strength: 0.5)
    #expect(figure.pose(idle, at: 0.5).parts[1].rotation == 20)
    #expect(figure.pose(idle, at: 1).parts[1].rotation == 10)
}

@Test func accentsMultiplyScalesAndKeepOpacityInRange() throws {
    let figure = try figure()
    let idle = try clip("idle", duration: 1, loops: true, [track("arm", .scaleY, [(0, 0.5)])])
    let blink = try clip(
        "blink", duration: 1, loops: true,
        [track("arm", .scaleY, [(0, 1), (0.5, 0.2), (1, 1)]), track("arm", .opacity, [(0, 0), (0.5, 1), (1, 0)])])
    let pose = figure.pose(try figure.bind(idle.accented(by: blink, strength: 2)), at: 0.5)
    // 0.5 × (1 + (0.2 − 1) × 2) would be negative; a scale stops at zero.
    #expect(pose.parts[1].scaleY == 0)
    // Opacity adds without strength and stays within 0...1.
    #expect(pose.parts[1].opacity == 1)
    let gentle = figure.pose(try figure.bind(idle.accented(by: blink, strength: 0.5)), at: 0.5)
    #expect(abs(gentle.parts[1].scaleY - 0.3) < 1e-9)
}

@Test func aOneShotAccentStretchesOverItsClip() throws {
    let figure = try figure()
    let cheer = try clip("cheer", duration: 1, loops: false, [track("arm", .rotation, [(0, 0), (1, 100)])])
    let wiggle = try clip("wiggle", duration: 2, loops: false, [track("arm", .x, [(0, 0), (1, 6), (2, 0)])])
    let bound = try figure.bind(cheer.accented(by: wiggle, tempo: 3))
    #expect(figure.pose(bound, at: 0.5).parts[1].x == 6)
    #expect(figure.pose(bound, at: 0.5).parts[1].rotation == 50)
    #expect(figure.pose(bound, at: 1).parts[1].x == 0)
}

@Test func rejectsAccentsThatWouldJump() throws {
    let idle = try clip("idle", duration: 1, loops: true, [])
    let once = try clip("once", duration: 1, loops: false, [])
    #expect(throws: AvatarError.accentMismatch(clip: "idle", accent: "once")) { try idle.accented(by: once) }
    #expect(throws: AvatarError.invalidAccent(clip: "idle", accent: "idle")) { try idle.accented(by: idle, tempo: 0) }
    let tilted = try clip("tilt", duration: 1, loops: true, [track("arm", .rotation, [(0, 0), (1, 5)])])
    #expect(throws: AvatarError.accentNotAtRest(accent: "tilt", part: "arm", channel: .rotation)) {
        try idle.accented(by: tilted)
    }
    let late = try clip("late", duration: 1, loops: true, [track("arm", .scaleX, [(0.2, 1), (1, 1)])])
    #expect(throws: AvatarError.accentNotAtRest(accent: "late", part: "arm", channel: .scaleX)) {
        try idle.accented(by: late)
    }
    let stray = try clip("stray", duration: 1, loops: true, [track("tail", .x, [(0, 0), (1, 0)])])
    #expect(throws: AvatarError.unknownPart(clip: "stray", part: "tail")) {
        try figure().bind(idle.accented(by: stray))
    }
}
