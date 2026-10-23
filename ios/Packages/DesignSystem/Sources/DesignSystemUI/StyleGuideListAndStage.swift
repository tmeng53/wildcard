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
                SwitchRow(Text("被戳提醒", bundle: .module), systemImage: "hand.tap", isOn: $pokes, showsDivider: false)
            }
            // A plain menu (设置): no icons, no chevrons, an ink switch.
            VStack(spacing: 0) {
                ListRow(Text("性格", bundle: .module), value: Text("淡人", bundle: .module), showsChevron: false) {}
                SwitchRow(Text("每日提醒", bundle: .module), isOn: $dailyReminder, showsDivider: false, tint: .ink)
            }
        }
    }
}

// MARK: - 9 The character's stage

struct StageSection: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.sceneTheme) private var theme
    @State private var isTalking = true

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            SectionTitle(number: 9, title: Text("小人舞台和气泡", bundle: .module))
            CharacterStage {
                VStack(spacing: Space.xxs) {
                    if isTalking {
                        SpeechBubble(Text("冲冲冲！", bundle: .module))
                            .transition(.speech(reduceMotion: reduceMotion))
                    }
                    Image(systemName: "figure.arms.open")
                        .font(.system(size: Sizing.characterBust * 1.4))
                        .foregroundStyle(Color(role: .fgDefault, in: theme))
                }
                .frame(maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, Space.xl)
                .overlay(alignment: .topTrailing) {
                    HeaderButton(Text("随机换一个", bundle: .module), systemImage: "dice", on: .scene) {
                        withAnimation(.wildcard(Motion.sheet, reduceMotion: reduceMotion)) { isTalking.toggle() }
                    }
                    .padding(Space.xs)
                }
            }
            .frame(height: 300)
            GuideGroup(Text("点人看状态：整段显示", bundle: .module)) {
                HStack(alignment: .bottom, spacing: Space.s) {
                    SpeechBubble(
                        Text("腿还在酸，今天先躺平，明天一定练。", bundle: .module),
                        kind: .info(title: Text("小美 · 请假条", bundle: .module)), on: .page)
                    SpeechBubble(Text("可以", bundle: .module), on: .page)
                }
            }
        }
    }
}
#endif
