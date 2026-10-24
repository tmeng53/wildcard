import AvatarArt
import AvatarDomain
import AvatarLooks
import Foundation
import Testing

/// The bundled files load and fit together, so a broken edit to them fails here, not on a phone.
@Test(arguments: Looks.squad)
func everyOutfitBuilds(outfit: Outfit) throws {
    let figure = try PlaceholderCharacter.figure(wearing: outfit)
    #expect(
        figure.parts.map(\.id.rawValue) == [
            "shadow", "dustL", "dustR", "root", "propBack", "tail", "legL", "legR", "torso", "medal", "acc", "earL",
            "earR", "head",
            "flapL",
            "flapR", "crown", "award",
            "nose",
            "eyes", "brows", "browsSad", "browsMad", "glasses", "puff", "mouthSmile", "mouthOpen", "mouthSad",
            "mouthGasp", "drool", "vein", "steamL", "steamR", "stars", "gloom", "bang", "squirtL", "squirtR", "heartL",
            "heartR", "sparkle",
            "tearL", "tearR",
            "food0", "food1", "food2",
            "armL", "armR", "chin", "propR", "gripR", "flexL", "muscleL", "flexR", "muscleR", "heart", "propFront",
            "propOver",
            "desk",
        ])
    // Only the bear's hands are free and only it wears an accessory, and only the cat has a tail.
    #expect(try figure.part("acc").art.count == (outfit == Looks.bear ? 1 : 0))
    // NO LOOK's jersey and MOSSWAY's anorak draw their hems over the waistband; the tee doesn't.
    #expect(try figure.part("torso").art.count == (outfit == Looks.athlete || outfit == Looks.bear ? 3 : 2))
    #expect(try figure.part("propR").art.count == (outfit == Looks.bear ? 0 : 1))
    #expect(try figure.part("tail").art.count == (outfit == Looks.cat ? 1 : 0))
    // Everyone has eyes and both mouths; only people pick brows.
    #expect(try ["eyes", "mouthSmile", "mouthOpen"].allSatisfy { try figure.part($0).art.count == 1 })
    let people = try PlaceholderCharacter.editorChoices().species.filter(\.wearsHair).flatMap(\.bodies)
    let isPerson = people.contains(outfit.variants["body"] ?? "")
    #expect(try figure.part("brows").art.count == (isPerson ? 1 : 0))
    // The open mouth waits hidden until the cheer swaps it in, and the sad face until crying does.
    for part in ["mouthOpen", "browsSad", "mouthSad", "tearL", "tearR", "dustL", "dustR"] as [PartID] {
        #expect(figure.layout(figure.restPose)[try figure.index(part)].opacity == 0)
    }
}

/// Every body and hair the editor can offer, by folder name.
@Test func variantsListTheBundledArt() {
    #expect(
        PlaceholderCharacter.variants(for: "body") == [
            "bear", "bichon", "calico", "cat", "collie", "corgi", "dutch", "golden", "husky", "lihua", "lop",
            "orangewhite", "peach", "rabbit", "ragdoll", "shiba", "siamese", "tortie", "tuxedo",
        ])
    #expect(
        PlaceholderCharacter.variants(for: "hair") == [
            "bob", "bun", "buzz", "curls", "curtain", "long", "pigtails", "ponytail", "spacebuns", "wolf",
        ])
    #expect(PlaceholderCharacter.variants(for: "eyes") == ["dot", "happy", "round", "sharp", "sleepy", "sparkle"])
    #expect(PlaceholderCharacter.variants(for: "brows") == ["arched", "bold", "soft", "worried"])
    #expect(PlaceholderCharacter.variants(for: "mouth") == ["cat", "grin", "oh", "smile", "smirk"])
    #expect(PlaceholderCharacter.variants(for: "cheeks") == ["flushed", "freckles", "rosy"])
    #expect(PlaceholderCharacter.variants(for: "glasses") == ["round", "square"])
    #expect(PlaceholderCharacter.variants(for: "cape").isEmpty)
}

/// A cat leaves its face out and still gets round eyes and a smile; a person can pick others.
@Test func looksWithoutAFaceWearTheDefaultOne() throws {
    let cat = try PlaceholderCharacter.figure(wearing: Looks.cat)
    let plain = try PlaceholderCharacter.figure(wearing: Outfit(["body": "peach", "eyes": "round", "mouth": "smile"]))
    let bare = try PlaceholderCharacter.figure(wearing: Outfit(["body": "peach"]))
    #expect(try cat.part("eyes").art == plain.part("eyes").art)
    #expect(try bare.part("eyes").art == plain.part("eyes").art)
    #expect(try bare.part("mouthSmile").art == plain.part("mouthSmile").art)
    let athlete = try PlaceholderCharacter.figure(wearing: Looks.athlete)
    #expect(try athlete.part("eyes").art != plain.part("eyes").art)
    #expect(try athlete.part("mouthSmile").art != plain.part("mouthSmile").art)
}

@Test(arguments: wardrobe)
func everyLookBuilds(outfit: Outfit) throws {
    let figure = try PlaceholderCharacter.figure(wearing: outfit)
    #expect(figure.parts.count == 59)
}

@Test(arguments: Persona.allCases)
func everyPersonaHasAnIdleACheerAndAWelcome(persona: Persona) throws {
    let figure = try PlaceholderCharacter.figure(wearing: PlaceholderCharacter.lifter)
    let idle = try figure.bind(PlaceholderCharacter.clip("idle", persona: persona))
    #expect(idle.clip.name == "idle" && idle.clip.loops)
    // The idle loop's last frame is its first, so the loop has no visible jump.
    #expect(nearlyEqual(figure.pose(idle, at: idle.clip.duration - 1e-9), figure.pose(idle, at: 0)))
    for name in ["cheer", "welcome"] {
        let oneShot = try figure.bind(PlaceholderCharacter.clip(name, persona: persona))
        #expect(oneShot.clip.name == name && !oneShot.clip.loops)
        // It lands where the idle starts (half-closed eyes included, for deadpan), so handing
        // back to idle doesn't jump either.
        #expect(nearlyEqual(figure.pose(oneShot, at: oneShot.clip.duration), figure.pose(idle, at: 0)), "\(name)")
    }
}

/// Each species moves its own way on top of every persona: the moves start and end at rest,
/// so the idle still loops without a jump and the cheer still lands where the idle starts.
@Test(arguments: Persona.allCases, ["peach", "cat", "shiba", "golden", "rabbit", "lop", "bear"])
func speciesMovesLayerOnEveryPersona(persona: Persona, body: String) throws {
    let look = Outfit(["body": body])
    let figure = try PlaceholderCharacter.figure(wearing: look)
    let species = Looks.species(of: look)
    let plainIdle = try figure.bind(PlaceholderCharacter.clip("idle", persona: persona))
    let idle = try figure.bind(PlaceholderCharacter.clip("idle", persona: persona, species: species))
    let cheer = try figure.bind(PlaceholderCharacter.clip("cheer", persona: persona, species: species))
    #expect(idle.clip.accents.count == 1)
    #expect(idle.clip.accents.first?.tempo == persona.accentTempo)
    #expect(idle.clip.accents.first?.strength == persona.accentStrength)
    #expect(cheer.clip.accents.count == (["peach", "cat"].contains(body) ? 0 : 1))
    #expect(nearlyEqual(figure.pose(idle, at: 0), figure.pose(plainIdle, at: 0)))
    #expect(nearlyEqual(figure.pose(cheer, at: cheer.clip.duration), figure.pose(idle, at: 0)))
}

/// Every species the editor groups has moves of its own; one it doesn't, or none, plays the
/// persona's clip as is.
@Test func everySpeciesHasMoves() throws {
    for species in try PlaceholderCharacter.editorChoices().species.map(\.id) {
        #expect(try PlaceholderCharacter.clip("idle", persona: .shy, species: species).accents.count == 1)
    }
    #expect(try PlaceholderCharacter.clip("idle", persona: .shy, species: "dragon").accents.isEmpty)
    #expect(try PlaceholderCharacter.clip("idle", persona: .shy, species: nil).accents.isEmpty)
}

/// A cat yawns now and then: its mouth opens wide and its eyes shut, later for a deadpan cat,
/// which does everything slowly.
@Test func catsYawn() throws {
    let figure = try PlaceholderCharacter.figure(wearing: Looks.cat)
    let mouth = try figure.index("mouthOpen")
    func openMouth(_ persona: Persona, at time: Double) throws -> Double {
        let idle = try figure.bind(PlaceholderCharacter.clip("idle", persona: persona, species: "cat"))
        return figure.layout(figure.pose(idle, at: time))[mouth].opacity
    }
    #expect(try openMouth(.energetic, at: 0) == 0)
    // The yawn is 3.3 to 4.5 s into the cat's loop: 2.4 to 3.2 s for an energetic cat
    // (1.4 times as fast), 4.7 to 6.4 s for a deadpan one (0.7 times).
    #expect(try openMouth(.energetic, at: 2.8) == 1)
    #expect(try openMouth(.deadpan, at: 2.8) == 0)
    #expect(try openMouth(.deadpan, at: 5.5) == 1)
}

/// Rabbits and pointy-eared dogs carry their ears as parts of their own, so the moves can turn
/// them: upright ears behind the head, a lop's floppy ones over it; rabbits move their noses too.
/// Dogs whose ears don't move (a golden's, a bichon's) keep them in the head's art, drawn as before.
@Test func earsThatMoveArePartsOfTheirOwn() throws {
    let parts: [String: [PartID]] = [
        "rabbit": ["earL", "earR", "nose"], "dutch": ["earL", "earR", "nose"], "lop": ["flapL", "flapR", "nose"],
        "shiba": ["earL", "earR"], "corgi": ["earL", "earR"], "husky": ["earL", "earR"],
        "golden": [], "collie": [], "bichon": [],
    ]
    for (body, moving) in parts {
        let figure = try PlaceholderCharacter.figure(wearing: Outfit(["body": body]))
        for part in ["earL", "earR", "flapL", "flapR", "nose"] as [PartID] {
            #expect(try figure.part(part).art.isEmpty == !moving.contains(part), "\(body) \(part)")
        }
    }
}

/// Hanging sleeves tuck under a person-sized chin; a bichon's fluff reaches lower, so it draws that
/// fluff again over the hanging arms, and only the bichon does. Raised arms stay in front of it.
@Test func aBichonsChinSitsOverTheSleeves() throws {
    for body in try PlaceholderCharacter.variants(for: "body") {
        let figure = try PlaceholderCharacter.figure(wearing: Outfit(["body": body]))
        #expect(try figure.part("chin").art.isEmpty == (body != "bichon"), "\(body)")
        #expect(try figure.index("chin") > figure.index("armL") && figure.index("chin") > figure.index("armR"))
        #expect(try figure.index("chin") < figure.index("flexL") && figure.index("chin") < figure.index("flexR"))
    }
}

/// A hat sits over floppy ears, as it did before the ears were parts of their own.
@Test func hatsSitOverFloppyEars() throws {
    let figure = try PlaceholderCharacter.figure(wearing: Outfit(["body": "lop", "hat": "warmup-cap"]))
    #expect(try figure.index("crown") > figure.index("flapL") && figure.index("crown") > figure.index("flapR"))
    #expect(try figure.part("crown").art.count == 2)
}

/// The same pose, give or take floating-point rounding. A part turned a full circle (a swimmer's
/// arm) looks the same as one that hasn't turned.
func nearlyEqual(_ first: Pose, _ second: Pose) -> Bool {
    zip(first.parts, second.parts).allSatisfy { one, other in
        Channel.allCases.allSatisfy { channel in
            let gap = abs(one[channel] - other[channel])
            return channel == .rotation
                ? min(gap.truncatingRemainder(dividingBy: 360), 360 - gap.truncatingRemainder(dividingBy: 360)) < 1e-6
                : gap < 1e-6
        }
    }
}

/// Personas read differently at a glance: how high each one jumps, and the moves that
/// define them.
@Test func personasMoveTheirOwnWay() throws {
    let figure = try PlaceholderCharacter.figure(wearing: PlaceholderCharacter.lifter)
    func rootValues(_ persona: Persona, _ value: (PartPose) -> Double) throws -> [Double] {
        let cheer = try figure.bind(PlaceholderCharacter.clip("cheer", persona: persona))
        let root = try figure.index("root")
        return (0...Int(cheer.clip.duration * 100)).map { value(figure.pose(cheer, at: Double($0) / 100).parts[root]) }
    }
    // Root y is up-negative, so the highest jump has the smallest minimum.
    let peaks = try Persona.allCases.map { try rootValues($0, \.y).min() ?? 0 }
    #expect(abs(peaks[0] - -10) < 0.5)  // deadpan
    #expect(abs(peaks[1] - -36) < 0.5)  // energetic
    #expect(peaks.min() == peaks[1])
    #expect(peaks.max() == peaks[0])
    // The shy one edges sideways before it hops.
    #expect(abs((try rootValues(.shy, \.x).min() ?? 0) - -10) < 0.5)
}

/// Every look stays inside the canvas through every frame of every persona's clips, with its
/// species' moves on top, so a view sized to
/// the art never cuts off an ear, a tail or a racket. Only the shadow may touch the bottom edge.
@Test(arguments: Persona.allCases, wardrobe)
func everyFrameStaysOnTheCanvas(persona: Persona, outfit: Outfit) throws {
    let figure = try PlaceholderCharacter.figure(wearing: outfit)
    for name in ["idle", "cheer", "welcome"] {
        let bound = try figure.bind(
            PlaceholderCharacter.clip(name, persona: persona, species: Looks.species(of: outfit)))
        // An idle with its species' moves on top lines its two loops up differently each time
        // round, so it plays for 20 s, a few rounds of the longest.
        let seconds = bound.clip.accents.isEmpty || !bound.clip.loops ? bound.clip.duration : 20
        expectOnCanvas(figure, bound, for: seconds, "\(persona.rawValue) \(name)")
    }
}

/// Checks every frame of a clip, 50 a second, keeps the figure inside its canvas. Only the
/// shadow may touch the bottom edge, unless the move lies down (`below`).
func expectOnCanvas(
    _ figure: Figure, _ bound: BoundClip, for seconds: Double, _ label: String, sideways: Double = 0, above: Double = 0,
    below: Double = 0
) {
    for frame in 0...Int(seconds * 50) {
        let time = Double(frame) / 50
        for (part, placement) in zip(figure.parts, figure.layout(figure.pose(bound, at: time)))
        where placement.opacity > 0 {
            for shape in part.art.flatMap(\.shapes) {
                let margin = (shape.stroke?.width ?? 0) / 2
                for point in outline(shape.path).map(placement.transform.apply(to:)) {
                    let bottom = part.id == "shadow" || point.y + margin <= figure.height + below
                    #expect(
                        point.x - margin >= -sideways && point.x + margin <= figure.width + sideways
                            && point.y - margin >= -above && bottom,
                        "\(label) at \(time)s: \(part.id) reaches (\(point.x), \(point.y))")
                }
            }
        }
    }
}

/// Points along each segment of a path, curves sampled every tenth of the way.
func outline(_ path: [PathElement]) -> [Point] {
    var points: [Point] = []
    var current = Point(x: 0, y: 0)
    func along(_ point: (Double) -> Point) {
        points += (1...10).map { point(Double($0) / 10) }
    }
    for element in path {
        switch element {
        case .move(let point), .line(let point):
            points.append(point)
            current = point
        case .quadCurve(let end, let control):
            let start = current
            along { way in
                let rest = 1 - way
                return Point(
                    x: rest * rest * start.x + 2 * rest * way * control.x + way * way * end.x,
                    y: rest * rest * start.y + 2 * rest * way * control.y + way * way * end.y)
            }
            current = end
        case .curve(let end, let control1, let control2):
            let start = current
            along { way in
                let rest = 1 - way
                return Point(
                    x: rest * rest * rest * start.x + 3 * rest * rest * way * control1.x + 3 * rest * way * way
                        * control2.x + way * way * way
                        * end.x,
                    y: rest * rest * rest * start.y + 3 * rest * rest * way * control1.y + 3 * rest * way * way
                        * control2.y + way * way * way * end.y
                )
            }
            current = end
        case .close: break
        }
    }
    return points
}

/// Every body the editor groups is bundled, and every bundled body is in a group; every piece of
/// clothing and prop it offers is bundled, and its first color is its art's own. The racks start
/// with WARM-UP's twelve pieces.
@Test func theEditorOffersBundledArt() throws {
    let choices = try PlaceholderCharacter.editorChoices()
    #expect(choices.species.map(\.id) == ["person", "cat", "dog", "rabbit", "bear"])
    #expect(choices.species.map(\.wearsHair) == [true, false, false, false, false])
    let grouped = choices.species.flatMap(\.bodies)
    #expect(Set(grouped).count == grouped.count)
    #expect(Set(grouped) == Set(PlaceholderCharacter.variants(for: "body")))
    #expect(
        choices.props == [
            "bottle", "dumbbell", "kettlebell", "yogamat", "racket", "pickleball", "badminton", "pingpong", "chalkbag",
            "goggles",
        ])
    #expect(Set(choices.props).isSubset(of: PlaceholderCharacter.variants(for: "prop")))
    #expect(
        choices.wear.mapValues { $0.map(\.id) } == [
            "top": ["warmup-tee", "warmup-tank", "warmup-hoodie"],
            "bottom": ["warmup-shorts", "warmup-joggers", "warmup-leggings"],
            "shoes": ["warmup-canvas", "warmup-runner"],
            "hat": ["warmup-cap", "warmup-headband"],
            "acc": ["warmup-towel", "warmup-waistbag"],
        ])
    for (slot, pieces) in choices.wear {
        #expect(Set(pieces.map(\.id)).isSubset(of: PlaceholderCharacter.variants(for: slot)))
        for piece in pieces {
            #expect(piece.swatches.count == 6, "\(piece.id)")
            #expect(
                piece.swatches.first == PlaceholderCharacter.tones(for: slot, wearing: piece.id)?.base, "\(piece.id)")
        }
    }
    // A look that leaves its top, bottom or shoes out wears WARM-UP's first.
    let defaults = try PlaceholderCharacter.rig().defaults
    for slot: Slot in ["top", "bottom", "shoes"] {
        #expect(defaults[slot] == choices.wear[slot]?.first?.id)
    }
}

@Test func tonesNameTheColorAnUncoloredVariantShows() {
    #expect(PlaceholderCharacter.tones(for: "top", wearing: "warmup-tee")?.base == RGBAColor(hex: "#F4F6FA"))
    #expect(PlaceholderCharacter.tones(for: "body", wearing: "calico") == nil)
    #expect(PlaceholderCharacter.tones(for: "prop", wearing: "dumbbell") == nil)
}

@Test func editorChoicesOfAnotherVersionAreRejected() {
    #expect(throws: AvatarError.unsupportedVersion(1)) {
        try EditorChoices.decode(Data(#"{"version": 1, "species": [], "hats": [], "shoes": [], "props": []}"#.utf8))
    }
}

/// A misspelt key fails instead of loading as if it were absent.
@Test func editorChoicesWithAnUnknownKeyAreRejected() {
    #expect(throws: AvatarError.malformedJSON(#".species[0]: unknown key "hiar""#)) {
        try EditorChoices.decode(
            Data(
                #"{"version": 2, "species": [{"id": "person", "bodies": ["peach"], "hiar": true}], "wear": {}, "props": []}"#
                    .utf8))
    }
}
