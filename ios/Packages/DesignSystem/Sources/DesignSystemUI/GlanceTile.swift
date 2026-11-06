#if canImport(SwiftUI)
import DesignSystem
import SwiftUI

/// A brand tile that opens a page of the member's own, on graphite: a number and its title on
/// one line (W3 出赛表, 21 我的动态), an optional quiet line under them, and a glimpse of the page
/// at the bottom (an 编辑 pill, the newest posts). 我 sets two side by side under the player
/// card, each half the page wide and as tall as the other, so they read as one set.
public struct GlanceTile<Glimpse: View>: View {
    @Environment(\.sceneTheme) private var theme
    private let figure: Text
    private let figureStyle: TypeStyle
    private let title: Text
    private let caption: Text?
    private let action: () -> Void
    private let glimpse: Glimpse

    /// `figure` is the tile's number (W45, 128), in `figureStyle`: `scoreWeek` for a week,
    /// `scoreCard` for a count.
    public init(
        figure: Text, figureStyle: TypeStyle = TypeRamp.scoreCard, title: Text, caption: Text? = nil,
        action: @escaping () -> Void, @ViewBuilder glimpse: () -> Glimpse
    ) {
        self.figure = figure
        self.figureStyle = figureStyle
        self.title = title
        self.caption = caption
        self.action = action
        self.glimpse = glimpse()
    }

    public var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: Space.xs) {
                HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
                    figure
                        .typeStyle(figureStyle)
                        .foregroundStyle(Color(role: .fgOnBrand, in: theme))
                        .fixedSize()
                    title
                        .typeStyle(TypeRamp.calloutEmphasis)
                        .foregroundStyle(Color(role: .fgOnBrand, in: theme))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                if let caption {
                    caption
                        .typeStyle(TypeRamp.footnote)
                        .foregroundStyle(Color(role: .fgOnInkMuted, in: theme))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                glimpse
            }
            .padding(Space.s)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(
                Color(role: .bgBrand, in: theme),
                in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
            )
            .contentShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        }
        .buttonStyle(PressableButtonStyle())
    }
}

/// A white pill at the bottom of a `GlanceTile` saying what the tile does (编辑): part of the
/// tile's button, never a button of its own.
public struct GlanceAction: View {
    @Environment(\.sceneTheme) private var theme
    private let title: Text
    private let systemImage: String

    public init(_ title: Text, systemImage: String) {
        (self.title, self.systemImage) = (title, systemImage)
    }

    public var body: some View {
        HStack(spacing: Space.xxs) {
            Image(systemName: systemImage)
                .font(.system(size: Sizing.smallIcon * 0.9, weight: .semibold))
                .accessibilityHidden(true)
            title
                .typeStyle(TypeRamp.calloutEmphasis)
        }
        .foregroundStyle(Color(role: .bgBrand, in: theme))
        .frame(maxWidth: .infinity, minHeight: Sizing.compactControl)
        .background(Color(role: .fgOnBrand, in: theme), in: Capsule())
    }
}

/// The tile's sizes, for what goes in its glimpse.
public enum GlanceTileMetrics {
    /// How many of the newest posts a glimpse shows, side by side.
    public static let posts = 3
}
#endif
