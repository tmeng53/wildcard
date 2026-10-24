#if canImport(SwiftUI)
import DesignSystem
import SwiftUI

// MARK: - 4 Buttons and headers

struct ButtonSection: View {
    @Environment(\.sceneTheme) private var theme
    @State private var tab = 0

    private var tabs: [TabBarItem<Int>] {
        [
            TabBarItem(id: 0, title: Text("今天", bundle: .module), systemImage: "sun.max"),
            TabBarItem(id: 1, title: Text("动态", bundle: .module), systemImage: "bubble.left.and.bubble.right"),
            TabBarItem(id: 2, title: Text("出赛表", bundle: .module), systemImage: "calendar"),
            TabBarItem(id: 3, title: Text("我", bundle: .module), systemImage: "person.crop.circle"),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            SectionTitle(number: 4, title: Text("按钮、页头、标签栏", bundle: .module))
            GuideGroup(Text("主按钮：当前场景色", bundle: .module)) {
                VStack(spacing: Space.xs) {
                    Button {
                    } label: {
                        Text("下一步", bundle: .module).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    Button {
                    } label: {
                        Text("发布", bundle: .module).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(true)
                    // Ink, on the pages that keep out of the scene's colours (我, 设置, 注销账号).
                    Button {
                    } label: {
                        Text("下一步", bundle: .module).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .accentTone(.ink)
                    Button {
                    } label: {
                        Label {
                            Text("用 Apple 确认", bundle: .module)
                        } icon: {
                            Image(systemName: "apple.logo")
                        }
                    }
                    .buttonStyle(AppleButtonStyle(.outlined))
                }
            }
            GuideGroup(Text("次要按钮、文字按钮", bundle: .module)) {
                HStack(spacing: Space.xs) {
                    Button {
                    } label: {
                        Text("去打卡", bundle: .module)
                    }
                    .buttonStyle(PrimaryButtonStyle(.regular))
                    Button {
                    } label: {
                        Text("换一组", bundle: .module)
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    Button {
                    } label: {
                        Text("以后再选", bundle: .module)
                    }
                    .buttonStyle(TextButtonStyle())
                    Button {
                    } label: {
                        Text("删除", bundle: .module)
                    }
                    .buttonStyle(TextButtonStyle(.plain))
                    Button {
                    } label: {
                        Label {
                            Text("用 Apple 确认", bundle: .module)
                        } icon: {
                            Image(systemName: "apple.logo")
                        }
                    }
                    .buttonStyle(AppleButtonStyle())
                }
            }
            LoadingGuide()
            GuideGroup(Text("页头：44 的圆，右边最多一个", bundle: .module)) {
                VStack(alignment: .leading, spacing: Space.m) {
                    StepHeader(step: 2, of: 4) {}
                        .accessibilityIdentifier("styleguide.stepheader")
                    HStack {
                        HeaderButton(Text("关闭", bundle: .module), systemImage: "xmark") {}
                        Spacer()
                        HeaderButton(Text("设置", bundle: .module), systemImage: "gearshape") {}
                    }
                }
            }
            GuideGroup(Text("标签栏：玻璃，选中是浅灰块", bundle: .module)) {
                TabBar(tabs, selection: $tab)
                    .padding(Space.s)
                    .background(
                        Color(role: .bgScene, in: theme),
                        in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
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
        case .swim: Text("游泳", bundle: .module)
        case .run: Text("跑步", bundle: .module)
        case .lift: Text("力量", bundle: .module)
        case .tennis: Text("网球", bundle: .module)
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

    private let moreNames: [Text] = [
        Text("骑车", bundle: .module), Text("普拉提", bundle: .module), Text("羽毛球", bundle: .module),
        Text("徒步", bundle: .module), Text("篮球", bundle: .module),
    ]
    private let tiles = ["figure.wave", "figure.run", "figure.yoga", "figure.climbing"]

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            SectionTitle(number: 5, title: Text("切换和选择", bundle: .module))
            GuideGroup(Text("我在哪：墨色胶囊", bundle: .module)) {
                CategoryBar(
                    [
                        CategoryBarItem(id: GuideRange.week, title: Text("本周", bundle: .module)),
                        CategoryBarItem(id: GuideRange.all, title: Text("全部", bundle: .module)),
                    ], selection: $range)
            }
            GuideGroup(Text("我选了啥：白底细线，选中是场景色描边加勾", bundle: .module)) {
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
            GuideGroup(Text("图片选项和色块", bundle: .module)) {
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
            GuideGroup(Text("刻度尺：滑动选数字，每过一格轻震一下", bundle: .module)) {
                TickRuler(
                    value: $minutes, scale: RulerScale(range: 1...360, step: 1, midEvery: 5, labelEvery: 15),
                    label: Text("时长 · 分钟", bundle: .module), unit: Text("分钟", bundle: .module))
            }
            GuideGroup(Text("输入框", bundle: .module)) {
                InputField(
                    text: $catchphrase, label: Text("口头禅", bundle: .module), prompt: Text("冲冲冲！", bundle: .module),
                    limit: 10)
                SearchField(text: $query, prompt: Text("搜索", bundle: .module))
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
            SectionTitle(number: 6, title: Text("打卡四类：用场景浅底", bundle: .module))
            GuideGroup(Text("放在白底", bundle: .module)) {
                KindRow(onScene: false)
            }
            GuideGroup(Text("放在场景底", bundle: .module)) {
                KindRow(onScene: true)
                    .padding(Space.cardPadding)
                    .background(
                        Color(role: .bgScene, in: theme),
                        in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            }
            GuideGroup(Text("标签", bundle: .module)) {
                HStack(spacing: Space.xs) {
                    ForEach(CheckInKind.allCases, id: \.self) { kind in
                        Tag(kind.shortName, systemImage: kind.symbol)
                    }
                }
            }
            GuideGroup(Text("打卡展开", bundle: .module)) {
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

// MARK: - 7 Cards, status rings and progress

struct StatusSection: View {
    @Environment(\.sceneTheme) private var theme
    @State private var mine = RingStatus.open

    @State private var plusOnes = 0
    @State private var page = SquadCardPage.squad
    @State private var pickedDay: Int?

    private let squad: [RingStatus] = [.done, .done, .restDay, .open, .open]

    private var squadWeek: SquadWeek {
        SquadWeek(
            name: String(localized: "周三不练腿俱乐部", bundle: .module), done: mine == .done ? 15 : 14, goal: 22,
            members: members)
    }

    private var myWeek: MyWeek {
        MyWeek(
            summary: String(localized: "游泳 1 · 跑步 1", bundle: .module), done: mine == .done ? 3 : 2, planned: 5,
            days: [
                .trained(symbol: "figure.run"), .restDay, .trained(symbol: "figure.pool.swim"), .excused,
                mine == .done ? .trained(symbol: "figure.run") : .planned(symbol: "figure.run"),
                .planned(symbol: "figure.yoga"), .restDay,
            ],
            today: 4,
            details: [
                WeekDayDetail(
                    line: String(localized: "跑步 32 分钟", bundle: .module), isPlan: false,
                    meals: .init(healthy: 1, cheat: 0)),
                WeekDayDetail(
                    line: String(localized: "休息日", bundle: .module), isPlan: false, meals: .init(healthy: 2, cheat: 1)),
                WeekDayDetail(
                    line: String(localized: "游泳 45 分钟", bundle: .module), isPlan: false,
                    meals: .init(healthy: 0, cheat: 0)),
                WeekDayDetail(
                    line: String(localized: "请假了", bundle: .module), isPlan: false, meals: .init(healthy: 0, cheat: 1)),
                mine == .done
                    ? WeekDayDetail(
                        line: String(localized: "跑步", bundle: .module), isPlan: false,
                        meals: .init(healthy: 1, cheat: 0))
                    : WeekDayDetail(
                        line: String(localized: "跑步", bundle: .module), isPlan: true, meals: .init(healthy: 1, cheat: 0)
                    ),
                WeekDayDetail(line: String(localized: "瑜伽", bundle: .module), isPlan: true, meals: nil),
                WeekDayDetail(line: String(localized: "休息日", bundle: .module), isPlan: false, meals: nil),
            ])
    }

    private var members: [SquadMember] {
        [SquadMember(id: "me", status: mine, isMe: true, accessibilityIdentifier: "styleguide.ring.mine")]
            + squad.enumerated().map { SquadMember(id: "mate\($0.offset)", status: $0.element) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            SectionTitle(number: 7, title: Text("卡片、状态圈、进度", bundle: .module))
            GuideGroup(Text("场景上：实心白卡片", bundle: .module)) {
                SquadCard(squad: squadWeek, mine: myWeek, page: $page, pickedDay: $pickedDay) { member in
                    GuideFace(index: members.firstIndex(of: member) ?? 0)
                }
                .overlay(alignment: .topLeading) {
                    PlusOne(trigger: plusOnes)
                        .offset(x: Space.xl, y: -Space.xxl)
                }
                .padding(.vertical, Space.cardPadding)
                .background(
                    Color(role: .bgScene, in: theme),
                    in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            }
            Button {
                mine = mine == .done ? .open : .done
                if mine == .done { plusOnes += 1 }
            } label: {
                mine == .done ? Text("重来", bundle: .module) : Text("我打卡了", bundle: .module)
            }
            .buttonStyle(SecondaryButtonStyle())
            .accessibilityIdentifier("styleguide.ring.play")
            GuideGroup(Text("白底页上：浅灰卡片", bundle: .module)) {
                HStack(alignment: .lastTextBaseline) {
                    VStack(alignment: .leading, spacing: Space.xxs) {
                        SectionLabel(Text("本周", bundle: .module))
                        Text("周三不练腿俱乐部", bundle: .module)
                            .typeStyle(TypeRamp.headline)
                            .foregroundStyle(Color(role: .fgDefault, in: theme))
                    }
                    Spacer()
                    Score(count: 3, goal: 5, size: .card)
                }
                .card()
            }
        }
    }
}

/// A stand-in head for the ring demo; the app passes the character.
struct GuideFace: View {
    @Environment(\.sceneTheme) private var theme
    let index: Int

    var body: some View {
        Image(
            systemName: ["face.smiling", "pawprint.fill", "hare.fill", "face.smiling.inverse", "cat.fill", "dog.fill"][
                index % 6]
        )
        .font(.system(size: Sizing.characterHead * 0.55))
        .foregroundStyle(Color(role: .fgMuted, in: theme))
    }
}
#endif
