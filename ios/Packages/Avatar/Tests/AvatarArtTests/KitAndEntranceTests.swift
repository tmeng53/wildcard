import AvatarArt
import AvatarDomain
import AvatarLooks
import Contracts
import Foundation
import Testing

/// Shoes are their own slot: bodies draw bare legs, and every look wears 小白鞋 unless it picks
/// another pair, drawn over the bottoms.
@Test func everyLookWearsShoes() throws {
    for body in PlaceholderCharacter.variants(for: "body") {
        let figure = try PlaceholderCharacter.figure(wearing: Outfit(["body": body, "bottom": "leggings"]))
        for leg in ["legL", "legR"] as [PartID] {
            #expect(try figure.part(leg).art.count == 3, "\(body) \(leg)")
        }
    }
    let plain = try PlaceholderCharacter.figure(wearing: Outfit(["body": "peach"]))
    let sneakers = try PlaceholderCharacter.figure(wearing: Outfit(["body": "peach", "shoes": "sneaker"]))
    let runners = try PlaceholderCharacter.figure(wearing: Outfit(["body": "peach", "shoes": "runner"]))
    #expect(try plain.part("legL").art == sneakers.part("legL").art)
    #expect(try runners.part("legL").art != sneakers.part("legL").art)
    #expect(try runners.part("legL").art.last?.shapes.first?.fill == RGBAColor(hex: "#2D5BA0"))
}

/// Shoes keep their art's colors, like hats and props.
@Test func shoesKeepTheirColors() {
    for shoes in PlaceholderCharacter.variants(for: "shoes") {
        #expect(PlaceholderCharacter.tones(for: "shoes", wearing: shoes) == nil)
        #expect(PlaceholderCharacter.swatches(for: "shoes", wearing: shoes).isEmpty)
    }
}

/// Each sport puts on its own kit, its category's, or the warm-up.
@Test func sportsPickTheirKits() throws {
    let kits = try PlaceholderCharacter.sportKits()
    let picks: [Sport: String] = [
        .swim: "swim", .surf: "swim", .run: "run", .hike: "run", .spin: "run", .strength: "strength",
        .boxing: "strength", .tennis: "tennis", .badminton: "tennis", .climb: "climb", .ski: "warmup",
        .yoga: "yoga", .matPilates: "yoga", .basketball: "warmup", .dance: "warmup", .dogWalk: "warmup",
    ]
    for (sport, kit) in picks {
        #expect(kits.kit(for: .sport(sport)).id == kit, "\(sport)")
    }
    #expect(kits.kit(for: .custom(try CustomSport("飞盘"))).id == "warmup")
    #expect(kits.kits.map(\.id) == ["swim", "run", "strength", "tennis", "climb", "yoga", "warmup"])
}

/// A kit changes the clothes it names and keeps the rest of the look: body, hair, face, and the
/// colors of the slots it changes when the new variant can take them.
@Test func aKitKeepsTheLook() throws {
    let kits = try PlaceholderCharacter.sportKits()
    let blue = try #require(RGBAColor(hex: "#2D5BA0"))
    let look = Outfit(
        ["body": "peach", "hair": "bob", "eyes": "sharp", "hat": "cap", "top": "tee", "bottom": "leggings"],
        colors: ["top": blue, "hair": try #require(RGBAColor(hex: "#2A2333"))])
    let running = kits.kit(for: .sport(.run)).dress(look)
    #expect(running.variants["top"] == "tank" && running.colors["top"] == blue)
    #expect(running.variants["hat"] == "headband" && running.variants["shoes"] == "runner")
    #expect(running.variants["prop"] == "stopwatch")
    #expect(running.variants["hair"] == "bob" && running.variants["eyes"] == "sharp")
    #expect(running.colors["hair"] == look.colors["hair"])
    let climbing = kits.kit(for: .sport(.climb)).dress(look)
    #expect(climbing.variants["hat"] == nil && climbing.variants["shoes"] == "climbing")
    #expect(kits.kit(for: .sport(.ski)).dress(look) == look)
}

@Test func kitsJSONIsChecked() {
    func decode(_ json: String) throws(AvatarError) -> SportKits {
        try SportKits.decode(Data(json.utf8))
    }
    let kit = #"[{"id": "run", "wear": {}}]"#
    #expect(throws: AvatarError.unknownKit("swim")) {
        try decode(
            #"{"version": 1, "kits": \#(kit), "categories": {"water": "swim"}, "sports": {}, "otherwise": "run"}"#)
    }
    #expect(throws: AvatarError.unknownKit("pool")) {
        try decode(#"{"version": 1, "kits": \#(kit), "categories": {"pool": "run"}, "sports": {}, "otherwise": "run"}"#)
    }
    #expect(throws: AvatarError.unknownKit("parkour")) {
        try decode(
            #"{"version": 1, "kits": \#(kit), "categories": {}, "sports": {"parkour": "run"}, "otherwise": "run"}"#)
    }
    #expect(throws: AvatarError.unsupportedVersion(2)) {
        try decode(#"{"version": 2, "kits": [], "categories": {}, "sports": {}, "otherwise": "run"}"#)
    }
}

/// Every kit on every kind of character: the quick turn meets edge-on, so the swap is out of
/// sight; the turn back lands where the kit's move starts, and the move loops without a jump.
/// Nothing leaves the canvas.
@Test(arguments: Persona.allCases)
func everyKitPlaysOnEveryLook(persona: Persona) throws {
    let kits = try PlaceholderCharacter.sportKits()
    let turn = try PlaceholderCharacter.turn()
    #expect(!turn.out.loops && !turn.in.loops)
    for kit in kits.kits {
        for look in Looks.squad {
            let figure = try PlaceholderCharacter.figure(wearing: kit.dress(look))
            let out = try figure.bind(turn.out)
            let back = try figure.bind(turn.in)
            let move = try figure.bind(PlaceholderCharacter.move(for: kit, persona: persona))
            #expect(move.clip.loops)
            let root = try figure.index("root")
            #expect(figure.pose(out, at: out.clip.duration).parts[root].scaleX < 0.1)
            #expect(nearlyEqual(figure.pose(out, at: out.clip.duration), figure.pose(back, at: 0)))
            #expect(nearlyEqual(figure.pose(back, at: back.clip.duration), figure.restPose))
            #expect(nearlyEqual(figure.pose(move, at: move.clip.duration - 1e-9), figure.pose(move, at: 0)))
            for clip in [out, back, move] {
                expectOnCanvas(figure, clip, for: clip.clip.duration, "\(kit.id) \(persona.rawValue) \(clip.clip.name)")
            }
        }
    }
}

/// A deadpan character swims slower than an energetic one.
@Test func personasPlayKitMovesAtTheirOwnTempo() throws {
    let swim = try PlaceholderCharacter.sportKits().kit(for: .sport(.swim))
    let deadpan = try PlaceholderCharacter.move(for: swim, persona: .deadpan)
    let energetic = try PlaceholderCharacter.move(for: swim, persona: .energetic)
    #expect(abs(deadpan.duration - 1.625) < 1e-9)
    #expect(abs(energetic.duration - 1.04) < 1e-9)
}

/// 上场: the root carries the figure in from the right and up into the jump while the shadow
/// keeps to the floor, following only sideways; the figure faces the way it runs, spins in the
/// air and ends at rest on its spot.
@Test func theEntranceRunsInAndLandsAtRest() throws {
    let figure = try PlaceholderCharacter.figure(wearing: PlaceholderCharacter.lifter)
    let entrance = try figure.bind(PlaceholderCharacter.entrance())
    #expect(!entrance.clip.loops)
    let (root, shadow) = (try figure.index("root"), try figure.index("shadow"))
    let start = figure.pose(entrance, at: 0)
    #expect(start.parts[root].x > figure.width * 3)
    #expect(start.parts[root].scaleX == -1)
    var highest = 0.0
    var spun = false
    for frame in 0...Int(entrance.clip.duration * 100) {
        let pose = figure.pose(entrance, at: Double(frame) / 100)
        #expect(pose.parts[shadow].y == 0)
        #expect(abs(pose.parts[shadow].x - pose.parts[root].x) < 1e-9)
        highest = min(highest, pose.parts[root].y)
        if Double(frame) / 100 > 1.2, pose.parts[root].scaleX < 0 { spun = true }
    }
    #expect(highest < -300)
    #expect(spun)
    #expect(nearlyEqual(figure.pose(entrance, at: entrance.clip.duration), figure.restPose))
}

/// Teammates cheer a new member in their own way: the energetic ones jump highest, the show-off
/// spins, the shy one edges away afterwards.
@Test func personasWelcomeTheirOwnWay() throws {
    let figure = try PlaceholderCharacter.figure(wearing: PlaceholderCharacter.lifter)
    let root = try figure.index("root")
    func values(_ persona: Persona, _ value: (PartPose) -> Double) throws -> [Double] {
        let welcome = try figure.bind(PlaceholderCharacter.clip("welcome", persona: persona))
        return (0...Int(welcome.clip.duration * 100)).map {
            value(figure.pose(welcome, at: Double($0) / 100).parts[root])
        }
    }
    let peaks = try Persona.allCases.map { try values($0, \.y).min() ?? 0 }
    #expect(peaks.min() == peaks[Persona.allCases.firstIndex(of: .energetic) ?? 0])
    #expect(abs(peaks[Persona.allCases.firstIndex(of: .deadpan) ?? 0]) < 0.5)
    #expect(try values(.showoff, \.scaleX).min() ?? 1 < 0)
    #expect(try values(.shy, \.x).min() ?? 0 < -5)
}
