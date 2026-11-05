import Contracts
import DesignSystem

extension SceneTheme {
    /// Takes the catalog's scenes, so one added since this build is named and coloured as the
    /// catalog says (a scene with a colour that isn't `#RRGGBB` is left out, and shows as the gym).
    public static func list(_ scenes: [CatalogScene]) {
        var listed: [SceneTheme: Listing] = [:]
        for scene in scenes {
            let colors = scene.colors
            guard let id = SceneTheme(rawValue: scene.id.rawValue),
                let signature = SRGBColor(hex: colors.signature), let onSignature = SRGBColor(hex: colors.onSignature),
                let wash = SRGBColor(hex: colors.wash), let text = SRGBColor(hex: colors.text),
                let floor = SRGBColor(hex: colors.floor)
            else { continue }
            listed[id] = Listing(
                colors: .light(accent: signature, subtle: wash, text: text, floor: floor, onAccent: onSignature),
                simplifiedChinese: scene.names.simplifiedChinese, english: scene.names.english,
                traditionalChinese: scene.names.traditionalChinese)
        }
        list(listed)
    }
}
