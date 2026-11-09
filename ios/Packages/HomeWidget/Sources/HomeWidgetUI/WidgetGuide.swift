#if canImport(SwiftUI)
import Contracts
import DesignSystem
import DesignSystemUI
import HomeWidgetDomain
import SwiftUI

/// 设置 › 桌面小组件: what the widgets show, drawn from the sample squad as the home screen shows
/// them, then the three steps to put one there (iOS lets no app add a widget itself).
public struct WidgetGuide: View {
    @Environment(\.sceneTheme) private var theme
    private let day: LocalDay

    /// - Parameter now: the time the sample widgets show, on the phone's clock.
    public init(now: Date) {
        day = LocalDay(at: now, in: .current)
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("桌面小组件", bundle: .module)
                    .typeStyle(TypeRamp.taskTitle)
                    .foregroundStyle(Color(role: .fgDefault, in: theme))
                    .accessibilityAddTraits(.isHeader)
                Text("不用打开 App，也能看到这周练了几天、小队今天谁练了。", bundle: .module)
                    .typeStyle(TypeRamp.callout)
                    .foregroundStyle(Color(role: .fgMuted, in: theme))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, Space.xxs)
                previews
                    .padding(.top, Space.l)
                SectionLabel(Text("怎么加", bundle: .module))
                    .padding(.top, Space.l)
                    .padding(.bottom, Space.xxs)
                stepRow(number: 1, Text("回到桌面，长按空白处，直到图标开始晃", bundle: .module))
                stepRow(number: 2, Text("点左上角「编辑」，再点「添加小组件」", bundle: .module))
                stepRow(number: 3, Text("搜「外卡」，选大小，点「添加小组件」", bundle: .module), isLast: true)
            }
            .padding(.horizontal, Space.pageMargin)
            .padding(.top, Space.xs)
            .padding(.bottom, Space.l)
        }
        .scrollIndicators(.hidden)
        .background(Color(role: .bgCanvas, in: theme))
        .pushedPage()
        .accessibilityIdentifier("widgetGuide.page")
    }

    /// The small and the medium widget, scaled to fit the page, on the home screen's grey.
    private var previews: some View {
        VStack(spacing: Space.s) {
            scaled(.small) { WeekWidget(board: SampleBoard.board(on: day)) { _ in PostWorkoutLabel() } }
            scaled(.medium) { SquadWidget(board: SampleBoard.board(on: day)) { _ in PostWorkoutLabel() } }
            Text("小号、中号都有", bundle: .module)
                .typeStyle(TypeRamp.footnote)
                .foregroundStyle(Color(role: .fgMuted, in: theme))
        }
        // Only pictures here: the widgets' own links stay on the home screen.
        .allowsHitTesting(false)
        .frame(maxWidth: .infinity)
        .padding(.vertical, Space.m)
        .background(Color(role: .bgSubtle, in: theme), in: RoundedRectangle(cornerRadius: Radius.menu))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("小号、中号都有", bundle: .module))
        .accessibilityIdentifier("widgetGuide.previews")
    }

    /// A widget at `previewScale` of its size, taking only the room it shows in.
    private func scaled(_ size: WidgetSize, @ViewBuilder content: () -> some View) -> some View {
        WidgetFace(size, content: content)
            .scaleEffect(Self.previewScale)
            .frame(width: size.width * Self.previewScale, height: size.height * Self.previewScale)
    }

    /// One step of putting a widget on iOS 26's home screen, in its own words.
    private func stepRow(number: Int, _ step: Text, isLast: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.s) {
            Text(verbatim: "\(number)")
                .typeStyle(TypeRamp.scoreSmall)
                .foregroundStyle(Color(role: .fgDefault, in: theme))
                .frame(minWidth: Space.m, alignment: .leading)
            step
                .typeStyle(TypeRamp.body)
                .foregroundStyle(Color(role: .fgDefault, in: theme))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.vertical, Space.s)
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle()
                    .fill(Color(role: .borderDefault, in: theme))
                    .frame(height: Sizing.hairline)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("widgetGuide.step\(number)")
    }

    /// The widgets drawn at this much of their size, so the medium one fits the smallest phone.
    private static let previewScale = 0.72
}
#endif
