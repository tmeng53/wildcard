#if os(iOS)
import DesignSystem
import DesignSystemUI
import SwiftUI

/// The words the widget gallery shows for each widget, from this package's catalog. Strings,
/// not `Text`: WidgetKit's `configurationDisplayName` and `description` take only a `Text` made
/// from a key or a literal and stop the extension on any other (`Text(copy:)` is made from an
/// `AttributedString`), so no widget would draw at all.
public enum WidgetCopy {
    public static var weekName: String { String(copy: "我的一周", bundle: .module) }
    public static var weekDescription: String { String(copy: "本周练了几天", bundle: .module) }
    public static var squadName: String { String(copy: "小队今天", bundle: .module) }
    public static var squadDescription: String { String(copy: "今天谁练了", bundle: .module) }
}

/// A widget with no board to show: who isn't signed in or isn't in a squad yet, or a squad it
/// can't read right now. A tap opens the
/// app, where they do it.
public struct WidgetNotice: View {
    public enum Reason: Sendable {
        case signedOut
        case noSquad
        case unavailable
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
                case .signedOut: Text(copy: "还没登录", bundle: .module)
                case .noSquad: Text(copy: "还没加入小队", bundle: .module)
                case .unavailable: Text(copy: "暂时连不上", bundle: .module)
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
