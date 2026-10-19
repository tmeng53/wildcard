#if canImport(SwiftUI)
import DesignSystem
import SwiftUI

/// A thin track filled in the scene's progress color. It never turns red and stops at full.
/// A fill too faint to hold its shape on white (gym's volt) gets a signature edge.
public struct ProgressBar: View {
    @Environment(\.sceneTheme) private var theme
    private let fraction: Double

    /// `fraction` is clamped to 0...1.
    public init(fraction: Double) {
        self.fraction = min(max(fraction, 0), 1)
    }

    public var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color(role: .divider, in: theme))
                Capsule()
                    .fill(Color(role: .progressFill, in: theme))
                    .overlay {
                        if theme.colors.progressFill.contrastRatio(with: Palette.white) < 3 {
                            Capsule().strokeBorder(Color(role: .signature, in: theme), lineWidth: 1)
                        }
                    }
                    .frame(width: proxy.size.width * fraction)
            }
        }
        .frame(height: Space.xs)
        .accessibilityHidden(true)
    }
}
#endif
