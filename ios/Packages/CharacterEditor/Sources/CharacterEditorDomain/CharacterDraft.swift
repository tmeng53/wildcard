import AvatarArt
import AvatarDomain
import Contracts
import Foundation

/// The character being made: what each slot wears and its color, the persona and its 口头禅,
/// the nickname, and the looks before, for undo. Every change returns whether anything changed, so the
/// screen only plays a move when the look really moved.
public struct CharacterDraft: Hashable, Sendable {
    public let catalog: Catalog
    /// Every pick, including hair while the body is an animal, so a person who tries on a cat
    /// gets their hair back.
    public private(set) var picks: Outfit
    public private(set) var persona: Persona
    /// As typed; `name` is what gets saved.
    public var nickname: String
    /// The 口头禅 as typed; empty leaves the persona's own line. `shout` is what gets saved.
    public var catchphrase: String
    private var history: [Outfit] = []

    /// How many looks undo goes back.
    public static let historyLimit = 30
    /// The most characters a nickname may have: the API's.
    public static let nicknameLimit = Nickname.maxLength

    /// The most characters a 口头禅 may have: the API's.
    public static let catchphraseLimit = Catchphrase.maxLength

    public init(catalog: Catalog, look: Outfit, persona: Persona, nickname: String, catchphrase: String = "") {
        self.catalog = catalog
        picks = look
        self.persona = persona
        self.nickname = String(nickname.prefix(Self.nicknameLimit))
        self.catchphrase = String(catchphrase.prefix(Self.catchphraseLimit))
    }

    /// What the character wears: the picks, minus hair and a person's face on an animal, whose
    /// face comes with its coat.
    public var outfit: Outfit {
        guard !wearsHair else { return picks }
        var outfit = picks
        for slot in ["hair"] + PlaceholderCharacter.faceSlots {
            outfit.variants[slot] = nil
            outfit.colors[slot] = nil
        }
        return outfit
    }

    /// Whether the body is a person's, who wears hair: a species that wears it.
    public var wearsHair: Bool {
        guard let body = picks.variants["body"] else { return false }
        return catalog.species(of: body)?.wearsHair == true
    }

    public var canUndo: Bool { !history.isEmpty }

    /// What `slot` shows: its pick, or what the rig puts there when it's left empty.
    public func wearing(_ slot: Slot) -> String? {
        picks.variants[slot] ?? catalog.defaults[slot]
    }

    /// The nickname to save, by the API's rule; nil while it isn't one.
    public var name: String? {
        try? Nickname(nickname).text
    }

    /// The 口头禅 to save: nil when left empty, for the persona's own line.
    public var shout: Catchphrase? {
        try? Catchphrase(catchphrase)
    }

    /// Whether the 口头禅 can be saved as typed: empty, or one by the API's rule.
    public var catchphraseIsValid: Bool {
        catchphrase.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || shout != nil
    }

    /// Wears `variant` in `slot`, or nothing there when nil; picking what the slot already shows
    /// changes nothing, even when that is the rig's default. A color stays when the new
    /// variant can wear it too: hair keeps its color across styles, skin across people. An
    /// animal's coat starts from its own colors. Brows put on without a color take the hair's.
    @discardableResult
    public mutating func pick(_ variant: String?, for slot: Slot) -> Bool {
        guard wearing(slot) != variant else { return false }
        var next = picks
        next.variants[slot] = variant
        let keepsColor: Bool
        if let variant, let color = picks.colors[slot] {
            let sameSpecies =
                slot != "body" || picks.variants["body"].flatMap(catalog.species(of:)) == catalog.species(of: variant)
            keepsColor = sameSpecies && catalog.swatches(for: slot, wearing: variant).contains(color)
        } else {
            keepsColor = false
        }
        if !keepsColor { next.colors[slot] = nil }
        if slot == "brows", variant != nil, next.colors["brows"] == nil { next.colors["brows"] = picks.colors["hair"] }
        commit(next)
        return true
    }

    /// Colors `slot` with one of its swatches, or back to its art's own color when nil. Brows
    /// follow the hair until they're given a color of their own.
    @discardableResult
    public mutating func pickColor(_ color: RGBAColor?, for slot: Slot) -> Bool {
        guard let variant = picks.variants[slot], picks.colors[slot] != color else { return false }
        if let color, !catalog.swatches(for: slot, wearing: variant).contains(color) { return false }
        var next = picks
        if slot == "hair", next.variants["brows"] != nil, next.colors["brows"] == next.colors["hair"] {
            next.colors["brows"] = color
        }
        next.colors[slot] = color
        commit(next)
        return true
    }

    @discardableResult
    public mutating func choose(_ persona: Persona) -> Bool {
        guard persona != self.persona else { return false }
        self.persona = persona
        return true
    }

    /// Back to the look before the last change. The persona, 口头禅 and nickname aren't part of it.
    @discardableResult
    public mutating func undo() -> Bool {
        guard let previous = history.popLast() else { return false }
        picks = previous
        return true
    }

    /// A whole new random look, which undo can take back.
    public mutating func shuffle(using generator: inout some RandomNumberGenerator) {
        commit(Self.randomLook(from: catalog, using: &generator))
    }

    /// A random look: a person a bit less than half the time, else any animal; hair, a face,
    /// top, bottom and shoes always; brows most of the time, cheeks half, glasses a fifth; a hat
    /// about a third of the time, a prop most of the time; and most recolorable pieces in one of
    /// their swatches, brows in the hair's.
    public static func randomLook(from catalog: Catalog, using generator: inout some RandomNumberGenerator) -> Outfit {
        let people = catalog.species.filter(\.wearsHair).flatMap(\.bodies)
        let animals = catalog.species.filter { !$0.wearsHair }.flatMap(\.bodies)
        let body =
            (Double.random(in: 0..<1, using: &generator) < 0.4 ? people.randomElement(using: &generator) : nil)
            ?? animals.randomElement(using: &generator) ?? people.randomElement(using: &generator)
        var look = Outfit([:])
        look.variants["body"] = body
        look.variants["hair"] = catalog.variants["hair"]?.randomElement(using: &generator)
        look.variants["top"] = catalog.variants["top"]?.randomElement(using: &generator)
        look.variants["bottom"] = catalog.variants["bottom"]?.randomElement(using: &generator)
        look.variants["shoes"] = catalog.variants["shoes"]?.randomElement(using: &generator)
        let face: [(Slot, Double)] = [("eyes", 1), ("brows", 0.9), ("mouth", 1), ("cheeks", 0.5), ("glasses", 0.2)]
        for (slot, chance) in face where Double.random(in: 0..<1, using: &generator) < chance {
            look.variants[slot] = catalog.variants[slot]?.randomElement(using: &generator)
        }
        if Double.random(in: 0..<1, using: &generator) < 0.35 {
            look.variants["hat"] = catalog.variants["hat"]?.randomElement(using: &generator)
        }
        if Double.random(in: 0..<1, using: &generator) < 0.7 {
            look.variants["prop"] = catalog.props.randomElement(using: &generator)
        }
        for slot: Slot in ["body", "hair", "eyes", "top", "bottom"] {
            guard let variant = look.variants[slot], Double.random(in: 0..<1, using: &generator) < 0.8 else { continue }
            look.colors[slot] = catalog.swatches(for: slot, wearing: variant).randomElement(using: &generator)
        }
        if let brows = look.variants["brows"], let hair = look.colors["hair"],
            catalog.swatches(for: "brows", wearing: brows).contains(hair)
        {
            look.colors["brows"] = hair
        }
        return look
    }

    private mutating func commit(_ next: Outfit) {
        history.append(picks)
        if history.count > Self.historyLimit { history.removeFirst(history.count - Self.historyLimit) }
        picks = next
    }
}
