#if canImport(SwiftUI)
import DesignSystem
import SwiftUI

// MARK: - 8 List

struct ListSection: View {
    @State private var dailyReminder = true
    @State private var pokes = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            SectionTitle(number: 8, title: Text("列表", bundle: .module))
            VStack(spacing: 0) {
                ListRow(Text("性格", bundle: .module), systemImage: "sparkles", value: Text("淡人", bundle: .module)) {}
                ListRow(Text("穿搭", bundle: .module), systemImage: "tshirt") {}
                ListRow(
                    Text("每周计划", bundle: .module), systemImage: "calendar", value: Text("练 5 休 2", bundle: .module)
                ) {}
                SwitchRow(Text("每日提醒", bundle: .module), systemImage: "bell", isOn: $dailyReminder)
                    .accessibilityIdentifier("styleguide.switch")
                SwitchRow(Text("拍一拍", bundle: .module), systemImage: "hand.tap", isOn: $pokes, showsDivider: false)
            }
            // A plain menu (设置): no icons, no chevrons, an ink switch.
            VStack(spacing: 0) {
                ListRow(Text("性格", bundle: .module), value: Text("淡人", bundle: .module), showsChevron: false) {}
                SwitchRow(Text("每日提醒", bundle: .module), isOn: $dailyReminder, showsDivider: false)
            }
            .accentTone(.ink)
        }
    }
}
#endif
