import AvatarDomain
import Foundation
import Testing

/// An arm hanging straight down from the shoulder at (60, 40), its elbow at (60, 60) and its
/// hand at (60, 80).
private let elbow = Rig.Elbow(point: Point(x: 60, y: 60), hand: Point(x: 60, y: 80))

private func bend(_ degrees: Double) -> Bend {
    Bend(shoulder: Point(x: 60, y: 40), elbow: elbow, degrees: degrees)
}

@Test func theUpperArmStaysAndTheForearmTurnsAtTheElbow() {
    // Bent 90° clockwise: the hand swings from below the elbow to its left.
    #expect(rounded(bend(90).apply(to: Point(x: 60, y: 40))) == Point(x: 60, y: 40))
    #expect(rounded(bend(90).apply(to: Point(x: 60, y: 80))) == Point(x: 40, y: 60))
    // A short sleeve's hem, a little above the elbow, stays put.
    #expect(rounded(bend(90).apply(to: Point(x: 64, y: 52))) == Point(x: 64, y: 52))
    // Just past the elbow the arm turns only partway, so it curves rather than folds.
    let partway = bend(90).apply(to: Point(x: 60, y: 66))
    let turned = atan2(60 - partway.x, partway.y - 60) * 180 / .pi
    #expect(turned > 0 && turned < 90)
}

/// The arm's line is one curve through the elbow; bent, it still passes through the elbow
/// and ends at the turned hand, as one soft arm.
@Test func aCurveStaysSmoothThroughTheElbow() {
    let arm: [PathElement] = [
        .move(Point(x: 60, y: 40)), .quadCurve(end: Point(x: 60, y: 80), control: Point(x: 60, y: 60)),
    ]
    let bent = bend(90).apply(to: arm)
    guard case .quadCurve(let end, let control) = bent[1] else {
        Issue.record("expected a curve")
        return
    }
    #expect(rounded(end) == Point(x: 40, y: 60))
    // Through the elbow halfway: 2·elbow − (shoulder + hand) / 2.
    #expect(rounded(control) == Point(x: 70, y: 70))
    #expect(bend(0).apply(to: arm) == arm)
}

/// The hand, wholly past the elbow, turns as one piece: its curves keep their shape.
@Test func artPastTheElbowTurnsWhole() {
    let knuckle: [PathElement] = [
        .move(Point(x: 56, y: 80)),
        .curve(end: Point(x: 64, y: 80), control1: Point(x: 56, y: 85), control2: Point(x: 64, y: 85)),
        .close,
    ]
    let turned = bend(90).forearm
    let expected: [PathElement] = [
        .move(rounded(turned.apply(to: Point(x: 56, y: 80)))),
        .curve(
            end: rounded(turned.apply(to: Point(x: 64, y: 80))),
            control1: rounded(turned.apply(to: Point(x: 56, y: 85))),
            control2: rounded(turned.apply(to: Point(x: 64, y: 85)))),
        .close,
    ]
    #expect(bend(90).apply(to: knuckle).map(roundedElement) == expected)
}

private func roundedElement(_ element: PathElement) -> PathElement {
    switch element {
    case .move(let point): .move(rounded(point))
    case .line(let point): .line(rounded(point))
    case .quadCurve(let end, let control): .quadCurve(end: rounded(end), control: rounded(control))
    case .curve(let end, let first, let second):
        .curve(end: rounded(end), control1: rounded(first), control2: rounded(second))
    case .close: .close
    }
}

/// The fixture figure with an elbow on its arm and a prop in its hand.
private func elbowed() throws -> Figure {
    var bendy = rig
    bendy.parts[1].elbow = elbow
    bendy.parts.append(Rig.Part(id: "prop", parent: "arm", pivot: Point(x: 60, y: 80)))
    return try Figure(rig: bendy, outfit: Outfit([:]), art: art)
}

@Test func whatTheHandHoldsMovesWithTheForearm() throws {
    let figure = try elbowed()
    var pose = figure.restPose
    pose.parts[1].bend = 90
    let placements = figure.layout(pose)
    #expect(placements[1].bend == bend(90))
    #expect(placements[0].bend == nil)
    #expect(rounded(placements[2].transform.apply(to: Point(x: 60, y: 80))) == Point(x: 40, y: 60))
    // Unbent, nothing is bent.
    #expect(figure.layout(figure.restPose).allSatisfy { $0.bend == nil })
}

/// A swing the clip doesn't bend trails: the forearm lags while the arm moves, straightens
/// once it stops, and what it holds keeps the angle the clip gave it.
@Test func aSwingingArmFollowsThrough() throws {
    let figure = try elbowed()
    let swing = try figure.bind(
        clip("swing", duration: 2, loops: false, [track("arm", .rotation, [(0, 0), (0.5, 60), (2, 60)])]))
    // Mid-swing at 120°/s, 0.09 s behind: 0.9 × −10.8° = −9.72°.
    let moving = figure.pose(swing, at: 0.25)
    #expect((moving.parts[1].bend * 100).rounded() / 100 == -9.72)
    #expect((moving.parts[2].rotation * 100).rounded() / 100 == 9.72)
    #expect(figure.pose(swing, at: 1).parts[1].bend == 0)
    #expect(figure.pose(swing, at: 0).parts[1].bend == 0)
    // A fast swing bends no further than 35°.
    let fast = try figure.bind(
        clip("fast", duration: 1, loops: false, [track("arm", .rotation, [(0, 0), (0.1, 180), (1, 180)])]))
    #expect(figure.pose(fast, at: 0.1).parts[1].bend == -35)
}

/// A clip that bends the elbow itself, as a boxer's guard does, gets just what it asks.
@Test func aClipBendsTheElbowItself() throws {
    let figure = try elbowed()
    let guardUp = try figure.bind(
        clip(
            "guard", duration: 1, loops: false,
            [track("arm", .rotation, [(0, 0), (1, 90)]), track("arm", .bend, [(0, 0), (1, -120)])]))
    #expect(figure.pose(guardUp, at: 0.5).parts[1].bend == -60)
    #expect(figure.pose(guardUp, at: 0.5).parts[2].rotation == 0)
    let stiff = try clip("stiff", duration: 1, loops: false, [track("body", .bend, [(0, 0), (1, 10)])])
    #expect(throws: AvatarError.noElbow(clip: "stiff", part: "body")) { try figure.bind(stiff) }
}
