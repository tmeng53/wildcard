#if os(iOS)
import DesignSystem
import DesignSystemUI
import SwiftUI

/// A widget drawn in the app as the home screen shows it: its size, its margin inside and its
/// corners, for the 桌面小组件 guide and the `-widgets` preview UI tests read. With `edgeToEdge`
/// (`ScheduleWidget`), no margin, on the scene's backdrop, as the extension draws it.
public struct WidgetFace<Content: View>: View {
    @Environment(\.sceneTheme) private var theme
    private let size: WidgetSize
    private let content: Content
    private let bleeds: Bool

    public init(_ size: WidgetSize, edgeToEdge: Bool = false, @ViewBuilder content: () -> Content) {
        self.size = size
        self.content = content()
        bleeds = edgeToEdge
    }

    public var body: some View {
        content
            .padding(bleeds ? 0 : Space.m)
            .frame(width: size.width, height: size.height)
            .background {
                if bleeds { ScheduleWidget.Backdrop() } else { Color(role: .bgCanvas, in: theme) }
            }
            .clipShape(RoundedRectangle(cornerRadius: Radius.menu - 2, style: .continuous))
    }
}

/// A widget's size on a 6.1" to 6.3" iPhone.
public enum WidgetSize: Sendable {
    /// 170 points square.
    case small
    /// 364 by 170 points.
    case medium

    public var width: Double { self == .small ? WidgetMetrics.small : WidgetMetrics.medium }
    public var height: Double { WidgetMetrics.small }
}
#endif
