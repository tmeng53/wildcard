import Foundation
import ScenePickDomain
import Testing

// Every expected value is what the approved prototype's own `render(t)` sets at that moment
// (unbox-prototype/index.html, 2026-10-22), read back by running it in Node against stand-in
// elements, to the precision it writes them.

private func near(_ value: Double?, _ expected: Double, within tolerance: Double = 0.01) -> Bool {
    guard let value else { return false }
    return abs(value - expected) <= tolerance
}

@Test func theCartonLandsWithASquashAndShakesTheScreen() throws {
    let frame = Unboxing(boxed: true).frame(at: 0.7)
    #expect(near(frame.dim, 0.86, within: 0.001))
    #expect(near(frame.shake.x, -0.51) && near(frame.shake.y, 1.55))
    let carton = try #require(frame.carton)
    #expect(near(carton.offsetY, 0, within: 0.05) && near(carton.rotation, 0))
    #expect(near(carton.scaleX, 0.964, within: 0.001) && near(carton.scaleY, 1.048, within: 0.001))
    // The dust: six puffs; the right-most one's frame starts at (217.414, 501.940).
    #expect(frame.dust.count == 6)
    let right = try #require(frame.dust.last)
    #expect(near(right.diameter, 15.413) && near(right.opacity, 0.7, within: 0.001))
    #expect(near(right.center.x - right.diameter / 2, 217.414) && near(right.center.y - right.diameter / 2, 501.940))
}

@Test func itRattlesHopsAndCrouchesBeforeTheBurst() throws {
    let hop = try #require(Unboxing(boxed: true).frame(at: 1.2).carton)
    #expect(near(hop.offsetY, -14, within: 0.05) && near(hop.rotation, 3.80))
    let rattle = try #require(Unboxing(boxed: true).frame(at: 1.3).carton)
    #expect(near(rattle.offsetY, -3.6, within: 0.05) && near(rattle.rotation, 0.82))
    let crouch = try #require(Unboxing(boxed: true).frame(at: 1.6).carton)
    #expect(near(crouch.rotation, -5.66))
    #expect(near(crouch.scaleX, 1.075, within: 0.001) && near(crouch.scaleY, 0.906, within: 0.001))
    #expect(Unboxing(boxed: true).frame(at: 1.3).shake == Point(x: 0, y: 0))
}

@Test func theFlapsFlyInARingOfConfettiAsTheCardRises() throws {
    let frame = Unboxing(boxed: true).frame(at: 1.8)
    let carton = try #require(frame.carton)
    #expect(near(carton.leftFlap.x, -31.1, within: 0.05) && near(carton.leftFlap.y, -116.7, within: 0.05))
    #expect(near(carton.leftFlap.rotation, -101.2, within: 0.05))
    #expect(near(carton.rightFlap.x, 34.2, within: 0.05) && near(carton.rightFlap.y, -132.3, within: 0.05))
    #expect(near(carton.rightFlap.rotation, 109.0, within: 0.05))

    let ring = try #require(frame.ring)
    #expect(near(ring.diameter, 278.166) && near(ring.center.x - ring.diameter / 2, 55.917))
    #expect(near(ring.lineWidth, 7.8, within: 0.05) && near(ring.opacity, 0.72, within: 0.001))

    #expect(frame.confetti.count == 34)
    #expect(near(frame.confetti[0].origin.x, 230.755) && near(frame.confetti[0].origin.y, 368.371))
    #expect(near(frame.confetti[0].rotation, -42) && frame.confetti[0].size == Size(width: 8, height: 8))
    #expect(near(frame.confetti[1].origin.x, 228.009) && near(frame.confetti[1].origin.y, 342.868))
    #expect(near(frame.confetti[1].rotation, 141.8) && frame.confetti[1].cornerRadius == 1.5)
    #expect(frame.confetti[6].color == .picked && frame.confetti[1].color == .signature(.pool))

    let card = try #require(frame.card)
    #expect(card.frame == Rect(x: 120, y: card.frame.y, width: 150, height: 220))
    #expect(near(card.frame.y, 318.326) && card.cornerRadius == 18)
    #expect(near(card.opacity, 0.893, within: 0.001) && near(card.scale, 0.585, within: 0.001))
    #expect(near(card.rotation, -7.21) && near(card.border, 4.0, within: 0.05))
}

@Test func theCardGrowsToFillTheScreen() throws {
    let growing = try #require(Unboxing(boxed: true).frame(at: 2.4).card)
    #expect(near(growing.frame.x, 116.16) && near(growing.frame.y, 212.96))
    #expect(near(growing.frame.width, 157.68) && near(growing.frame.height, 239.968))
    #expect(near(growing.cornerRadius, 17.424) && near(growing.scale, 1, within: 0.001))
    #expect(near(growing.rotation, -2.90) && near(growing.border, 3.9, within: 0.05))

    let reveal = Unboxing(boxed: true)
    let full = try #require(reveal.frame(at: reveal.covered).card)
    #expect(full.frame == Rect(x: 0, y: 0, width: 390, height: 844))
    #expect(full.cornerRadius == 0 && full.scale == 1 && full.rotation == 0 && full.border == 0)
    // The carton has sunk away; the last confetti fades out over the home.
    #expect(reveal.frame(at: 2.7).carton == nil)
    let fading = reveal.frame(at: 2.8).confetti
    #expect(near(fading.first?.opacity, 0.533, within: 0.001))
    #expect(near(fading.first?.origin.x, 486.150) && near(fading.first?.origin.y, 985.252))
    #expect(reveal.frame(at: reveal.finished + 0.01).confetti.isEmpty)
    #expect(near(reveal.finished, 2.96, within: 1e-9) && near(reveal.covered, 2.8, within: 1e-9))
}

@Test func aSceneTheSquadKnowsRisesAtOnceWithoutACarton() throws {
    let reveal = Unboxing(boxed: false)
    let frame = reveal.frame(at: 0.4)
    #expect(frame.carton == nil && frame.ring == nil && frame.confetti.isEmpty && frame.dust.isEmpty)
    #expect(frame.shake == Point(x: 0, y: 0))
    let card = try #require(frame.card)
    #expect(near(card.frame.y, 220.192) && near(card.scale, 1.013, within: 0.001) && near(card.rotation, -3.01))
    let almost = try #require(reveal.frame(at: 1.0).card)
    #expect(near(almost.frame.x, 0.48) && near(almost.frame.height, 841.504) && near(almost.rotation, -0.01))
    #expect(near(reveal.covered, 1.05, within: 1e-9) && reveal.finished == reveal.covered)
    // Nothing shows before it starts rising: the card's first frame is at 0.
    #expect(Unboxing(boxed: true).frame(at: 1.7).card == nil)
}
