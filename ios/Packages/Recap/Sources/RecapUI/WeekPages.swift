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
    /// Where the title and the count end, which the day's bubble keeps clear of.
    @State private var titleBottom = 0.0

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
                walker(beat: beat, xs: xs, row: row, width: width)
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
            .onGeometryChange(for: Double.self) {
                $0.size.height
            } action: {
                titleBottom = $0
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
    private func walker(beat: MyWeekBeats.Beat?, xs: [Double], row: Double, width: Double) -> some View {
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
                        .position(bubbleSpot(feet: CGPoint(x: across, y: y), width: width))
                }
            }
        } else {
            page.character(page.cast.viewer).standing(feetAt: CGPoint(x: xs[0], y: feet), scale: 0.56)
        }
    }
}

extension MyWeekPage {
    /// Over the character's head, or beside it where a short screen leaves no room under the
    /// count, on the side with more room.
    fileprivate func bubbleSpot(feet: CGPoint, width: Double) -> CGPoint {
        let over = CGPoint(x: feet.x, y: feet.y - Self.bubbleOverHead)
        guard over.y - Self.bubbleHalfHeight < titleBottom + Space.s else { return over }
        let side = feet.x < width / 2 ? 1.0 : -1.0
        return CGPoint(x: feet.x + side * Self.bubbleBeside, y: feet.y - Self.bubbleBesideHead)
    }

    /// The bubble's centre above the feet, over the head, and beside it.
    private static let bubbleOverHead = 196.0
    private static let bubbleBesideHead = 150.0
    /// How far beside the character the bubble's centre sits.
    private static let bubbleBeside = 76.0
    private static let bubbleHalfHeight = 20.0
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
                VStack(alignment: .leading, spacing: Space.l) {
                    PageTitle(label: Text("本周", bundle: .module), title: Text("你最火的一条", bundle: .module))
                    post(photoHeight: min(Self.photoHeight, max(Self.photoHeightMin, floor - Self.besidePhoto)))
                        .padding(.horizontal, Space.l)
                        .offset(y: 30 * (1 - page.pop(0, 0.5)))
                        .rotationEffect(.degrees(-2 * page.pop(0, 0.5)))
                        .opacity(page.ramp(0, 0.15))
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
                .frame(width: width, alignment: .leading)
                .position(x: width / 2, y: floor + Space.xl + Space.xs)
                page.character(
                    page.cast.viewer,
                    act: Act(
                        clip: .award((hottest.move ?? .cheer).solo), start: 0.6, hold: hottest.move == .pose ? 1.3 : nil
                    )
                )
                .standing(feetAt: CGPoint(x: width - 72, y: floor), scale: 0.5)
            }
        }
    }

    /// The photo at the design's 220 × 293, smaller on a short phone so the post stays above the
    /// ground: the title over it and the words under it take `besidePhoto`.
    private static let photoHeight: Double = 293
    private static let photoHeightMin: Double = 120
    private static let besidePhoto: Double = 300

    private func post(photoHeight: Double) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            photo
                .frame(width: photoHeight * 220 / 293, height: photoHeight)
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
            if let line = hottest.line {
                Text(verbatim: line)
                    .typeStyle(TypeRamp.callout)
                    .foregroundStyle(Color(role: .fgMuted, in: theme))
                    .lineLimit(2)
                    .frame(width: 220, alignment: .leading)
                    .opacity(page.ramp(1.4, 1.7))
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
        return date.formatted(style.locale(AppLanguage.current.locale))
    }
}
#endif
