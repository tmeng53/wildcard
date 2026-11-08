import AvatarDomain
import Foundation

/// Who stands in a store's window on 商店街: a character wearing the store's clothes, and how it
/// moves. Read from `stores/<id>.json` beside the store's badge, so a store's model is art an
/// admin can put (`put_art`) like any other file.
public struct StoreWindow: Hashable, Sendable {
    public let outfit: Outfit
    public let persona: Persona

    public init(outfit: Outfit, persona: Persona) {
        (self.outfit, self.persona) = (outfit, persona)
    }

    /// The only `version` of a store's window file this build reads.
    public static let currentVersion = 1

    /// `{"version": 1, "persona": "energetic", "look": {"body": "corgi", "top": "warmup-hoodie"},
    /// "colors": {"hair": "#2A2333"}}`. A persona this build doesn't know moves as `.energetic`,
    /// and a colour that isn't `#rrggbb` is left out.
    public static func decode(_ data: Data) throws(AvatarError) -> StoreWindow {
        let file: File = try decodeJSON(data, version: currentVersion, shape: File.shape)
        return StoreWindow(
            outfit: Outfit(
                Dictionary(uniqueKeysWithValues: file.look.map { (Slot($0.key), $0.value) }),
                colors: (file.colors ?? [:]).reduce(into: [:]) { colors, entry in
                    if let color = RGBAColor(hex: entry.value) { colors[Slot(entry.key)] = color }
                }),
            persona: Persona(rawValue: file.persona) ?? .energetic)
    }

    private struct File: Decodable {
        // `look` and `colors` are keyed by slot, so any key goes.
        static let shape = JSONShape.object(["version": .value, "persona": .value, "look": .value, "colors": .value])

        let persona: String
        let look: [String: String]
        let colors: [String: String]?
    }
}

extension PlaceholderCharacter {
    /// The model in `store`'s window, `stores/<id>.json`; nil for a store without one.
    public static func storeWindow(_ store: String) -> StoreWindow? {
        (try? file("stores/\(store).json")).flatMap { try? StoreWindow.decode($0) }
    }
}
