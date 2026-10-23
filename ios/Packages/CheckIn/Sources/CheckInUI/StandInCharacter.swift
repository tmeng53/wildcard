import AvatarArt
import AvatarDomain
import Contracts

/// A character for a member who hasn't made theirs yet: a look and persona picked from their
/// id, the same on every launch.
enum StandInCharacter {
    /// A persona per member, the same on every launch.
    static func persona(of member: MemberID) -> Persona {
        Persona.allCases[seed(member, 0) % Persona.allCases.count]
    }

    /// A look per member, the same on every launch.
    static func look(of member: MemberID) -> Outfit {
        func pick(_ slot: Slot, _ salt: Int) -> String? {
            let variants = PlaceholderCharacter.variants(for: slot)
            return variants.isEmpty ? nil : variants[seed(member, salt) % variants.count]
        }
        var variants: [Slot: String] = ["body": "peach", "brows": "soft", "cheeks": "rosy"]
        variants["hair"] = pick("hair", 1)
        variants["top"] = pick("top", 2)
        variants["bottom"] = pick("bottom", 3)
        var colors: [Slot: RGBAColor] = [:]
        for (salt, slot) in [Slot("body"), "hair", "top", "bottom"].enumerated() {
            guard let variant = variants[slot] else { continue }
            let swatches = PlaceholderCharacter.swatches(for: slot, wearing: variant)
            if !swatches.isEmpty { colors[slot] = swatches[seed(member, salt + 4) % swatches.count] }
        }
        return Outfit(variants, colors: colors)
    }

    private static func seed(_ member: MemberID, _ salt: Int) -> Int {
        let bytes = withUnsafeBytes(of: member.uuid.uuid) { Array($0) }
        return Int(bytes[(salt * 3) % bytes.count]) &+ Int(bytes[(salt * 3 + 1) % bytes.count]) &* 7
    }
}
