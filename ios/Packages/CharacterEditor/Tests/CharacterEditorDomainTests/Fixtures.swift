import AvatarArt
import AvatarDomain
import CharacterEditorDomain

let skin = [RGBAColor(red: 0xE8, green: 0xB4, blue: 0x8F), RGBAColor(red: 0x8D, green: 0x5A, blue: 0x3C)]
let fur = [RGBAColor(red: 0xF2, green: 0xA6, blue: 0x5A)]
let hairColors = [RGBAColor(red: 0x22, green: 0x25, blue: 0x2E), RGBAColor(red: 0xC9, green: 0xA0, blue: 0x6A)]
let blue = RGBAColor(red: 0x2D, green: 0x5B, blue: 0xA0)

/// People (one body) and cats (a plain coat and a calico); hair, two eyes, brows, a hat, tops,
/// bottoms, two pairs of shoes and two props. Round eyes and sneakers are what a look leaves
/// empty wears.
let catalog = Catalog(
    species: [
        EditorChoices.Species(id: "person", bodies: ["peach"], wearsHair: true),
        EditorChoices.Species(id: "cat", bodies: ["cat", "calico"]),
    ],
    variants: [
        "hair": ["bob", "buzz"], "eyes": ["round", "sleepy"], "brows": ["soft"], "hat": ["cap"], "top": ["tee"],
        "bottom": ["shorts"], "shoes": ["sneaker", "runner"],
    ],
    props: ["dumbbell", "racket"],
    swatches: [
        "body": ["peach": skin, "cat": fur], "hair": ["bob": hairColors, "buzz": hairColors],
        "brows": ["soft": hairColors], "top": ["tee": [blue]],
    ],
    originals: [:], defaults: ["eyes": "round", "shoes": "sneaker"])

let lifter = Outfit(["body": "peach", "hair": "bob", "top": "tee", "bottom": "shorts", "prop": "dumbbell"])

func draft(_ look: Outfit = lifter, nickname: String = "Tracy", catchphrase: String = "") -> CharacterDraft {
    CharacterDraft(catalog: catalog, look: look, persona: .energetic, nickname: nickname, catchphrase: catchphrase)
}

/// The same numbers on every run, so a random look is a literal expectation.
struct SplitMix64: RandomNumberGenerator {
    var state: UInt64

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var mixed = state
        mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
        mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
        return mixed ^ (mixed >> 31)
    }
}
