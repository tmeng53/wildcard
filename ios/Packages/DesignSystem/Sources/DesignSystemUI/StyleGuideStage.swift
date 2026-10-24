#if canImport(SwiftUI)
import DesignSystem
import SwiftUI

// MARK: - 9 The character's stage

struct StageSection: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.sceneTheme) private var theme
    @State private var isTalking = true

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            SectionTitle(number: 9, title: Text("小人舞台和气泡", bundle: .module))
            CharacterStage(issued: .now) {
                VStack(spacing: Space.xxs) {
                    if isTalking {
                        SpeechBubble(Text("冲冲冲！", bundle: .module))
                            .transition(.speech(reduceMotion: reduceMotion))
                    }
                    Image(systemName: "figure.arms.open")
                        .font(.system(size: Sizing.characterBust * 1.4))
                        .foregroundStyle(Color(role: .fgOnBrand, in: theme))
                }
                .frame(maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, CharacterStage<EmptyView, EmptyView>.stubHeight)
                .overlay(alignment: .topTrailing) {
                    HeaderButton(Text("随机换一个", bundle: .module), systemImage: "dice", on: .scene) {
                        withAnimation(.wildcard(Motion.sheet, reduceMotion: reduceMotion)) { isTalking.toggle() }
                    }
                    .padding(.top, Space.xl)
                    .padding(.trailing, Space.xs)
                }
            } stub: {
                Text("小林", bundle: .module)
                    .typeStyle(TypeRamp.headline)
                    .foregroundStyle(Color(role: .fgOnBrand, in: theme))
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
            GuideGroup(Text("点队友：状态和拍一拍", bundle: .module)) {
                HStack(alignment: .bottom, spacing: Space.s) {
                    SpeechBubble(
                        Text("小米 · 跑步 中", bundle: .module),
                        kind: .status(
                            detail: Text("今天练了", bundle: .module),
                            button: .init(Text("拍一拍", bundle: .module), isDone: false) {}),
                        on: .page)
                    SpeechBubble(
                        Text("阿杰 · 今天还没打卡", bundle: .module),
                        kind: .status(detail: nil, button: .init(Text("拍过了", bundle: .module), isDone: true) {}),
                        on: .page)
                }
            }
        }
    }
}
#endif
