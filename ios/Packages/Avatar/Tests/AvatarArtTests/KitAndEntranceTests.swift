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

/// Every kit on every kind of character: the hop squashes down, where the kit goes on, and pops
/// back up from that same squash to land where the kit's move starts; the move loops without a
/// jump. Nothing leaves the canvas.
@Test(arguments: Persona.allCases)
func everyKitPlaysOnEveryLook(persona: Persona) throws {
    let kits = try PlaceholderCharacter.sportKits()
    let hop = try PlaceholderCharacter.kitHop()
    #expect(!hop.out.loops && !hop.in.loops)
    for kit in kits.kits {
        for look in Looks.squad {
            let figure = try PlaceholderCharacter.figure(wearing: kit.dress(look))
            let out = try figure.bind(hop.out)
            let back = try figure.bind(hop.in)
            let move = try figure.bind(PlaceholderCharacter.move(for: kit, persona: persona))
            #expect(move.clip.loops)
            let root = try figure.index("root")
            #expect(figure.pose(out, at: out.clip.duration).parts[root].scaleY < 0.9)
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
    #expect(abs(deadpan.duration - 1.3 / 0.7) < 1e-9)
    #expect(abs(energetic.duration - 1.3 / 1.4) < 1e-9)
}

/// 上场: the root carries the figure in from the right and up into the jump while the shadow
/// keeps to the floor, following only sideways; the figure ends at rest on its spot.
@Test func theEntranceRunsInAndLandsAtRest() throws {
    let figure = try PlaceholderCharacter.figure(wearing: PlaceholderCharacter.lifter)
    let entrance = try figure.bind(PlaceholderCharacter.entrance())
    #expect(!entrance.clip.loops)
    let (root, shadow) = (try figure.index("root"), try figure.index("shadow"))
    let start = figure.pose(entrance, at: 0)
    #expect(start.parts[root].x > figure.width * 3)
    // Wholly off a stage that ends left of `entranceStartsRightOf`, so it runs in rather than pops in.
    for (part, placement) in zip(figure.parts, figure.layout(start)) where placement.opacity > 0 && part.id != "shadow"
    {
        for point in part.art.flatMap(\.shapes).flatMap({ outline($0.path) }).map(placement.transform.apply(to:)) {
            #expect(point.x > PlaceholderCharacter.entranceStartsRightOf, "\(part.id)")
        }
    }
    var highest = 0.0
    for frame in 0...Int(entrance.clip.duration * 100) {
        let pose = figure.pose(entrance, at: Double(frame) / 100)
        #expect(pose.parts[shadow].y == 0)
        #expect(abs(pose.parts[shadow].x - pose.parts[root].x) < 1e-9)
        highest = min(highest, pose.parts[root].y)
    }
    #expect(highest < -300)
    #expect(nearlyEqual(figure.pose(entrance, at: entrance.clip.duration), figure.restPose))
}

/// Teammates cheer a new member in their own way: the energetic ones jump highest, the show-off
/// flexes, the shy one edges away afterwards.
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
    let showoff = try figure.bind(PlaceholderCharacter.clip("welcome", persona: .showoff))
    let flexing = figure.pose(showoff, at: 1).parts[try figure.index("armR")].rotation
    #expect(flexing < -90)
    #expect(try values(.shy, \.x).min() ?? 0 < -5)
}

/// The art is flat, so no clip turns the whole character side-on, mirrors it or spins it: the
/// root and torso keep facing front (a squash is fine) and lean at most 15°.
@Test func noClipTurnsTheCharacter() throws {
    let figure = try PlaceholderCharacter.figure(wearing: PlaceholderCharacter.lifter)
    let kits = try PlaceholderCharacter.sportKits()
    let hop = try PlaceholderCharacter.kitHop()
    var clips = [hop.out, hop.in, try PlaceholderCharacter.entrance(), try PlaceholderCharacter.drop()]
    clips += try PlaceholderCharacter.editorChoices().props.compactMap {
        try PlaceholderCharacter.propMove(for: Outfit(["prop": $0]))
    }
    clips += PlaceholderCharacter.reactionMoves.compactMap(PlaceholderCharacter.reactionMove)
    for persona in Persona.allCases {
        clips += [try PlaceholderCharacter.typing(persona: persona), try PlaceholderCharacter.teary(persona: persona)]
        clips += try Move.allCases.map { try PlaceholderCharacter.clip(for: $0, persona: persona) }
        clips += [
            try PlaceholderCharacter.sitting(persona: persona), try PlaceholderCharacter.holdingSign(persona: persona),
            try PlaceholderCharacter.sleeping(persona: persona),
        ]
        clips += try ["idle", "cheer", "welcome"].map { try PlaceholderCharacter.clip($0, persona: persona) }
        clips += try kits.kits.map { try PlaceholderCharacter.move(for: $0, persona: persona) }
    }
    let whole = [try figure.index("root"), try figure.index("torso")]
    for clip in clips {
        let bound = try figure.bind(clip)
        for frame in 0...Int(clip.duration * 100) {
            let pose = figure.pose(bound, at: Double(frame) / 100)
            for part in whole {
                #expect(pose.parts[part].scaleX > 0.85, "\(clip.name) at \(frame)")
                #expect(abs(pose.parts[part].rotation) <= 15, "\(clip.name) at \(frame)")
            }
        }
    }
}

/// A teammate's reaction makes the author's character play a move from the feed's library: each
/// one drawn plays once on every look, stays on the canvas and ends at rest, so the character
/// holds still again until the next reaction.
@Test func reactionMovesPlayOnceAndEndAtRest() throws {
    #expect(
        PlaceholderCharacter.reactionMoves == ["chin-up", "drool", "flex", "heart", "laugh-bend", "pout", "shocked"])
    #expect(PlaceholderCharacter.reactionMove("happy-hop") == nil)
    #expect(PlaceholderCharacter.reactionMove("../moves/entrance") == nil)
    let figure = try PlaceholderCharacter.figure(wearing: PlaceholderCharacter.lifter)
    for id in PlaceholderCharacter.reactionMoves {
        let clip = try #require(PlaceholderCharacter.reactionMove(id))
        #expect(!clip.loops, "\(id)")
        let bound = try figure.bind(clip)
        expectOnCanvas(figure, bound, for: clip.duration, id)
        #expect(nearlyEqual(figure.pose(bound, at: clip.duration), figure.restPose), "\(id)")
    }
}
