#if canImport(SwiftUI)
import DesignSystem
import SwiftUI

// MARK: - 1 Color

struct ColorSection: View {
    private let neutrals: [(role: ColorRole, name: Text)] = [
        (.bgCanvas, Text(copy: "页面底", bundle: .module)),
        (.bgSubtle, Text(copy: "内块、未选中", bundle: .module)),
        (.borderDefault, Text(copy: "分隔线、未完成", bundle: .module)),
        (.fgDefault, Text(copy: "主文字", bundle: .module)),
        (.fgMuted, Text(copy: "次要文字", bundle: .module)),
        (.fgSubtle, Text(copy: "弱文字、占位", bundle: .module)),
    ]

    private let brand: [(role: ColorRole, name: Text)] = [
        (.bgBrand, Text(copy: "品牌色：主操作、选中", bundle: .module)),
        (.fgOnBrand, Text(copy: "品牌色上的字", bundle: .module)),
        (.fgOnBrandMuted, Text(copy: "品牌色上的次要字", bundle: .module)),
    ]

    private let accents: [(role: ColorRole, name: Text)] = [
        (.bgAccent, Text(copy: "主操作、选中", bundle: .module)),
        (.bgAccentSubtle, Text(copy: "强调浅底", bundle: .module)),
        (.fgOnAccent, Text(copy: "强调上的字", bundle: .module)),
        (.fgAccent, Text(copy: "强调色文字", bundle: .module)),
        (.bgScene, Text(copy: "场景底", bundle: .module)),
        (.ring, Text(copy: "状态圈", bundle: .module)),
        (.bgKind, Text(copy: "打卡四类", bundle: .module)),
        (.fgKind, Text(copy: "打卡四类图标", bundle: .module)),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            SectionTitle(number: 1, title: Text(copy: "颜色", bundle: .module))
            GuideGroup(Text(copy: "中性色", bundle: .module)) { SwatchGrid(swatches: neutrals) }
            GuideGroup(Text(copy: "品牌：开场、注册、我、发动态、请假条、动态", bundle: .module)) {
                SwatchGrid(swatches: brand)
            }
            GuideGroup(Text(copy: "强调：当前场景色，一屏只有这一种", bundle: .module)) { SwatchGrid(swatches: accents) }
        }
    }
}

private struct SwatchGrid: View {
    let swatches: [(role: ColorRole, name: Text)]

    var body: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: Space.xs), count: 2), spacing: Space.xs
        ) {
            ForEach(swatches, id: \.role) { swatch in
                RoleSwatch(role: swatch.role, name: swatch.name)
            }
        }
    }
}

private struct RoleSwatch: View {
    @Environment(\.sceneTheme) private var theme
    let role: ColorRole
    let name: Text

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.pick, style: .continuous)
        HStack(spacing: Space.s) {
            shape
                .fill(Color(role: role, in: theme))
                .overlay(shape.strokeBorder(Color(role: .borderDefault, in: theme), lineWidth: Sizing.hairline))
                .frame(width: Sizing.control, height: Sizing.control)
            VStack(alignment: .leading, spacing: 2) {
                name
                    .typeStyle(TypeRamp.footnote)
                    .foregroundStyle(Color(role: .fgDefault, in: theme))
                    .lineLimit(1)
                TokenName(text: "\(role.rawValue) \(role.color(in: theme).hex)")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - 2 Type

struct TypeSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            SectionTitle(number: 2, title: Text(copy: "字体", bundle: .module))
            GuideGroup(Text(copy: "六级中文字号，最粗 600", bundle: .module)) {
                VStack(alignment: .leading, spacing: Space.m) {
                    Sample(token: "largeTitle", style: TypeRamp.largeTitle, text: Text(verbatim: "Tracy"))
                    Sample(token: "title", style: TypeRamp.title, text: Text(copy: "本周", bundle: .module))
                    Sample(token: "headline", style: TypeRamp.headline, text: Text(copy: "周三不练腿俱乐部", bundle: .module))
                    Sample(token: "body", style: TypeRamp.body, text: Text(copy: "今天游了 2 公里，水有点凉", bundle: .module))
                    Sample(token: "footnote", style: TypeRamp.footnote, text: Text(copy: "今天 3 人训练", bundle: .module))
                    Sample(token: "label", style: TypeRamp.label, text: Text(copy: "本周小队训练", bundle: .module))
                }
            }
            GuideGroup(Text(copy: "任务页标题和控件", bundle: .module)) {
                VStack(alignment: .leading, spacing: Space.m) {
                    Sample(token: "taskTitle", style: TypeRamp.taskTitle, text: Text(copy: "平时练什么？", bundle: .module))
                    Sample(token: "action", style: TypeRamp.action, text: Text(copy: "下一步", bundle: .module))
                    Sample(token: "pick", style: TypeRamp.pick, text: Text(copy: "游泳", bundle: .module))
                    Sample(token: "callout", style: TypeRamp.callout, text: Text(copy: "全部", bundle: .module))
                    Sample(
                        token: "calloutEmphasis", style: TypeRamp.calloutEmphasis,
                        text: Text(copy: "换一组", bundle: .module))
                }
            }
            GuideGroup(Text(copy: "数字：Barlow Condensed，只给数字", bundle: .module)) {
                HStack(alignment: .lastTextBaseline, spacing: Space.l) {
                    Score(count: 14, goal: 22, size: .hero)
                    Score(count: 14, goal: 22, size: .card)
                    Score(count: 14, goal: 22, size: .inline)
                }
            }
        }
    }
}

private struct Sample: View {
    @Environment(\.sceneTheme) private var theme
    let token: String
    let style: TypeStyle
    let text: Text

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            text
                .typeStyle(style)
                .foregroundStyle(Color(role: .fgDefault, in: theme))
            TokenName(text: "\(token) · \(Int(style.size))")
        }
    }
}

// MARK: - 3 Spacing, radii, control heights

struct LayoutSection: View {
    @Environment(\.sceneTheme) private var theme

    private let steps: [(name: String, value: Double)] = [
        ("xxs", Space.xxs), ("xs", Space.xs), ("s", Space.s), ("m", Space.m), ("l", Space.l), ("xl", Space.xl),
        ("xxl", Space.xxl),
    ]
    private let radii: [(name: Text, value: Double)] = [
        (Text(copy: "缩略图", bundle: .module), Radius.thumbnail),
        (Text(copy: "选项、输入框", bundle: .module), Radius.pick),
        (Text(copy: "卡片", bundle: .module), Radius.card),
    ]
    private let heights: [(name: Text, value: Double)] = [
        (Text(copy: "主按钮，一屏一个", bundle: .module), Sizing.primaryControl),
        (Text(copy: "普通按钮、输入框、页头按钮", bundle: .module), Sizing.control),
        (Text(copy: "标签和切换", bundle: .module), Sizing.compactControl),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            SectionTitle(number: 3, title: Text(copy: "间距、圆角、控件高度", bundle: .module))
            GuideGroup(Text(copy: "间距：4 的倍数，7 档", bundle: .module)) {
                VStack(alignment: .leading, spacing: Space.xxs) {
                    ForEach(steps, id: \.name) { step in
                        HStack(spacing: Space.s) {
                            Color(role: .bgAccentSubtle, in: theme)
                                .frame(width: step.value, height: Space.s)
                            TokenName(text: "\(step.name) · \(Int(step.value))")
                        }
                    }
                }
            }
            GuideGroup(Text(copy: "圆角：只有按钮是胶囊", bundle: .module)) {
                HStack(alignment: .top, spacing: Space.s) {
                    ForEach(Array(radii.enumerated()), id: \.offset) { _, radius in
                        Labeled(name: radius.name, value: radius.value) {
                            RoundedRectangle(cornerRadius: radius.value, style: .continuous)
                                .fill(Color(role: .bgSubtle, in: theme))
                                .frame(width: 64, height: 64)
                        }
                    }
                    Labeled(name: Text(copy: "按钮", bundle: .module), value: nil) {
                        Capsule().fill(Color(role: .bgSubtle, in: theme)).frame(width: 64, height: Sizing.control)
                    }
                }
            }
            GuideGroup(Text(copy: "控件高度：只有三种", bundle: .module)) {
                VStack(alignment: .leading, spacing: Space.xs) {
                    ForEach(Array(heights.enumerated()), id: \.offset) { _, height in
                        HStack(spacing: Space.s) {
                            Capsule()
                                .fill(Color(role: .bgAccentSubtle, in: theme))
                                .frame(width: 88, height: height.value)
                                .overlay {
                                    Text(verbatim: "\(Int(height.value))")
                                        .typeStyle(TypeRamp.scoreInline)
                                        .foregroundStyle(Color(role: .fgAccent, in: theme))
                                }
                            height.name
                                .typeStyle(TypeRamp.footnote)
                                .foregroundStyle(Color(role: .fgMuted, in: theme))
                        }
                    }
                }
            }
        }
    }
}

private struct Labeled<Content: View>: View {
    @Environment(\.sceneTheme) private var theme
    let name: Text
    let value: Double?
    @ViewBuilder let shape: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xxs) {
            shape
            name
                .typeStyle(TypeRamp.footnote)
                .foregroundStyle(Color(role: .fgDefault, in: theme))
            TokenName(text: value.map { "\(Int($0))" } ?? "capsule")
        }
    }
}

// MARK: - 10 Motion

struct MotionSection: View {
    @Environment(\.sceneTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isAtEnd = false
    @State private var checkPlays = 0

    private let names: [String: Text] = [
        "press": Text(copy: "按下：所有按钮", bundle: .module),
        "change": Text(copy: "变色：选中、切换，不回弹", bundle: .module),
        "sheet": Text(copy: "半屏：展开、弹出", bundle: .module),
        "page": Text(copy: "全屏：换页", bundle: .module),
        "celebrate": Text(copy: "庆祝：只在打卡成功那一下回弹", bundle: .module),
        "notice": Text(copy: "通知条：从顶上落下", bundle: .module),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            SectionTitle(number: 10, title: Text(copy: "动效", bundle: .module))
            VStack(alignment: .leading, spacing: Space.m) {
                ForEach(Motion.all, id: \.name) { item in
                    VStack(alignment: .leading, spacing: Space.xxs) {
                        GeometryReader { proxy in
                            Capsule()
                                .fill(Color(role: .bgSubtle, in: theme))
                                .overlay(alignment: .leading) {
                                    Circle()
                                        .fill(Color(role: .bgAccent, in: theme))
                                        .frame(width: Space.l, height: Space.l)
                                        .offset(x: isAtEnd ? proxy.size.width - Space.l : 0)
                                        .animation(
                                            .wildcard(
                                                isAtEnd ? item.spring : item.spring.exit, reduceMotion: reduceMotion),
                                            value: isAtEnd)
                                }
                        }
                        .frame(height: Space.l)
                        (names[item.name] ?? Text(verbatim: item.name))
                            .typeStyle(TypeRamp.footnote)
                            .foregroundStyle(Color(role: .fgDefault, in: theme))
                        TokenName(
                            text: "\(item.name) · \(item.spring.response) · \(item.spring.dampingFraction)")
                    }
                }
            }
            Button {
                isAtEnd.toggle()
            } label: {
                isAtEnd ? Text(copy: "回到起点", bundle: .module) : Text(copy: "播放", bundle: .module)
            }
            .buttonStyle(SecondaryButtonStyle())
            .accessibilityIdentifier("styleguide.motion.play")
            GuideGroup(Text(copy: "整页加载：两张票", bundle: .module)) {
                HStack(spacing: 0) {
                    TicketSpinner(size: 64, on: .brand)
                        .frame(maxWidth: .infinity, minHeight: 120)
                        .background(Color(role: .bgBrand, in: theme))
                    TicketSpinner(size: 64, on: .page)
                        .frame(maxWidth: .infinity, minHeight: 120)
                        .background(Color(role: .bgBrandPage, in: theme))
                }
                .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            }
            GuideGroup(Text(copy: "完成：两张票打勾", bundle: .module)) {
                TicketCheck(size: 96, label: Text(copy: "完成", bundle: .module)) {
                    Text(copy: "完成", bundle: .module).typeStyle(TypeRamp.headline)
                }
                .id(checkPlays)
                .frame(maxWidth: .infinity, minHeight: 180)
                .background(Color(role: .bgCanvas, in: theme))
                .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                .onTapGesture { checkPlays += 1 }
                .accessibilityIdentifier("styleguide.ticketCheck")
            }
        }
    }
}
#endif
