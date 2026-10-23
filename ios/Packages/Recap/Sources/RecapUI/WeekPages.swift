#if os(iOS)
import Contracts
import DesignSystem
import DesignSystemUI
import RecapDomain
import SportsUI
import SwiftUI

/// 你的一周: your character hops Monday to Sunday and does each day: that day's sport, a doze on
/// a rest day, lying flat (躺平) on a 请假条 day. The count goes up as each trained day lights.
struct MyWeekPage: View {
    let week: RecapDomain.MyWeek
    let page: PageContext
    @Environment(\.sceneTheme) private var theme

    private var beats: MyWeekBeats { MyWeekBeats(days: week.days) }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let row = proxy.size.height - StoryLayout.groundWeek
            let spacing = (width - 2 * Space.xl) / 7
            let xs = (0..<7).map { Space.xl + spacing * (Double($0) + 0.5) }
            let beat = page.moves ? beats.beat(at: page.time) : nil
            ZStack(alignment: .topLeading) {
                Ground(height: StoryLayout.groundWeek)
                ForEach(Array(week.days.enumerated()), id: \.offset) { index, day in
                    DayDot(index: index, kind: day.kind, isLit: isLit(index))
                        .scaleEffect(1 + 0.16 * bump(index))
                        .position(x: xs[min(index, 6)], y: row)
                }
                walker(beat: beat, xs: xs, row: row)
                stats
                    .padding(.horizontal, Space.l)
                    .frame(width: width, alignment: .leading)
                    .position(x: width / 2, y: row + StoryLayout.groundWeek / 2)
            }
        }
        .overlay(alignment: .top) {
            VStack(alignment: .leading, spacing: Space.l) {
                PageTitle(label: Text("本周", bundle: .module), title: Text("你的一周", bundle: .module))
                HStack(alignment: .top, spacing: Space.l) {
                    VStack(alignment: .leading, spacing: Space.xxs) {
                        Score(count: litCount, goal: week.plan, size: .story)
                        Text("训练天数", bundle: .module).typeStyle(TypeRamp.footnote)
                    }
                    if let line = week.line {
                        Text(verbatim: line)
                            .typeStyle(TypeRamp.headline)
                            .padding(.top, Space.xl)
                    }
                }
                .foregroundStyle(Color(role: .fgOnScene, in: theme))
                .padding(.horizontal, Space.l)
            }
        }
    }

    private func isLit(_ index: Int) -> Bool {
        guard page.moves else { return true }
        return beats.beats.indices.contains(index) && page.time >= beats.beats[index].land
    }

    /// The day's dot swells as the character lands on it.
    private func bump(_ index: Int) -> Double {
        guard page.moves, beats.beats.indices.contains(index) else { return 0 }
        let land = beats.beats[index].land
        return sin(page.ramp(land, land + 0.22) * .pi)
    }

    private var litCount: Int {
        week.days.indices.filter { index in
            if case .trained = week.days[index].kind { return isLit(index) }
            return false
        }.count
    }

    private var stats: some View {
        HStack(alignment: .top) {
            stat(week.healthyMeals, Text("健康餐", bundle: .module))
            stat(week.cheatMeals, Text("放纵餐", bundle: .module))
            stat(week.reactionsReceived, Text("收到的回应", bundle: .module))
        }
        .foregroundStyle(Color(role: .fgDefault, in: theme))
    }

    private func stat(_ count: Int, _ label: Text) -> some View {
        VStack(alignment: .leading, spacing: Space.xxs) {
            Score(count: count, size: .card)
            label.typeStyle(TypeRamp.footnote).foregroundStyle(Color(role: .fgMuted, in: theme))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// The reader's character: on a day while its move plays, hopping to the next one after.
    @ViewBuilder
    private func walker(beat: MyWeekBeats.Beat?, xs: [Double], row: Double) -> some View {
        let feet = row - DayDot.size / 2
        if let beat {
            let day = min(beat.day, 6)
            let hop = page.ramp(beat.end, beat.end + MyWeekBeats.hop)
            let next = min(day + 1, 6)
            let hopping = page.time >= beat.end && beat.day < week.days.count - 1
            let across = hopping ? xs[day] + (xs[next] - xs[day]) * hop : xs[day]
            let y = feet - (hopping ? 34 * sin(hop * .pi) : 0)
            let playing = page.time < beat.end
            ZStack {
                page.character(
                    page.cast.viewer, act: Act(clip: beat.clip, start: beat.land, hold: beat.end - beat.land),
                    kit: playing ? page.wardrobe.kit(for: beat.clip) : nil
                )
                .standing(feetAt: CGPoint(x: across, y: y), scale: 0.56)
                if playing, beat.clip != nil {
                    DayBubble(kind: week.days[beat.day].kind)
                        .opacity(page.ramp(beat.land, beat.land + 0.12) * (1 - page.ramp(beat.end - 0.12, beat.end)))
                        .position(x: across, y: y - 196)
                }
            }
        } else {
            page.character(page.cast.viewer).standing(feetAt: CGPoint(x: xs[0], y: feet), scale: 0.56)
        }
    }
}

/// One day of the week under the character: lit in the accent when trained or on leave, grey on
/// a rest day, an outline when nothing was checked in.
private struct DayDot: View {
    static let size: Double = 30
    let index: Int
    let kind: DayKind
    let isLit: Bool
    @Environment(\.sceneTheme) private var theme

    var body: some View {
        let filled: Bool = {
            switch kind {
            case .trained, .disclaimer: isLit
            case .rest, .none: false
            }
        }()
        Text(Self.weekday(index), bundle: .module)
            .typeStyle(TypeRamp.footnoteEmphasis)
            .foregroundStyle(Color(role: filled ? .fgOnAccent : .fgMuted, in: theme))
            .frame(width: Self.size, height: Self.size)
            .background {
                if filled {
                    Circle().fill(Color(role: .bgAccent, in: theme))
                } else if kind == .rest, isLit {
                    Circle().fill(Color(role: .bgSubtle, in: theme))
                } else {
                    Circle().strokeBorder(Color(role: .borderDefault, in: theme), lineWidth: Sizing.selectionStroke)
                }
            }
    }

    static func weekday(_ index: Int) -> LocalizedStringKey {
        ["一", "二", "三", "四", "五", "六", "日"][min(max(index, 0), 6)]
    }
}

/// What the day was, in a bubble over the character: the sport, 休息, or 请假条.
private struct DayBubble: View {
    let kind: DayKind

    var body: some View {
        SpeechBubble(text, kind: .line, on: .scene)
    }

    private var text: Text {
        switch kind {
        case .trained(let sport?): sport.name
        case .trained(nil): Text("练了", bundle: .module)
        case .rest: Text("休息", bundle: .module)
        case .disclaimer: Text("请假条", bundle: .module)
        case .none: Text(verbatim: "")
        }
    }
}

/// 你最火的一条: your check-in with the most reactions. The photo leads, the reactions pop in,
/// and you do the move the AI picked.
struct HottestPage: View {
    let hottest: Hottest
    let page: PageContext
    @Environment(\.sceneTheme) private var theme

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let floor = proxy.size.height - StoryLayout.groundLow
            ZStack(alignment: .topLeading) {
                Ground(height: StoryLayout.groundLow)
                if let line = hottest.line {
                    Text(verbatim: line)
                        .typeStyle(TypeRamp.body)
                        .foregroundStyle(Color(role: .fgOnScene, in: theme))
                        .frame(width: width * 0.58, alignment: .leading)
                        .position(x: Space.l + width * 0.29, y: floor - Space.xxl)
                        .opacity(page.ramp(1.4, 1.7))
                }
                HStack(spacing: Space.xs) {
                    ForEach(Array(hottest.reactions.enumerated()), id: \.element.emoji) { index, reaction in
                        let start = 0.7 + Double(index) * 0.15
                        ReactionChip(reaction: reaction, isFirst: index == 0)
                            .scaleEffect(page.pop(start, start + 0.3))
                            .opacity(page.ramp(start, start + 0.1))
                    }
                }
                .padding(.horizontal, Space.l)
                .position(x: width / 2, y: floor + Space.xl + Space.xs)
                .frame(width: width, alignment: .leading)
                page.character(
                    page.cast.viewer,
                    act: Act(
                        clip: .award((hottest.move ?? .cheer).solo), start: 0.6, hold: hottest.move == .pose ? 1.3 : nil
                    )
                )
                .standing(feetAt: CGPoint(x: width - 72, y: floor), scale: 0.5)
            }
        }
        .overlay(alignment: .top) {
            VStack(alignment: .leading, spacing: Space.l) {
                PageTitle(label: Text("本周", bundle: .module), title: Text("你最火的一条", bundle: .module))
                post
                    .padding(.horizontal, Space.l)
                    .offset(y: 30 * (1 - page.pop(0, 0.5)))
                    .rotationEffect(.degrees(-2 * page.pop(0, 0.5)))
                    .opacity(page.ramp(0, 0.15))
            }
        }
    }

    private var post: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            photo
                .frame(width: 220, height: 293)
                .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            HStack(spacing: Space.xs) {
                Tag(kindTag)
                Text(verbatim: hottest.day.weekdayName)
                    .typeStyle(TypeRamp.footnote)
                    .foregroundStyle(Color(role: .fgOnScene, in: theme))
            }
            if let words = hottest.words {
                Text(verbatim: words)
                    .typeStyle(TypeRamp.headline)
                    .foregroundStyle(Color(role: .fgOnScene, in: theme))
                    .lineLimit(2)
                    .frame(width: 220, alignment: .leading)
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var photo: some View {
        if let cover = hottest.photos.first {
            AsyncImage(url: cover) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Color(role: .bgCanvas, in: theme)
            }
            .accessibilityLabel(Text("打卡照片", bundle: .module))
        } else {
            ZStack {
                Color(role: .bgCanvas, in: theme)
                Image(systemName: hottest.kind.symbol)
                    .font(.system(size: Sizing.kindButton))
                    .foregroundStyle(Color(role: .fgSubtle, in: theme))
                    .accessibilityHidden(true)
            }
        }
    }

    /// 「练了 · 跑步」, or just the kind.
    private var kindTag: Text {
        let kind = hottest.kind.fullName
        guard let sport = hottest.sport else { return kind }
        return Text("\(kind) · \(sport.name)", bundle: .module)
    }
}

extension LocalDay {
    /// 「周四」: the day of the week, which is all the story needs.
    var weekdayName: String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        let date = calendar.date(from: DateComponents(year: year, month: month, day: day)) ?? .distantPast
        let style = Date.FormatStyle(timeZone: calendar.timeZone).weekday(.abbreviated)
        return date.formatted(style.locale(Locale.current))
    }
}
#endif
