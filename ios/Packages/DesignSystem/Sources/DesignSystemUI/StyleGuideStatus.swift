#if canImport(SwiftUI)
import DesignSystem
import SwiftUI

// MARK: - 7 Cards, status rings and progress

struct StatusSection: View {
    @Environment(\.sceneTheme) private var theme
    @State private var mine = RingStatus.open

    @State private var plusOnes = 0
    @State private var page = SquadCardPage.squad
    @State private var pickedDay: Int?

    private let squad: [RingStatus] = [.done, .done, .restDay, .open, .open]
    /// What each ring's badge shows once it is done: a sport, or a 请假条's note.
    private static let badges = ["figure.run", "figure.pool.swim", "doc.text.fill"]

    private var squadWeek: SquadWeek {
        SquadWeek(
            name: String(copy: "周三不练腿俱乐部", bundle: .module), done: mine == .done ? 15 : 14, goal: 22,
            members: members)
    }

    private var myWeek: MyWeek {
        MyWeek(
            done: mine == .done ? 3 : 2, planned: 5,
            days: [
                .trained(symbol: "figure.run"), .restDay, .trained(symbol: "figure.pool.swim"), .excused,
                mine == .done ? .trained(symbol: "figure.run") : .planned(symbol: "figure.run"),
                .planned(symbol: "figure.yoga"), .restDay,
            ],
            today: 4,
            details: [
                WeekDayDetail(
                    lines: [
                        String(copy: "跑步 32 分钟", bundle: .module),
                        String(copy: "力量训练 20 分钟", bundle: .module),
                    ], isPlan: false, meals: .init(healthy: 1, cheat: 0)),
                WeekDayDetail(
                    line: String(copy: "休息日", bundle: .module), isPlan: false,
                    meals: .init(healthy: 2, cheat: 1)),
                WeekDayDetail(
                    line: String(copy: "游泳 45 分钟", bundle: .module), isPlan: false,
                    meals: .init(healthy: 0, cheat: 0)),
                WeekDayDetail(
                    line: String(copy: "请假了", bundle: .module), isPlan: false,
                    meals: .init(healthy: 0, cheat: 1)),
                mine == .done
                    ? WeekDayDetail(
                        line: String(copy: "跑步", bundle: .module), isPlan: false,
                        meals: .init(healthy: 1, cheat: 0))
                    : WeekDayDetail(
                        line: String(copy: "跑步", bundle: .module), isPlan: true,
                        meals: .init(healthy: 1, cheat: 0)
                    ),
                WeekDayDetail(line: String(copy: "瑜伽", bundle: .module), isPlan: true, meals: nil),
                WeekDayDetail(line: String(copy: "休息日", bundle: .module), isPlan: false, meals: nil),
            ])
    }

    private var members: [SquadMember] {
        [
            SquadMember(
                id: "me", status: mine, isMe: true, accessibilityIdentifier: "styleguide.ring.mine",
                badge: Self.badges[0])
        ]
            + squad.enumerated().map {
                SquadMember(
                    id: "mate\($0.offset)", status: $0.element, badge: Self.badges[($0.offset + 1) % Self.badges.count])
            }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            SectionTitle(number: 7, title: Text(copy: "卡片、状态圈、进度", bundle: .module))
            GuideGroup(Text(copy: "场景上：毛玻璃卡片，可收起", bundle: .module)) {
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
                SquadCapsule(squad: squadWeek, mine: myWeek, heads: { GuideHeads() }, expand: {})
                    .padding(.vertical, Space.cardPadding)
                    .background(
                        Color(role: .bgScene, in: theme),
                        in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            }
            Button {
                mine = mine == .done ? .open : .done
                if mine == .done { plusOnes += 1 }
            } label: {
                mine == .done ? Text(copy: "重来", bundle: .module) : Text(copy: "我打卡了", bundle: .module)
            }
            .buttonStyle(SecondaryButtonStyle())
            .accessibilityIdentifier("styleguide.ring.play")
            GuideGroup(Text(copy: "白底页上：浅灰卡片", bundle: .module)) {
                HStack(alignment: .lastTextBaseline) {
                    VStack(alignment: .leading, spacing: Space.xxs) {
                        SectionLabel(Text(copy: "本周", bundle: .module))
                        Text(copy: "周三不练腿俱乐部", bundle: .module)
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
#endif
