#if os(iOS)
import Contracts
import DesignSystem
import DesignSystemUI
import SwiftUI

/// The top of the 请假条 page: the date and the page's name, small, × on the right; under them
/// 请假｜休息, whether the day off is leave or a rest the member planned, as the system's
/// segmented control; then the 日期 strip (补打卡), whose days with a 练了 can't be picked. The
/// date and name follow the day picked: 今日请假条 or 今日休息 for today, 请假条 or 休息 before.
struct DisclaimerHeader: View {
    @Environment(\.sceneTheme) private var theme
    let model: TodayModel
    /// The past day picked; nil is today.
    @Binding var day: LocalDay?
    /// 休息 rather than 请假.
    @Binding var restDay: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            header
            Picker(selection: $restDay) {
                Text(copy: "请假", bundle: .module).tag(false)
                Text(copy: "休息", bundle: .module).tag(true)
            } label: {
                Text(copy: "请假还是休息", bundle: .module)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("disclaimer.kind")
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
                    switch (day == nil, restDay) {
                    case (true, false): Text(copy: "今日请假条", bundle: .module)
                    case (false, false): Text(copy: "请假条", bundle: .module)
                    case (true, true): Text(copy: "今日休息", bundle: .module)
                    case (false, true): Text(copy: "休息", bundle: .module)
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
            .accessibilityLabel(Text(copy: "关闭", bundle: .module))
            .accessibilityIdentifier("disclaimer.close")
        }
    }
}
#endif
