#if canImport(SwiftUI)
import AvatarArt
import AvatarDomain
import AvatarUI
import CheckInDomain
import Contracts
import DesignSystem
import DesignSystemUI
import HomeWidgetDomain
import SportsUI
import SwiftUI

/// 我的一周, the small widget: my week's x/y, whether I trained today, my character standing in
/// the corner and the week's days along the bottom, as the squad card's second page draws them.
public struct WeekWidget: View {
    @Environment(\.sceneTheme) private var theme
    private let board: WidgetBoard

    public init(board: WidgetBoard) {
        self.board = board
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel(Text("我的一周", bundle: .module))
            HStack(alignment: .firstTextBaseline, spacing: Space.xxs / 2) {
                Score(count: board.mine.trainedDays, goal: board.mine.plannedDays, size: .card)
                Text("天", bundle: .module)
                    .typeStyle(TypeRamp.denominator(of: TypeRamp.scoreCard))
                    .foregroundStyle(Color(role: .fgSubtle, in: theme))
            }
            .lineLimit(1)
            status
                .typeStyle(TypeRamp.label)
                .foregroundStyle(Color(role: board.myStatus == .notCheckedIn ? .fgMuted : .fgAccent, in: theme))
                .lineLimit(1)
            Spacer(minLength: Space.xs)
            WeekDayRow(days: days, today: board.week.today, size: .tiny)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(alignment: .topTrailing) {
            WidgetCharacter(look: board.mates.first(where: \.isMe)?.look)
                .frame(width: WidgetMetrics.figureWidth)
                .offset(x: Space.xs, y: -Space.xxs)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("我的一周", bundle: .module))
        .accessibilityValue(
            Text("\(board.mine.trainedDays)/\(board.mine.plannedDays) 天，\(status)", bundle: .module))
    }

    private var status: Text {
        switch board.myStatus {
        case .trained: Text("今天练了", bundle: .module)
        case .disclaimer: Text("今天请假", bundle: .module)
        case .notCheckedIn: Text("今天还没练", bundle: .module)
        }
    }

    /// Each day as the squad card's calendar draws it.
    private var days: [WeekDayStatus] {
        zip(board.week.days, board.week.activities).map { status, activity in
            switch status {
            case .trained: .trained(symbol: activity.flatMap(Self.symbol))
            case .disclaimer: .excused
            case .restDay: .restDay
            case .open: .open
            }
        }
    }

    /// A trained day's sport icon. SportsUI draws sports on iOS only, so the macOS build of this
    /// package (`swift test`) leaves the icon out.
    private static func symbol(_ activity: Activity) -> String? {
        #if os(iOS)
        return activity.symbol
        #else
        return nil
        #endif
    }
}

/// A member standing still, in their look; the default character before they made one.
struct WidgetCharacter: View {
    let look: CharacterLook?

    var body: some View {
        if let player = Self.player(look) {
            let frame = player.restFrame
            CharacterCanvas(drawing: frame.drawing, placements: frame.placements)
                .aspectRatio(player.drawing.width / player.drawing.height, contentMode: .fit)
                .accessibilityHidden(true)
        }
    }

    static func player(_ look: CharacterLook?) -> CharacterPlayer? {
        guard
            let figure = try? PlaceholderCharacter.figure(wearing: look.map(Outfit.init) ?? PlaceholderCharacter.lifter)
        else { return nil }
        return try? CharacterPlayer(figure: figure, idle: .still)
    }
}

/// Sizes that belong to the widgets only.
enum WidgetMetrics {
    /// My character in the small widget's corner.
    static let figureWidth: Double = 64
    /// A head on the medium widget, four to a row, and its width with today's ring around it.
    static let head: Double = 24
    static let ringed = head + 2 * (Sizing.ringGap + Sizing.ringWidth)
    /// The coach's head on the medium widget.
    static let coachHead: Double = 26
    /// The coach's ink dot.
    static let dot: Double = 8
    /// The medium widget's 打卡.
    static let button: Double = 32
}
#endif
