import AvatarDomain
import Foundation

/// The AI coaches' characters, by coach id: members' kind of character, on members' rig and
/// moves, each in a fixed look from `Coaches/<id>/look.json`. A coach may wear parts of its own
/// (`Coaches/<id>/art/<slot>/<variant>`, such as 毛头's whistle and jacket), which the editor never
/// lists, and any member part. A coach the API lists without a folder here has no character in
/// this build; the screens show a stand-in for it.
public enum CoachCharacter {
    /// What a coach plays: `idle` loops, `cheer` plays once, `crying` loops (being fired).
    public enum Move: String, CaseIterable, Sendable {
        case idle
        case cheer
        case crying
    }

    /// Whether this build has the coach's character.
    public static func exists(_ coach: String) -> Bool {
        FileManager.default.fileExists(atPath: folder(coach).appendingPathComponent("look.json").path)
    }

    /// The coaches this build draws, by id, sorted.
    public static var bundled: [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        return names.filter(exists).sorted()
    }

    /// The coach's look and persona.
    public static func look(_ coach: String) throws(AvatarError) -> Look {
        let data = try file(coach, "look.json")
        let stored: StoredLook
        do {
            stored = try JSONDecoder().decode(StoredLook.self, from: data)
        } catch {
            throw .malformedJSON("\(coach)/look.json: \(error)")
        }
        guard stored.version == 1 else { throw .unsupportedVersion(stored.version) }
        guard let persona = Persona(rawValue: stored.persona) else {
            throw .malformedJSON("\(coach)/look.json: persona \(stored.persona)")
        }
        var colors: [Slot: RGBAColor] = [:]
        for (slot, hex) in stored.colors ?? [:] {
            guard let color = RGBAColor(hex: hex) else { throw .malformedJSON("\(coach)/look.json: color \(hex)") }
            colors[Slot(slot)] = color
        }
        let variants = Dictionary(uniqueKeysWithValues: stored.look.map { (Slot($0.key), $0.value) })
        return Look(outfit: Outfit(variants, colors: colors), persona: persona, species: stored.species)
    }

    public static func figure(_ coach: String) throws(AvatarError) -> Figure {
        let look = try look(coach)
        return try Figure(
            rig: PlaceholderCharacter.rig(), outfit: look.outfit, art: CoachArt(folder: folder(coach)))
    }

    /// The coach's persona's idle and cheer, with its species' moves, and 注销账号's teary loop
    /// for being fired.
    public static func clip(_ move: Move, coach: String) throws(AvatarError) -> Clip {
        let look = try look(coach)
        switch move {
        case .idle: return try PlaceholderCharacter.clip("idle", persona: look.persona, species: look.species)
        case .cheer: return try PlaceholderCharacter.clip("cheer", persona: look.persona, species: look.species)
        case .crying: return try PlaceholderCharacter.teary(persona: look.persona)
        }
    }

    /// A coach's fixed look: what it wears, how it moves, and the species whose moves it plays.
    public struct Look: Hashable, Sendable {
        public let outfit: Outfit
        public let persona: Persona
        public let species: String?
    }

    private struct StoredLook: Decodable {
        let version: Int
        let persona: String
        let species: String?
        let look: [String: String]
        let colors: [String: String]?
    }

    private static func file(_ coach: String, _ path: String) throws(AvatarError) -> Data {
        guard let data = try? Data(contentsOf: folder(coach).appendingPathComponent(path)) else {
            throw .missingFile("\(coach)/\(path)")
        }
        return data
    }

    private static func folder(_ coach: String) -> URL { root.appendingPathComponent(coach) }

    /// The copied `Coaches` folder inside this package's resource bundle.
    private static var root: URL {
        (Bundle.module.resourceURL ?? Bundle.module.bundleURL).appendingPathComponent("Coaches")
    }
}

/// Reads a coach's own parts from its folder, and every other part from members' art.
private struct CoachArt: ArtSource {
    let folder: URL

    func text(at path: String) -> String? {
        let own = folder.appendingPathComponent("art").appendingPathComponent(path)
        return (try? String(contentsOf: own, encoding: .utf8)) ?? BundledArt().text(at: path)
    }
}
