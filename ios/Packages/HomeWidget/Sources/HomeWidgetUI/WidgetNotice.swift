#if canImport(SwiftUI)
import DesignSystem
import DesignSystemUI
import SwiftUI

/// The words the widget gallery shows for each widget, from this package's catalog.
public enum WidgetCopy {
    public static var weekName: Text { Text("我的一周", bundle: .module) }
    public static var weekDescription: Text { Text("本周练了几天", bundle: .module) }
    public static var squadName: Text { Text("小队和教练", bundle: .module) }
    public static var squadDescription: Text { Text("今天谁练了，教练说了什么", bundle: .module) }
}

/// A widget with no board to show: who isn't signed in or isn't in a squad yet, or a squad it
/// can't read right now. A tap opens the
/// app, where they do it.
public struct WidgetNotice: View {
    public enum Reason: Sendable {
        case signedOut
        case noSquad
        case unavailable
        /// The coach face for a squad with no coach.
        case noCoach
    }

    @Environment(\.sceneTheme) private var theme
    private let reason: Reason

    public init(_ reason: Reason) {
        self.reason = reason
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            WidgetCharacter(look: nil)
                .frame(width: WidgetMetrics.figureWidth)
            Spacer(minLength: 0)
            Group {
                switch reason {
                case .signedOut: Text("还没登录", bundle: .module)
                case .noSquad: Text("还没加入小队", bundle: .module)
                case .unavailable: Text("暂时连不上", bundle: .module)
                case .noCoach: Text("还没请教练", bundle: .module)
                }
            }
            .typeStyle(TypeRamp.footnoteEmphasis)
            .foregroundStyle(Color(role: .fgDefault, in: theme))
            .lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}
#endif
