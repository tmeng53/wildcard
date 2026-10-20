import AvatarArt
import AvatarDomain
import CharacterEditorDomain
import Testing

@Test func pickingWhatIsWornChangesNothing() {
    var editing = draft()
    #expect(!changed(&editing) { $0.pick("bob", for: "hair") })
    #expect(!editing.canUndo)
}

@Test func hairKeepsItsColorAcrossStyles() {
    var editing = draft()
    #expect(changed(&editing) { $0.pickColor(hairColors[1], for: "hair") })
    #expect(changed(&editing) { $0.pick("buzz", for: "hair") })
    #expect(editing.outfit.variants["hair"] == "buzz")
    #expect(editing.outfit.colors["hair"] == hairColors[1])
}

@Test func onlyAVariantsOwnSwatchesColorIt() {
    var editing = draft()
    #expect(!changed(&editing) { $0.pickColor(blue, for: "hair") })
    #expect(!changed(&editing) { $0.pickColor(blue, for: "hat") })
    #expect(editing.outfit.colors.isEmpty)
}

/// A cat has no hair and starts in its own coat; back to a person, the hair is back.
@Test func animalsWearNoHairAndTheirOwnCoat() {
    var editing = draft()
    editing.pickColor(skin[1], for: "body")
    #expect(changed(&editing) { $0.pick("cat", for: "body") })
    #expect(!editing.wearsHair)
    #expect(editing.outfit.variants["hair"] == nil)
    #expect(editing.outfit.colors["body"] == nil)
    #expect(changed(&editing) { $0.pick("peach", for: "body") })
    #expect(editing.wearsHair)
    #expect(editing.outfit.variants["hair"] == "bob")
}

/// An animal's face comes with its coat, so a person's brows and cheeks stay with the person.
@Test func animalsWearNoPersonsFace() {
    var editing = draft(Outfit(["body": "peach", "hair": "bob", "brows": "soft", "cheeks": "rosy"]))
    editing.pick("cat", for: "body")
    #expect(editing.outfit == Outfit(["body": "cat"]))
    editing.pick("peach", for: "body")
    #expect(editing.outfit.variants["brows"] == "soft")
}

/// A body the editor doesn't list is no person: it wears no hair or face.
@Test func anUnlistedBodyWearsNoHair() {
    let editing = draft(Outfit(["body": "robot", "hair": "buzz", "brows": "bold"]))
    #expect(!editing.wearsHair)
    #expect(editing.outfit == Outfit(["body": "robot"]))
}

/// Brows in the hair's color follow it when the hair is dyed; brows of their own color stay.
@Test func browsFollowTheHairColor() {
    var editing = draft(Outfit(["body": "peach", "hair": "bob", "brows": "soft"]))
    editing.pickColor(hairColors[1], for: "hair")
    #expect(editing.outfit.colors["brows"] == hairColors[1])
    editing.pickColor(nil, for: "hair")
    #expect(editing.outfit.colors.isEmpty)
    var ownBrows = draft(
        Outfit(["body": "peach", "hair": "bob", "brows": "soft"], colors: ["brows": hairColors[0]]))
    ownBrows.pickColor(hairColors[1], for: "hair")
    #expect(ownBrows.outfit.colors["brows"] == hairColors[0])
}

/// Brows put on take the dyed hair's color; taken off, their color goes with them.
@Test func browsPutOnTakeTheHairColor() {
    var editing = draft()
    editing.pickColor(hairColors[1], for: "hair")
    #expect(changed(&editing) { $0.pick("soft", for: "brows") })
    #expect(editing.outfit.colors["brows"] == hairColors[1])
    #expect(changed(&editing) { $0.pick(nil, for: "brows") })
    #expect(editing.outfit.colors["brows"] == nil)
    var undyed = draft()
    undyed.pick("soft", for: "brows")
    #expect(undyed.outfit.colors["brows"] == nil)
}

@Test func aCoatColorDoesNotCarryToAnotherCoat() {
    var editing = draft(Outfit(["body": "cat"], colors: ["body": fur[0]]))
    editing.pick("calico", for: "body")
    #expect(editing.outfit.colors["body"] == nil)
}

@Test func takingOffAPieceTakesOffItsColor() {
    var editing = draft()
    editing.pickColor(blue, for: "top")
    editing.pick(nil, for: "top")
    #expect(editing.outfit.variants["top"] == nil)
    #expect(editing.outfit.colors["top"] == nil)
}

@Test func undoGoesBackOneLookAtATime() {
    var editing = draft()
    editing.pick("racket", for: "prop")
    editing.pickColor(blue, for: "top")
    #expect(changed(&editing) { $0.undo() })
    #expect(editing.outfit.colors["top"] == nil)
    #expect(editing.outfit.variants["prop"] == "racket")
    #expect(changed(&editing) { $0.undo() })
    #expect(editing.outfit == lifter)
    #expect(!changed(&editing) { $0.undo() })
}

@Test func undoRemembersThirtyLooks() {
    var editing = draft()
    for index in 0..<40 {
        editing.pick(index.isMultiple(of: 2) ? "racket" : "dumbbell", for: "prop")
    }
    var steps = 0
    while changed(&editing, { $0.undo() }) { steps += 1 }
    #expect(steps == 30)
    // Forty changes back and forth, minus the thirty undone: the tenth look.
    #expect(editing.outfit.variants["prop"] == "dumbbell")
}

@Test func personaAndNicknameAreNotUndone() {
    var editing = draft()
    editing.pick("racket", for: "prop")
    #expect(changed(&editing) { $0.choose(.shy) })
    #expect(!changed(&editing) { $0.choose(.shy) })
    editing.nickname = "小汤"
    editing.undo()
    #expect(editing.persona == .shy)
    #expect(editing.nickname == "小汤")
}

@Test(arguments: [
    ("Tracy", "Tracy"), ("  小汤  ", "小汤"), ("一二三四五六七八九十一二", "一二三四五六七八九十一二"),
])
func aNicknameIsTrimmed(typed: String, saved: String) {
    var editing = draft()
    editing.nickname = typed
    #expect(editing.name == saved)
}

@Test(arguments: ["", "   ", "一二三四五六七八九十一二三"])
func aNicknameNeedsOneToTwelveCharacters(typed: String) {
    var editing = draft()
    editing.nickname = typed
    #expect(editing.name == nil)
}

@Test func aLongGivenNameIsCutToTwelve() {
    #expect(draft(nickname: "Alexandrina-Victoria").nickname == "Alexandrina-")
}

/// An empty slot shows the rig's default, so picking the default is no change, and its tile is
/// the one picked.
@Test func pickingWhatTheRigPutsThereChangesNothing() {
    var editing = draft()
    #expect(editing.wearing("shoes") == "sneaker")
    #expect(editing.wearing("hat") == nil)
    #expect(!changed(&editing) { $0.pick("sneaker", for: "shoes") })
    #expect(!editing.canUndo)
    #expect(changed(&editing) { $0.pick("runner", for: "shoes") })
    #expect(editing.outfit.variants["shoes"] == "runner")
    #expect(changed(&editing) { $0.pick("sneaker", for: "shoes") })
    #expect(editing.wearing("shoes") == "sneaker")
}

@Test(arguments: [("冲就完了🔥", "冲就完了🔥"), ("  今天也冲冲冲的一天👍🏽 ", "今天也冲冲冲的一天👍🏽")])
func aCatchphraseIsTrimmed(typed: String, saved: String) {
    var editing = draft()
    editing.catchphrase = typed
    #expect(editing.shout?.text == saved)
    #expect(editing.catchphraseIsValid)
}

/// Left empty, the persona's own line is shouted: nothing to save, and nothing wrong.
@Test(arguments: ["", "   "])
func anEmptyCatchphraseLeavesThePersonasLine(typed: String) {
    var editing = draft()
    editing.catchphrase = typed
    #expect(editing.shout == nil)
    #expect(editing.catchphraseIsValid)
}

/// Typed past ten characters, it can't be saved until it's shortened.
@Test func aCatchphraseHasTenCharactersAtMost() {
    var editing = draft()
    editing.catchphrase = "今天也是冲冲冲的一天!"
    #expect(editing.shout == nil)
    #expect(!editing.catchphraseIsValid)
    #expect(draft(catchphrase: "今天也是冲冲冲的一天!").catchphrase == "今天也是冲冲冲的一天")
}

@Test func theCatchphraseIsNotUndone() {
    var editing = draft()
    editing.pick("racket", for: "prop")
    editing.catchphrase = "冲"
    editing.undo()
    #expect(editing.catchphrase == "冲")
}

@Test func shuffleCanBeUndone() {
    var editing = draft()
    var generator = SplitMix64(state: 7)
    editing.shuffle(using: &generator)
    #expect(editing.outfit != lifter)
    editing.undo()
    #expect(editing.outfit == lifter)
}

/// A seeded generator gives the same look every time, and every piece of it is on offer.
@Test func randomLooksComeFromTheCatalog() {
    var generator = SplitMix64(state: 42)
    var bodies: Set<String> = []
    for _ in 0..<200 {
        let look = CharacterDraft.randomLook(from: catalog, using: &generator)
        let body = look.variants["body"] ?? ""
        bodies.insert(body)
        #expect(["peach", "cat", "calico"].contains(body))
        #expect(look.variants["top"] == "tee" && look.variants["bottom"] == "shorts")
        #expect(["sneaker", "runner"].contains(look.variants["shoes"] ?? ""))
        #expect(["round", "sleepy"].contains(look.variants["eyes"] ?? ""))
        // Brows wear the hair's color, or their own art's when the hair has none.
        #expect(look.colors["brows"] == look.colors["hair"] || look.variants["brows"] == nil)
        #expect(look.variants["prop"].map(catalog.props.contains) ?? true)
        for (slot, color) in look.colors {
            #expect(catalog.swatches(for: slot, wearing: look.variants[slot] ?? "").contains(color))
        }
    }
    #expect(bodies == ["peach", "cat", "calico"])
}

/// Runs a change outside `#expect`, which can't call a mutating method, and says whether it changed anything.
private func changed(_ editing: inout CharacterDraft, _ change: (inout CharacterDraft) -> Bool) -> Bool {
    change(&editing)
}
