#if canImport(SwiftUI)
import DesignSystem
import SwiftUI

// MARK: - 4 Buttons and headers

struct ButtonSection: View {
    @Environment(\.sceneTheme) private var theme
    @State private var tab = 0
    /// Room for the tab bar's sample: the bar over a strip of scene.
    private static let tabsHeight: Double = 140

    private var tabs: [TabBarItem<Int>] {
        [
            TabBarItem(id: 0, title: Text(copy: "今天", bundle: .module), systemImage: "person.3"),
            TabBarItem(id: 1, title: Text(copy: "动态", bundle: .module), systemImage: "square.stack"),
            TabBarItem(id: 2, title: Text(copy: "出赛表", bundle: .module), systemImage: "calendar"),
            TabBarItem(id: 3, title: Text(copy: "我", bundle: .module), systemImage: "person.crop.circle"),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            SectionTitle(number: 4, title: Text(copy: "按钮、页头、标签栏", bundle: .module))
            GuideGroup(Text(copy: "主按钮：当前场景色", bundle: .module)) {
                VStack(spacing: Space.xs) {
                    Button {
                    } label: {
                        Text(copy: "下一步", bundle: .module).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    Button {
                    } label: {
                        Text(copy: "发布", bundle: .module).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(true)
                    // Ink, on the pages that keep out of the scene's colours (我, 设置, 注销账号).
                    Button {
                    } label: {
                        Text(copy: "下一步", bundle: .module).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .accentTone(.ink)
                    Button {
                    } label: {
                        Label {
                            Text(copy: "用 Apple 确认", bundle: .module)
                        } icon: {
                            Image(systemName: "apple.logo")
                        }
                    }
                    .buttonStyle(AppleButtonStyle(.outlined))
                }
            }
            GuideGroup(Text(copy: "次要按钮、文字按钮", bundle: .module)) {
                HStack(spacing: Space.xs) {
                    Button {
                    } label: {
                        Text(copy: "去打卡", bundle: .module)
                    }
                    .buttonStyle(PrimaryButtonStyle(.regular))
                    Button {
                    } label: {
                        Text(copy: "换一组", bundle: .module)
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    Button {
                    } label: {
                        Text(copy: "以后再选", bundle: .module)
                    }
                    .buttonStyle(TextButtonStyle())
                    Button {
                    } label: {
                        Text(copy: "删除", bundle: .module)
                    }
                    .buttonStyle(TextButtonStyle(.plain))
                    Button {
                    } label: {
                        Label {
                            Text(copy: "用 Apple 确认", bundle: .module)
                        } icon: {
                            Image(systemName: "apple.logo")
                        }
                    }
                    .buttonStyle(AppleButtonStyle())
                }
            }
            FloatingGuide()
            StateGuide()
            LoadingGuide()
            GuideGroup(Text(copy: "页头：44 的圆，右边最多一个", bundle: .module)) {
                VStack(alignment: .leading, spacing: Space.m) {
                    StepHeader(step: 2, of: 4) {}
                        .accessibilityIdentifier("styleguide.stepheader")
                    HStack {
                        HeaderButton(Text(copy: "关闭", bundle: .module), systemImage: "xmark") {}
                        Spacer()
                        HeaderButton(Text(copy: "设置", bundle: .module), systemImage: "gearshape") {}
                    }
                    HStack {
                        Spacer()
                        HeaderButton(Text(copy: "关闭", bundle: .module), systemImage: "xmark", on: .ink) {}
                    }
                    .padding(Space.s)
                    .background(
                        Color(role: .bgInk, in: theme),
                        in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                }
            }
            GuideGroup(Text(copy: "标签栏：系统的液态玻璃，选中是墨色", bundle: .module)) {
                AppTabs(tabs, selection: $tab) { _ in
                    Color(role: .bgScene, in: theme)
                }
                .frame(height: Self.tabsHeight)
                .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            }
        }
    }
}

// MARK: - 5 Switches and picks

private enum Sport: String, CaseIterable, Identifiable {
    case swim, run, lift, tennis

    var id: String { rawValue }

    var name: Text {
        switch self {
        case .swim: Text(copy: "游泳", bundle: .module)
        case .run: Text(copy: "跑步", bundle: .module)
        case .lift: Text(copy: "力量", bundle: .module)
        case .tennis: Text(copy: "网球", bundle: .module)
        }
    }

    var symbol: String {
        switch self {
        case .swim: "figure.pool.swim"
        case .run: "figure.run"
        case .lift: "dumbbell"
        case .tennis: "tennisball"
        }
    }
}

private enum GuideRange: Hashable {
    case week, all
}

struct PickSection: View {
    @Environment(\.sceneTheme) private var theme
    @State private var range = GuideRange.week
    @State private var sports: Set<Sport> = [.swim, .lift]
    @State private var more: Set<Int> = [1]
    @State private var tile = 0
    @State private var swatch = 2
    @State private var catchphrase = ""
    @State private var query = ""
    @State private var minutes = 45

    private let moreNames: [Text] = (["骑车", "普拉提", "羽毛球", "徒步", "篮球"] as [CopyLine]).map {
        Text(copy: $0, bundle: .module)
    }
    private let tiles = ["figure.wave", "figure.run", "figure.yoga", "figure.climbing"]

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            SectionTitle(number: 5, title: Text(copy: "切换和选择", bundle: .module))
            GuideGroup(Text(copy: "我在哪：墨色胶囊", bundle: .module)) {
                CategoryBar(
                    [
                        CategoryBarItem(id: GuideRange.week, title: Text(copy: "本周", bundle: .module)),
                        CategoryBarItem(id: GuideRange.all, title: Text(copy: "全部", bundle: .module)),
                    ], selection: $range)
            }
            GuideGroup(Text(copy: "我选了啥：白底细线，选中是场景色描边加勾", bundle: .module)) {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: Space.xs), count: 2), spacing: Space.xs
                ) {
                    ForEach(Sport.allCases) { sport in
                        PickRow(sport.name, systemImage: sport.symbol, isSelected: sports.contains(sport)) {
                            if sports.contains(sport) { sports.remove(sport) } else { sports.insert(sport) }
                        }
                        .accessibilityIdentifier("styleguide.pick.\(sport.rawValue)")
                    }
                }
                FlowRow {
                    ForEach(Array(moreNames.enumerated()), id: \.offset) { index, name in
                        PickPill(name, isSelected: more.contains(index)) {
                            if more.contains(index) { more.remove(index) } else { more.insert(index) }
                        }
                    }
                }
            }
            GuideGroup(Text(copy: "图片选项和色块", bundle: .module)) {
                HStack(spacing: Space.xs) {
                    ForEach(Array(tiles.enumerated()), id: \.offset) { index, symbol in
                        PickTile(Text(verbatim: symbol), isSelected: tile == index) {
                            tile = index
                        } picture: {
                            Image(systemName: symbol)
                                .font(.system(size: 28))
                                .foregroundStyle(Color(role: .fgDefault, in: theme))
                        }
                    }
                }
                HStack(spacing: Space.xxs) {
                    ForEach(Array(Self.clothes.enumerated()), id: \.offset) { index, color in
                        Swatch(Color(color), label: Text(verbatim: color.hex), isSelected: swatch == index) {
                            swatch = index
                        }
                    }
                }
            }
            GuideGroup(Text(copy: "刻度尺：滑动选数字，每过一格轻震一下", bundle: .module)) {
                TickRuler(
                    value: $minutes, scale: RulerScale(range: 1...360, step: 1, midEvery: 5, labelEvery: 15),
                    label: Text(copy: "时长 · 分钟", bundle: .module), unit: Text(copy: "分钟", bundle: .module))
            }
            GuideGroup(Text(copy: "输入框", bundle: .module)) {
                InputField(
                    text: $catchphrase, label: Text(copy: "口头禅", bundle: .module),
                    prompt: Text(copy: "冲冲冲！", bundle: .module),
                    limit: 10)
                SearchField(text: $query, prompt: Text(copy: "搜索", bundle: .module))
            }
            GuideGroup(Text(copy: "入场券：写字的卡，撕线上写，下面放照片", bundle: .module)) {
                TicketCard {
                    Text(copy: "昨天练腿，今天下楼都难", bundle: .module)
                        .typeStyle(TypeRamp.field)
                        .foregroundStyle(Color(role: .fgDefault, in: theme))
                } stub: {
                    TicketStamp().frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        }
    }

    /// Outfit colors, so the swatches show the character's palette.
    private static let clothes = [
        Palette.white, Palette.ink, Palette.cobalt, Palette.mint, Palette.honey, Palette.lavender,
    ]
}

// MARK: - 6 Check-in kinds

struct KindSection: View {
    @Environment(\.sceneTheme) private var theme
    @State private var isOpen = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            SectionTitle(number: 6, title: Text(copy: "打卡四类：用场景浅底", bundle: .module))
            GuideGroup(Text(copy: "放在白底", bundle: .module)) {
                KindRow(onScene: false)
            }
            GuideGroup(Text(copy: "放在场景底", bundle: .module)) {
                KindRow(onScene: true)
                    .padding(Space.cardPadding)
                    .background(
                        Color(role: .bgScene, in: theme),
                        in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            }
            GuideGroup(Text(copy: "标签", bundle: .module)) {
                HStack(spacing: Space.xs) {
                    ForEach(CheckInKind.allCases, id: \.self) { kind in
                        Tag(kind.shortName, systemImage: kind.symbol)
                    }
                }
            }
            GuideGroup(Text(copy: "打卡展开", bundle: .module)) {
                CheckInBurst(isOpen: $isOpen, unavailable: [.disclaimer], identifierPrefix: "styleguide") { _ in }
                    .frame(maxWidth: .infinity)
                    .padding(.top, BurstLayout.radius + Sizing.control)
            }
        }
    }
}

private struct KindRow: View {
    let onScene: Bool

    var body: some View {
        HStack(alignment: .top, spacing: Space.s) {
            ForEach(CheckInKind.allCases, id: \.self) { kind in
                KindButton(kind, onScene: onScene) {}
            }
            Spacer(minLength: 0)
        }
    }
}
#endif
