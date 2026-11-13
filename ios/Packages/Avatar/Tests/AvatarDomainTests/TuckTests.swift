import AvatarDomain
import Testing

/// The placeholder's left arm: its pivot on the body, and its sleeve's seam from the top of
/// the shoulder to the armpit.
private let pivot = Point(x: 92.4, y: 222)
private let seam = Rig.Seam(top: Point(x: 84.98, y: 211.76), armpit: Point(x: 96.3, y: 236))

@Test func anArmIsDrawnOverItsBodyOnlyInFrontOfItsSeam() throws {
    let tuck = try #require(Tuck(pivot: pivot, seam: seam))
    // Out on the arm, past the seam.
    #expect(tuck.seam.keeps(Point(x: 70, y: 230)))
    #expect(!tuck.under.keeps(Point(x: 70, y: 230)))
    // The round about the pivot, on the chest, lies under the body.
    #expect(!tuck.seam.keeps(pivot))
    #expect(tuck.under.keeps(pivot))
    #expect(!tuck.seam.keeps(Point(x: 100, y: 222)))
    #expect(tuck.under.keeps(Point(x: 100, y: 222)))
}

@Test func theTwoPiecesLapAtTheSeam() throws {
    let tuck = try #require(Tuck(pivot: pivot, seam: seam))
    // On the seam both are drawn, so no hairline shows between them.
    #expect(tuck.seam.keeps(seam.top) && tuck.under.keeps(seam.top))
    #expect(tuck.seam.keeps(seam.armpit) && tuck.under.keeps(seam.armpit))
    // A point's width in front of the seam, only the piece over the body.
    #expect(!tuck.under.keeps(Point(x: 84.07, y: 212.18)))
}

@Test func aSeamWithNoLengthHasNoTuck() {
    #expect(Tuck(pivot: pivot, seam: Rig.Seam(top: seam.top, armpit: seam.top)) == nil)
}
