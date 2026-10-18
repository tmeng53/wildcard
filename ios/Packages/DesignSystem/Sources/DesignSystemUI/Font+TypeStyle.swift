#if canImport(SwiftUI)
import CoreText
import DesignSystem
import Foundation
import SwiftUI

/// Registers the bundled Barlow Condensed cuts with the process, once.
public enum ScoreboardFont {
    /// The PostScript names that registered, for tests and diagnostics.
    public static var registeredNames: [String] { registration }

    /// Safe to call from any thread; the work runs the first time only.
    public static func register() {
        _ = registration
    }

    private static let registration: [String] = {
        let urls = Bundle.module.urls(forResourcesWithExtension: "ttf", subdirectory: "Fonts") ?? []
        return urls.sorted { $0.lastPathComponent < $1.lastPathComponent }.compactMap { url in
            // Registering twice (for example in previews) reports an error but leaves the font usable.
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            guard
                let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
                let first = descriptors.first
            else { return nil }
            return CTFontDescriptorCopyAttribute(first, kCTFontNameAttribute) as? String
        }
    }()
}

extension Font {
    /// The font for a type style. It scales with Dynamic Type along the style's anchor.
    public static func wildcard(_ style: TypeStyle) -> Font {
        if case .scoreboard = style.face { ScoreboardFont.register() }
        return .custom(style.face.postScriptName, size: style.size, relativeTo: style.anchor.textStyle)
    }
}

extension ScaleAnchor {
    var textStyle: Font.TextStyle {
        switch self {
        case .largeTitle: .largeTitle
        case .title: .title
        case .title2: .title2
        case .title3: .title3
        case .headline: .headline
        case .body: .body
        case .callout: .callout
        case .subheadline: .subheadline
        case .footnote: .footnote
        case .caption: .caption
        }
    }
}

extension View {
    /// Applies a type style's font and tracking.
    public func typeStyle(_ style: TypeStyle) -> some View {
        font(.wildcard(style)).tracking(style.tracking)
    }
}
#endif
