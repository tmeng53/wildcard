#if os(iOS)
import Contracts
import DesignSystem
import DesignSystemUI
import SwiftUI

/// The top of the 请假条 page: the date and the page's name, small, × on the right, and under
/// them the 日期 strip (补打卡), whose days with a 练了 can't be picked. The date and name follow
/// the day picked: 今日请假条 for today, 请假条 for a day before.
struct DisclaimerHeader: View {
    @Environment(\.sceneTheme) private var theme
    let model: TodayModel
    /// The past day picked; nil is today.
    @Binding var day: LocalDay?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            header
            if let today = model.disclaimerDays.last, model.disclaimerDays.count > 1 {
                DayPick(
                    days: model.disclaimerDays, blocked: model.blockedForDisclaimer,
                    picked: Binding {
                        day ?? today
                    } set: {
                        day = $0 == today ? nil : $0
                    })
            }
        }
    }

    private var header: some View {
        HStack(spacing: Space.s) {
            VStack(alignment: .leading, spacing: 0) {
                Text(day?.date ?? .now, format: .dateTime.month(.defaultDigits).day().weekday(.abbreviated))
                    .typeStyle(TypeRamp.label)
                    .foregroundStyle(Color(role: .fgDefault, in: theme))
                Group {
                    if day == nil {
                        Text("今日请假条", bundle: .module)
                    } else {
                        Text("请假条", bundle: .module)
                    }
                }
                .typeStyle(TypeRamp.label)
                .foregroundStyle(Color(role: .fgMuted, in: theme))
                .accessibilityAddTraits(.isHeader)
            }
            Spacer()
            Button {
                model.cancel()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: Sizing.smallIcon, weight: .medium))
                    .foregroundStyle(Color(role: .fgDefault, in: theme))
                    .frame(width: Sizing.minimumTapTarget, height: Sizing.minimumTapTarget, alignment: .trailing)
            }
            .accessibilityLabel(Text("关闭", bundle: .module))
            .accessibilityIdentifier("disclaimer.close")
        }
    }
}
#endif
