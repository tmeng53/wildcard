#if os(iOS)
import Contracts
import DesignSystem
import DesignSystemUI
import RecapDomain
import SportsUI
import SwiftUI

/// 你的一周: the count and the AI's line, and on the ground's edge the whole week at once,
/// Monday to Sunday, each day's dot with what it was under it. Nothing staged: the page reads the
/// moment it opens. The reader's character stands over the last day of the sport they trained
/// most and does its move, in its kit; the meals and reactions sit under the week.
struct MyWeekPage: View {
    let week: RecapDomain.MyWeek
    let page: PageContext
    @Environment(\.sceneTheme) private var theme

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let row = proxy.size.height - StoryLayout.groundWeek
            let spacing = (width - 2 * Space.l) / 7
            let spots = (0..<7).map { Space.l + spacing * (Double($0) + 0.5) }
            ZStack(alignment: .topLeading) {
                Ground(height: StoryLayout.groundWeek)
                page.character(page.cast.viewer, act: Act(clip: week.topSport.weekClip, start: 0.3))
                    .standing(
                        feetAt: CGPoint(x: spots[min(week.standsOn, 6)], y: row - DayDot.size / 2 - Space.xxs),
                        scale: Self.scale)
                ForEach(Array(week.days.prefix(7).enumerated()), id: \.offset) { index, day in
                    let start = Double(index) * 0.04
                    VStack(spacing: Space.xs) {
                        DayDot(index: index, kind: day.kind)
                        DayName(kind: day.kind)
                            .typeStyle(TypeRamp.caption)
                            .foregroundStyle(Color(role: .fgMuted, in: theme))
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                    .frame(width: spacing)
                    .scaleEffect(0.9 + 0.1 * page.pop(start, start + 0.32))
                    .opacity(page.ramp(start, start + 0.12))
                    .accessibilityElement(children: .combine)
                    .position(x: spots[index], y: row + Space.xs + Space.xxs)
                }
                stats
                    .padding(.horizontal, Space.l)
                    .frame(width: width, alignment: .leading)
                    .position(x: width / 2, y: row + StoryLayout.groundWeek - Self.statsAboveBottom)
            }
        }
        .overlay(alignment: .top) {
            VStack(alignment: .leading, spacing: Space.l) {
                PageTitle(label: Text("本周", bundle: .module), title: Text("你的一周", bundle: .module))
                HStack(alignment: .top, spacing: Space.l) {
                    VStack(alignment: .leading, spacing: Space.xxs) {
                        Score(count: week.trainedDays, goal: week.plan, size: .story)
                        Text("训练天数", bundle: .module).typeStyle(TypeRamp.footnote)
                    }
                    if let line = week.line {
                        Text(verbatim: line)
                            .typeStyle(TypeRamp.headline)
                            .padding(.top, Space.xl)
                    }
                }
                .padding(.horizontal, Space.l)
            }
            .foregroundStyle(Color(role: .fgOnScene, in: theme))
        }
    }

    private static let scale = 0.5
    /// Where the meals and reactions sit: their centre this far over the bottom of the page.
    private static let statsAboveBottom = 88.0

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
}

/// One day of the week on the ground's edge: filled in the accent when trained, grey on a rest
/// day or a 请假条, an outline when nothing was checked in.
private struct DayDot: View {
    static let size: Double = 30
    let index: Int
    let kind: DayKind
    @Environment(\.sceneTheme) private var theme

    var body: some View {
        Text(Self.weekday(index), bundle: .module)
            .typeStyle(TypeRamp.footnoteEmphasis)
            .foregroundStyle(Color(role: kind.isTrained ? .fgOnAccent : .fgMuted, in: theme))
            .frame(width: Self.size, height: Self.size)
            .background {
                switch kind {
                case .trained: Circle().fill(Color(role: .bgAccent, in: theme))
                case .rest, .disclaimer: Circle().fill(Color(role: .bgSubtle, in: theme))
                case .none:
                    ZStack {
                        Circle().fill(Color(role: .bgCanvas, in: theme))
                        Circle().strokeBorder(
                            Color(role: .borderDefault, in: theme), lineWidth: Sizing.selectionStroke)
                    }
                }
            }
    }

    static func weekday(_ index: Int) -> LocalizedStringKey {
        ["一", "二", "三", "四", "五", "六", "日"][min(max(index, 0), 6)]
    }
}

/// What a day was, in a word: the sport, 休息 or 请假; blank with nothing checked in.
private struct DayName: View {
    let kind: DayKind

    var body: some View {
        switch kind {
        case .trained(let sport?): sport.cardName
        case .trained(nil): Text("训练", bundle: .module)
        case .rest: Text("休息", bundle: .module)
        case .disclaimer: Text("请假", bundle: .module)
        case .none: Text(verbatim: " ").accessibilityHidden(true)
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
                        clip: hottest.clip, start: 0.6, hold: hottest.move == .pose ? 1.3 : nil
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
            if !hottest.photos.isEmpty, let words = hottest.words {
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
            .accessibilityLabel(Text("照片", bundle: .module))
        } else {
            PostBlock(
                kind: hottest.kind, activity: hottest.sport.map(Activity.sport), words: hottest.words,
                day: hottest.day.day, layout: .card)
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
