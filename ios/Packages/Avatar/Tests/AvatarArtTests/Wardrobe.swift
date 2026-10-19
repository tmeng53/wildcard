import AvatarArt
import AvatarDomain
import AvatarLooks

/// The squad, then one look for every other body, hair and face part in the bundle (a body in
/// a tee and shorts, a hair or face part on the lifter), and a person and each kind of animal
/// holding every prop, so tests that run over looks cover every piece of art.
let wardrobe: [Outfit] = {
    let squad = Looks.squad
    func unworn(_ slot: Slot) -> [String] {
        PlaceholderCharacter.variants(for: slot).filter { variant in !squad.contains { $0.variants[slot] == variant } }
    }
    let bodies = unworn("body").map { Outfit(["body": $0, "top": "tee", "bottom": "shorts"]) }
    let onLifter = (["hair"] + PlaceholderCharacter.faceSlots).flatMap { slot in
        unworn(slot).map { variant in
            var look = PlaceholderCharacter.lifter
            look.variants[slot] = variant
            return look
        }
    }
    // One body per species with every prop, since an animal can hold one too.
    let firsts = ["peach", "cat", "shiba", "collie", "rabbit", "lop", "bear"]
    let armed = firsts.flatMap { body in
        PlaceholderCharacter.variants(for: "prop").map {
            Outfit(["body": body, "top": "tee", "bottom": "shorts", "prop": $0])
        }
    }
    return squad + bodies + onLifter + armed
}()

/// Coats whose pattern is the point (a calico's patches, a husky's mask): their art keeps
/// its own colors, so the editor offers no swatches for them.
let fixedCoats: Set = [
    "lihua", "tuxedo", "calico", "siamese", "ragdoll", "orangewhite", "tortie",
    "shiba", "corgi", "collie", "husky", "bichon", "dutch",
]
