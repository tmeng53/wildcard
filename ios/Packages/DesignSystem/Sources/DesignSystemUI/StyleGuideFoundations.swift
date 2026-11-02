#if canImport(SwiftUI)
import DesignSystem
import SwiftUI

// MARK: - 1 Color

struct ColorSection: View {
    private let neutrals: [(role: ColorRole, name: Text)] = [
        (.bgCanvas, Text("页面底", bundle: .module)),
        (.bgSubtle, Text("内块、未选中", bundle: .module)),
        (.borderDefault, Text("分隔线、未完成", bundle: .module)),
        (.fgDefault, Text("主文字", bundle: .module)),
        (.fgMuted, Text("次要文字", bundle: .module)),
        (.fgSubtle, Text("弱文字、占位", bundle: .module)),
    ]

    private let brand: [(role: ColorRole, name: Text)] = [
        (.bgBrand, Text("品牌色：主操作、选中", bundle: .module)),
        (.fgOnBrand, Text("品牌色上的字", bundle: .module)),
    ]

    private let accents: [(role: ColorRole, name: Text)] = [
        (.bgAccent, Text("主操作、选中", bundle: .module)),
        (.bgAccentSubtle, Text("强调浅底", bundle: .module)),
        (.fgOnAccent, Text("强调上的字", bundle: .module)),
        (.fgAccent, Text("强调色文字", bundle: .module)),
        (.bgScene, Text("场景底", bundle: .module)),
        (.ring, Text("状态圈", bundle: .module)),
        (.bgKind, Text("打卡四类", bundle: .module)),
        (.fgKind, Text("打卡四类图标", bundle: .module)),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            SectionTitle(number: 1, title: Text("颜色", bundle: .module))
            GuideGroup(Text("中性色", bundle: .module)) { SwatchGrid(swatches: neutrals) }
            GuideGroup(Text("品牌：开场、注册、我、发动态、请假条、动态", bundle: .module)) {
                SwatchGrid(swatches: brand)
            }
            GuideGroup(Text("强调：当前场景色，一屏只有这一种", bundle: .module)) { SwatchGrid(swatches: accents) }
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
            SectionTitle(number: 2, title: Text("字体", bundle: .module))
            GuideGroup(Text("六级中文字号，最粗 600", bundle: .module)) {
                VStack(alignment: .leading, spacing: Space.m) {
                    Sample(token: "largeTitle", style: TypeRamp.largeTitle, text: Text(verbatim: "Tracy"))
                    Sample(token: "title", style: TypeRamp.title, text: Text("本周", bundle: .module))
                    Sample(token: "headline", style: TypeRamp.headline, text: Text("周三不练腿俱乐部", bundle: .module))
                    Sample(token: "body", style: TypeRamp.body, text: Text("今天游了 2 公里，水有点凉", bundle: .module))
                    Sample(token: "footnote", style: TypeRamp.footnote, text: Text("今天 3 人练了", bundle: .module))
                    Sample(token: "label", style: TypeRamp.label, text: Text("本周小队训练", bundle: .module))
                }
            }
            GuideGroup(Text("任务页标题和控件", bundle: .module)) {
                VStack(alignment: .leading, spacing: Space.m) {
                    Sample(token: "taskTitle", style: TypeRamp.taskTitle, text: Text("平时练什么？", bundle: .module))
                    Sample(token: "action", style: TypeRamp.action, text: Text("下一步", bundle: .module))
                    Sample(token: "pick", style: TypeRamp.pick, text: Text("游泳", bundle: .module))
                    Sample(token: "callout", style: TypeRamp.callout, text: Text("全部", bundle: .module))
                    Sample(
                        token: "calloutEmphasis", style: TypeRamp.calloutEmphasis, text: Text("换一组", bundle: .module))
                }
            }
            GuideGroup(Text("数字：Barlow Condensed，只给数字", bundle: .module)) {
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
        (Text("缩略图", bundle: .module), Radius.thumbnail),
        (Text("选项、输入框", bundle: .module), Radius.pick),
        (Text("卡片", bundle: .module), Radius.card),
    ]
    private let heights: [(name: Text, value: Double)] = [
        (Text("主按钮，一屏一个", bundle: .module), Sizing.primaryControl),
        (Text("普通按钮、输入框、页头按钮", bundle: .module), Sizing.control),
        (Text("标签和切换", bundle: .module), Sizing.compactControl),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            SectionTitle(number: 3, title: Text("间距、圆角、控件高度", bundle: .module))
            GuideGroup(Text("间距：4 的倍数，7 档", bundle: .module)) {
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
            GuideGroup(Text("圆角：只有按钮是胶囊", bundle: .module)) {
                HStack(alignment: .top, spacing: Space.s) {
                    ForEach(Array(radii.enumerated()), id: \.offset) { _, radius in
                        Labeled(name: radius.name, value: radius.value) {
                            RoundedRectangle(cornerRadius: radius.value, style: .continuous)
                                .fill(Color(role: .bgSubtle, in: theme))
                                .frame(width: 64, height: 64)
                        }
                    }
                    Labeled(name: Text("按钮", bundle: .module), value: nil) {
                        Capsule().fill(Color(role: .bgSubtle, in: theme)).frame(width: 64, height: Sizing.control)
                    }
                }
            }
            GuideGroup(Text("控件高度：只有三种", bundle: .module)) {
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

    private let names: [String: Text] = [
        "press": Text("按下：所有按钮", bundle: .module),
        "change": Text("变色：选中、切换，不回弹", bundle: .module),
        "sheet": Text("半屏：展开、弹出", bundle: .module),
        "page": Text("全屏：换页", bundle: .module),
        "celebrate": Text("庆祝：只在打卡成功那一下回弹", bundle: .module),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            SectionTitle(number: 10, title: Text("动效", bundle: .module))
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
                isAtEnd ? Text("回到起点", bundle: .module) : Text("播放", bundle: .module)
            }
            .buttonStyle(SecondaryButtonStyle())
            .accessibilityIdentifier("styleguide.motion.play")
            GuideGroup(Text("整页加载：两张票", bundle: .module)) {
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
        }
    }
}
#endif
