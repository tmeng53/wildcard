import AvatarArt
import AvatarDomain
import Testing

/// A bichon's whole chin fluff (`chin`) sits behind the arms, so a raised arm stays in front of it;
/// its two halves (`chinFrontL`, `chinFrontR`) sit over the arms and each fades out as its own arm
/// rises, so the fluff covers the shoulders of hanging arms only. Only the bichon has any of them.
@Test func aBichonsChinGivesWayToARaisedArm() throws {
    for body in try PlaceholderCharacter.variants(for: "body") {
        let figure = try PlaceholderCharacter.figure(wearing: Outfit(["body": body]))
        let isBichon = body == "bichon"
        for part: PartID in ["chin", "chinFrontL", "chinFrontR"] {
            #expect(try figure.part(part).art.isEmpty == !isBichon, "\(body) \(part)")
        }
        #expect(try figure.index("chin") < figure.index("armL") && figure.index("chin") < figure.index("armR"))
        for (half, arm): (PartID, PartID) in [("chinFrontL", "armL"), ("chinFrontR", "armR")] {
            #expect(try figure.index(half) > figure.index(arm))
            #expect(try figure.index(half) < figure.index("flexL") && figure.index(half) < figure.index("flexR"))
            #expect(try figure.part(half).hides?.arm == figure.index(arm))
        }
    }
}

/// Each half stays whole while its arm hangs or swings in idle (24 degrees at most), and is gone once the
/// arm is past 26.5: a switch, not a slow fade, since reactions hold arms at every angle from 25 up and a
/// half-faded fluff would show the sleeve through it.
@Test func aBichonsFrontFluffFollowsItsArm() throws {
    let figure = try PlaceholderCharacter.figure(wearing: Outfit(["body": "bichon"]))
    let left = try figure.index("chinFrontL")
    let right = try figure.index("chinFrontR")
    func shown(_ part: Int, armL: Double, armR: Double) throws -> Double {
        var pose = figure.restPose
        pose.parts[try figure.index("armL")].rotation = armL
        pose.parts[try figure.index("armR")].rotation = armR
        return figure.layout(pose)[part].opacity
    }
    #expect(try shown(left, armL: 0, armR: 0) == 1)
    #expect(try shown(left, armL: 24, armR: -24) == 1)
    #expect(try shown(left, armL: 30, armR: 0) == 0)
    #expect(try shown(left, armL: 90, armR: 0) == 0)
    #expect(try shown(right, armL: 90, armR: 0) == 1)
    #expect(try shown(right, armL: 0, armR: -90) == 0)
    let half = try shown(left, armL: 26.25, armR: 0)
    #expect(half > 0.4 && half < 0.6)
}
