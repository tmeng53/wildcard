#if canImport(SwiftUI)
import DesignSystem
import SwiftUI

// MARK: - 9 The character's stage

struct StageSection: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.sceneTheme) private var theme
    @State private var isTalking = true
    @State private var isLit = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            SectionTitle(number: 9, title: Text(copy: "小人舞台和气泡", bundle: .module))
            CharacterStage(issued: .now) {
                VStack(spacing: Space.xxs) {
                    if isTalking {
                        SpeechBubble(Text(copy: "冲冲冲！", bundle: .module))
                            .transition(.speech(reduceMotion: reduceMotion))
                    }
                    Image(systemName: "figure.arms.open")
                        .font(.system(size: Sizing.characterBust * 1.4))
                        .foregroundStyle(Color(role: .fgOnBrand, in: theme))
                }
                .frame(maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, CharacterStage<EmptyView, EmptyView>.stubHeight)
                .overlay(alignment: .topTrailing) {
                    HeaderButton(Text(copy: "随机换一个", bundle: .module), systemImage: "dice", on: .scene) {
                        withAnimation(.wildcard(Motion.sheet, reduceMotion: reduceMotion)) { isTalking.toggle() }
                    }
                    .padding(.top, Space.xl)
                    .padding(.trailing, Space.xs)
                }
            } stub: {
                Text(copy: "小林", bundle: .module)
                    .typeStyle(TypeRamp.headline)
                    .foregroundStyle(Color(role: .fgOnBrand, in: theme))
            }
            .frame(height: 300)
            GuideGroup(Text(copy: "一周海报：一天一行，角色站在角落", bundle: .module)) {
                WeekPoster(
                    title: "小林 · 10.20–10.26", heading: .week(43), layout: .card, fill: .bgBrand, ink: .fgOnBrand
                ) {
                    VStack(alignment: .leading, spacing: Space.s) {
                        Text(copy: "周一 跑步", bundle: .module)
                        Text(copy: "周二 力量", bundle: .module)
                        Text(copy: "周三 休息", bundle: .module)
                    }
                    .typeStyle(TypeRamp.action)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Space.xs)
                } character: {
                    Image(systemName: "figure.run")
                        .font(.system(size: Sizing.characterBust * 1.4))
                } strip: {
                    Text(copy: "每周训练 2/7 天", bundle: .module)
                        .typeStyle(TypeRamp.label)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.horizontal, Space.s + 2)
                }
            }
            GuideGroup(Text(copy: "点人看状态：整段显示", bundle: .module)) {
                HStack(alignment: .bottom, spacing: Space.s) {
                    SpeechBubble(
                        Text(copy: "腿还在酸，今天先躺平，明天一定练。", bundle: .module),
                        kind: .info(title: Text(copy: "小美 · 请假条", bundle: .module)), on: .page)
                    SpeechBubble(Text(copy: "可以", bundle: .module), on: .page)
                }
            }
            GuideGroup(Text(copy: "点队友：状态和拍一拍", bundle: .module)) {
                HStack(alignment: .bottom, spacing: Space.s) {
                    SpeechBubble(
                        Text(copy: "小米 · 跑步 中", bundle: .module),
                        kind: .status(
                            detail: Text(copy: "今天训练", bundle: .module),
                            button: .init(Text(copy: "拍一拍", bundle: .module), isDone: false) {}),
                        on: .page)
                    SpeechBubble(
                        Text(copy: "阿杰 · 今天还没打卡", bundle: .module),
                        kind: .status(detail: nil, button: .init(Text(copy: "拍过了", bundle: .module), isDone: true) {}),
                        on: .page)
                }
            }
            GuideGroup(Text(copy: "通知条：任何页面都会弹", bundle: .module)) {
                VStack(spacing: Space.s) {
                    NoticeBanner(Text(copy: "小米把小队搬到了跑道", bundle: .module), action: Text(copy: "去看看", bundle: .module))
                    {
                        SceneBadge(.track)
                    }
                    NoticeBanner(
                        Text(copy: "DEUCE CLUB 开门了", bundle: .module), detail: Text(copy: "网球练满 3 天", bundle: .module),
                        action: Text(copy: "去看看", bundle: .module)
                    ) { SceneBadge(.tennis) }
                    NoticeBanner(
                        Text(copy: "阿杰评论了你的动态", bundle: .module), detail: Text(copy: "这组深蹲可以啊", bundle: .module),
                        action: Text(copy: "查看", bundle: .module)
                    ) { NoticeSymbol(systemImage: "bubble.left.fill") }
                    NoticeBanner(
                        Text(copy: "商店街上新了", bundle: .module), detail: Text(copy: "快去看看吧！", bundle: .module),
                        action: Text(copy: "去商店街看看", bundle: .module)
                    ) { NoticeSymbol(systemImage: "sparkles") }
                }
            }
            GuideGroup(Text(copy: "开灯的拉绳：关着是白的，开着是暖黄", bundle: .module)) {
                HStack(alignment: .top, spacing: Space.xl) {
                    PullCord(isLit ? Text(copy: "关灯", bundle: .module) : Text(copy: "开灯", bundle: .module), isOn: isLit)
                    {
                        isLit.toggle()
                    }
                    .accessibilityIdentifier("styleguide.pullcord")
                    PullCord(Text(copy: "关灯", bundle: .module), isOn: true) {}
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}
#endif
