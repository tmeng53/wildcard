/// The scene a squad picked. A scene swaps only its signature group (signature, buttons,
/// selected states, the score and the scene band); neutrals and meaning accents stay fixed.
public enum SceneTheme: String, CaseIterable, Sendable {
    case pool
    case track
    case gym
    case tennis
    case climbing

    public var colors: SceneColors {
        switch self {
        case .pool:
            SceneColors(
                signature: Palette.poolSignature, shade: Palette.poolShade, wash: Palette.poolWash,
                onSignature: Palette.white, signatureText: Palette.poolText, progressFill: Palette.poolSignature)
        case .track:
            SceneColors(
                signature: Palette.trackSignature, shade: Palette.trackShade, wash: Palette.trackWash,
                onSignature: Palette.white, signatureText: Palette.trackShade, progressFill: Palette.trackSignature)
        case .gym:
            // Graphite is dark, so text, icons and progress on it are volt.
            SceneColors(
                signature: Palette.graphite, shade: Palette.black, wash: Palette.gymWash,
                onSignature: Palette.volt, signatureText: Palette.graphite, progressFill: Palette.volt)
        case .tennis:
            SceneColors(
                signature: Palette.tennisSignature, shade: Palette.tennisShade, wash: Palette.tennisWash,
                onSignature: Palette.white, signatureText: Palette.tennisShade, progressFill: Palette.tennisSignature)
        case .climbing:
            SceneColors(
                signature: Palette.climbingSignature, shade: Palette.climbingShade, wash: Palette.climbingWash,
                onSignature: Palette.white, signatureText: Palette.climbingShade,
                progressFill: Palette.climbingSignature)
        }
    }
}

/// One scene's signature group.
public struct SceneColors: Sendable, Hashable {
    /// 打卡 and primary actions (solid fills), selected states, the score and the scene band.
    public let signature: SRGBColor
    /// The base edge of raised signature buttons.
    public let shade: SRGBColor
    /// The light scene background.
    public let wash: SRGBColor
    /// Labels and icons drawn on `signature`.
    public let onSignature: SRGBColor
    /// Signature-colored text and the score on `wash` or white.
    public let signatureText: SRGBColor
    /// Progress bars and the ring of an avatar who trained.
    public let progressFill: SRGBColor
}

/// An accent used only as an icon tint, a dot or a tag (wash background with dark text),
/// never as a large fill or a solid disc.
public struct AccentFamily: Sendable, Hashable {
    /// Dots and rings.
    public let tint: SRGBColor
    /// Icons on light surfaces and glass: 3:1 or more.
    public let ink: SRGBColor
    /// Tag backgrounds.
    public let wash: SRGBColor
    /// Tag text on `wash`: 4.5:1 or more.
    public let text: SRGBColor

    public init(tint: SRGBColor, ink: SRGBColor, wash: SRGBColor, text: SRGBColor) {
        self.tint = tint
        self.ink = ink
        self.wash = wash
        self.text = text
    }
}

/// What a check-in means, each with its accent.
public enum Meaning: String, CaseIterable, Sendable {
    /// 练了.
    case trained
    /// 健康餐.
    case fresh
    /// 坦白放纵餐.
    case indulgence
    /// 今日免责声明.
    case disclaimer

    public func accent(in theme: SceneTheme) -> AccentFamily {
        switch self {
        // Follows the scene for now; a fixed color would be a one-line change here.
        case .trained: theme.colors.trainedAccent
        case .fresh:
            AccentFamily(tint: Palette.mint, ink: Palette.mintInk, wash: Palette.mintWash, text: Palette.mintText)
        case .indulgence:
            AccentFamily(tint: Palette.amber, ink: Palette.amberInk, wash: Palette.amberWash, text: Palette.amberText)
        case .disclaimer:
            AccentFamily(
                tint: Palette.lavender, ink: Palette.lavenderInk, wash: Palette.lavenderWash, text: Palette.lavenderText
            )
        }
    }
}

extension SceneColors {
    /// The scene's signature group used as an accent.
    public var trainedAccent: AccentFamily {
        AccentFamily(tint: progressFill, ink: signatureText, wash: wash, text: signatureText)
    }
}

/// What a color is for. Each role's pairing rules are tested in `DesignSystemTests`.
public enum ColorRole: String, CaseIterable, Sendable {
    case canvas
    case surface
    case divider
    case textPrimary
    case textSecondary
    /// Large type and decoration only.
    case textTertiary

    case signature
    case signatureShade
    case signatureWash
    case onSignature
    case signatureText
    case progressFill

    case meaningTrained, meaningTrainedInk, meaningTrainedWash, meaningTrainedText
    case meaningFresh, meaningFreshInk, meaningFreshWash, meaningFreshText
    case meaningIndulgence, meaningIndulgenceInk, meaningIndulgenceWash, meaningIndulgenceText
    case meaningDisclaimer, meaningDisclaimerInk, meaningDisclaimerWash, meaningDisclaimerText

    /// The color this role takes in a scene.
    public func color(in theme: SceneTheme) -> SRGBColor {
        switch source {
        case .fixed(let color): color
        case .scene(let path): theme.colors[keyPath: path]
        case .accent(let meaning, let path): meaning.accent(in: theme)[keyPath: path]
        }
    }

    private enum Source {
        case fixed(SRGBColor)
        case scene(KeyPath<SceneColors, SRGBColor>)
        case accent(Meaning, KeyPath<AccentFamily, SRGBColor>)
    }

    private var source: Source {
        switch self {
        case .canvas: .fixed(Palette.white)
        case .surface: .fixed(Palette.mist)
        case .divider: .fixed(Palette.line)
        case .textPrimary: .fixed(Palette.ink)
        case .textSecondary: .fixed(Palette.inkSecondary)
        case .textTertiary: .fixed(Palette.inkTertiary)
        case .signature: .scene(\.signature)
        case .signatureShade: .scene(\.shade)
        case .signatureWash: .scene(\.wash)
        case .onSignature: .scene(\.onSignature)
        case .signatureText: .scene(\.signatureText)
        case .progressFill: .scene(\.progressFill)
        case .meaningTrained: .accent(.trained, \.tint)
        case .meaningTrainedInk: .accent(.trained, \.ink)
        case .meaningTrainedWash: .accent(.trained, \.wash)
        case .meaningTrainedText: .accent(.trained, \.text)
        case .meaningFresh: .accent(.fresh, \.tint)
        case .meaningFreshInk: .accent(.fresh, \.ink)
        case .meaningFreshWash: .accent(.fresh, \.wash)
        case .meaningFreshText: .accent(.fresh, \.text)
        case .meaningIndulgence: .accent(.indulgence, \.tint)
        case .meaningIndulgenceInk: .accent(.indulgence, \.ink)
        case .meaningIndulgenceWash: .accent(.indulgence, \.wash)
        case .meaningIndulgenceText: .accent(.indulgence, \.text)
        case .meaningDisclaimer: .accent(.disclaimer, \.tint)
        case .meaningDisclaimerInk: .accent(.disclaimer, \.ink)
        case .meaningDisclaimerWash: .accent(.disclaimer, \.wash)
        case .meaningDisclaimerText: .accent(.disclaimer, \.text)
        }
    }
}
