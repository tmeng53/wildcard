#if os(iOS)
import AvatarUI
import Contracts
import DesignSystem
import DesignSystemUI
import OnboardingDomain
import SportsUI
import SwiftUI

/// 本周目标, step 4: this week as a poster, each day a sport picked in the step before or
/// 休息. Tap a day, then what it is under the poster, and the next day is selected; days already
/// over are blank, neither training nor 休息, since the member wasn't here yet. The character on the poster hops when a rest day becomes a training day.
struct WeekStep: View {
    let model: SignUpModel
    @Environment(\.sceneTheme) private var theme

    var body: some View {
        StepPage(step: .week, title: Text("本周目标", bundle: .module), character: nil, onBack: model.back) {
            if let week = model.week {
                VStack(alignment: .leading, spacing: Space.m) {
                    WeekPoster(model: model, week: week)
                    DayChoices(model: model, week: week)
                }
            }
        } actions: {
            FailureLine(failure: model.failure)
            StepButton(
                title: Text("上场", bundle: .module), isWorking: model.isWorking, isEnabled: model.week != nil,
                action: model.finishWeek
            )
            .accessibilityIdentifier("week.done")
            Button(action: model.skipWeek) {
                Text("跳过", bundle: .module)
            }
            .buttonStyle(TextButtonStyle())
            .accessibilityIdentifier("week.skip")
        }
    }
}

/// The week on a card in the accent tone (the brand's, in sign-up), laid out as the approved board draws it: who and which dates,
/// the week's number in italic, a row a day, the character in the corner and 每周训练 N/7 天
/// along the bottom. A picture with a fixed layout, like the 出赛表 poster.
private struct WeekPoster: View {
    let model: SignUpModel
    let week: WeekDraft
    @Environment(\.sceneTheme) private var theme
    @Environment(\.accentTone) private var tone
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Positions from the approved board, in poster points.
    /// The poster's height; its width is the page's.
    private let height: Double = 460
    /// The week's number: italic, 112 points, set tight.
    private let weekNumberStyle = TypeStyle(
        face: .scoreboard(.extraBoldItalic), size: 112, tracking: -4, anchor: .largeTitle)
    /// Puts the number's baseline where the board's 0.86 line height does.
    private let weekNumberTop: Double = 15
    /// Where the rows start, under the week's number, and how wide they run.
    private let rowsTop: Double = 138
    private let rowsWidth: Double = 196
    private let rowHeight: Double = 38
    /// The day's name in front of its sport.
    private let dayLabelWidth: Double = 32
    /// The character in the poster's corner, clear of the strip.
    private let characterSize = CGSize(width: 92, height: 120)
    private let characterInset = CGSize(width: 30, height: 56)
    /// Days that are 休息 or already over fade back, so the training days read first.
    private let restOpacity = 0.55
    /// The selected day's row: the ink over the card, faintly.
    private let selectedFill = 0.22

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color(role: tone.fill, in: theme)
            Text(verbatim: "\(model.nickname) · \(dates)")
                .typeStyle(TypeRamp.calloutEmphasis)
                .lineLimit(1)
                .padding(.leading, Space.m + 2)
                .padding(.top, Space.s + 2)
            Text(verbatim: "W\(model.weekNumber)")
                .typeStyle(weekNumberStyle)
                .fixedSize()
                .padding(.leading, Space.s + 2)
                .padding(.top, weekNumberTop)
                .allowsHitTesting(false)
                .accessibilityLabel(Text("第 \(model.weekNumber) 周", bundle: .module))
            if let player = model.myCharacter?.player {
                CharacterView(player: player)
                    .frame(width: characterSize.width, height: characterSize.height)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(.trailing, characterInset.width)
                    .padding(.bottom, characterInset.height)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            VStack(spacing: 0) {
                ForEach(week.days.indices, id: \.self) { index in
                    dayRow(index)
                }
            }
            .frame(width: rowsWidth)
            .padding(.leading, Space.xs + 2)
            .padding(.top, rowsTop)
            WeekTotal(trainingDays: week.trainingDays)
                .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .foregroundStyle(Color(role: tone.onFill, in: theme))
        .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        // A picture with a fixed layout: its type doesn't grow with Dynamic Type.
        .dynamicTypeSize(.large)
        .animation(.wildcard(Motion.change, reduceMotion: reduceMotion), value: week)
        .onChange(of: model.hops) { _, _ in model.myCharacter?.play("cheer") }
        // On the poster the character trains at the scene's sport, as on the scene.
        .task(id: theme) { model.myCharacter?.train(on: theme) }
    }

    private func dayRow(_ index: Int) -> some View {
        let day = week.days[index]
        let isSelected = index == week.selected
        return Button {
            model.selectDay(index)
        } label: {
            HStack(spacing: 0) {
                Text(model.weekDays[safe: index].map(Self.weekday) ?? "")
                    .typeStyle(TypeRamp.footnoteEmphasis)
                    .frame(width: dayLabelWidth, alignment: .leading)
                // The board sets the sport at 19 points, semibold: the action's size.
                if week.isOpen(index) {
                    DayName(day: day)
                        .typeStyle(TypeRamp.action)
                        .lineLimit(1)
                } else {
                    // A day gone before sign-up isn't a rest day, so it says nothing.
                    Text(verbatim: "–")
                        .typeStyle(TypeRamp.action)
                        .accessibilityHidden(true)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Space.xs)
            .frame(height: rowHeight)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: Radius.pick, style: .continuous)
                        .fill(Color(role: tone.onFill, in: theme).opacity(selectedFill))
                }
            }
            .opacity(day == .rest || !week.isOpen(index) ? restOpacity : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(!week.isOpen(index))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("week.day.\(index)")
    }

    /// 10.20–10.26.
    private var dates: String {
        guard let first = model.weekDays.first, let last = model.weekDays.last else { return "" }
        return "\(Self.short(first))–\(Self.short(last))"
    }

    private static func short(_ day: LocalDay) -> String {
        "\(day.month).\(day.day)"
    }

    /// 周一, Mon: the day's name at its noon on the phone's clock.
    private static func weekday(_ day: LocalDay) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let noon = calendar.date(from: DateComponents(year: day.year, month: day.month, day: day.day, hour: 12))
        return noon?.formatted(.dateTime.weekday(.abbreviated).locale(AppLanguage.current.locale)) ?? ""
    }
}

/// The strip along the poster's bottom: 每周训练, the count turning over as a day changes, and
/// 天, all set to the right as the board has them.
private struct WeekTotal: View {
    let trainingDays: Int
    @Environment(\.sceneTheme) private var theme

    /// The strip: the accent, a shade darker.
    private let height: Double = 44
    private let shade = 0.16
    private let labelOpacity = 0.85
    private let denominatorOpacity = 0.6

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.xxs + 2) {
            Spacer(minLength: 0)
            Text("每周训练", bundle: .module)
                .typeStyle(TypeRamp.label)
                .opacity(labelOpacity)
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text(verbatim: "\(trainingDays)")
                    .typeStyle(TypeRamp.scoreCard)
                    .contentTransition(.numericText(value: Double(trainingDays)))
                Text(verbatim: "/\(WeeklyPlan.dayCount)")
                    .typeStyle(TypeRamp.denominator(of: TypeRamp.scoreCard))
                    .opacity(denominatorOpacity)
            }
            Text("天", bundle: .module)
                .typeStyle(TypeRamp.footnoteEmphasis)
        }
        .padding(.horizontal, Space.s + 2)
        .frame(height: height)
        .background(Color(role: .fgDefault, in: theme).opacity(shade))
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isStaticText)
        .accessibilityLabel(Text("每周训练 \(trainingDays)/\(WeeklyPlan.dayCount) 天", bundle: .module))
        .accessibilityIdentifier("week.count")
    }
}

/// What the selected day can be: each sport picked, or 训练 when none was, then 休息 with its
/// moon. Small chips in words, the selected one outlined in the accent.
private struct DayChoices: View {
    let model: SignUpModel
    let week: WeekDraft
    @State private var isChoosing = false

    var body: some View {
        FlowRow {
            ForEach(week.choices, id: \.self) { choice in
                DayChip(day: choice, isSelected: week.days[week.selected] == choice) {
                    model.setDay(choice)
                }
                .accessibilityIdentifier("week.choice.\(Self.key(for: choice))")
            }
            // A sport that wasn't picked as 常练: the shared picker has every one.
            MoreChip { isChoosing = true }
                .accessibilityIdentifier("week.choice.more")
        }
        .sheet(isPresented: $isChoosing) {
            SportPicker(selected: selectedActivity, recent: model.sports.picked) { activity in
                isChoosing = false
                model.setDay(.train(activity))
            }
        }
    }

    private var selectedActivity: Activity {
        if case .train(let activity?) = week.days[week.selected] { activity } else { .sport("run") }
    }

    static func key(for day: PlanDay) -> String {
        switch day {
        case .train(let activity?): activity.key
        case .train(nil): "train"
        case .rest: "rest"
        }
    }
}

/// One choice under the poster, as the design draws it: 34 points tall, corners of 10, within a
/// full-height tap area.
private struct DayChip: View {
    let day: PlanDay
    let isSelected: Bool
    let action: () -> Void
    @Environment(\.sceneTheme) private var theme
    @Environment(\.accentTone) private var tone

    /// The chip's drawn height in the design.
    private let height = 34.0

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.pick, style: .continuous)
        Button(action: action) {
            HStack(spacing: Space.xxs) {
                if day == .rest {
                    Image(systemName: "moon.fill")
                        .font(.system(size: Sizing.smallIcon, weight: .medium))
                        .accessibilityHidden(true)
                }
                DayName(day: day)
                    .typeStyle(isSelected ? TypeRamp.calloutEmphasis : TypeRamp.callout)
                    .lineLimit(1)
                    .fixedSize()
            }
            .foregroundStyle(Color(role: .fgDefault, in: theme))
            .padding(.horizontal, Space.s)
            .frame(minHeight: height)
            .background(Color(role: .bgSubtle, in: theme), in: shape)
            .overlay {
                if isSelected {
                    shape.strokeBorder(Color(role: tone.fill, in: theme), lineWidth: Sizing.selectionStroke)
                }
            }
            .frame(minHeight: Sizing.minimumTapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// 更多 beside the day chips, drawn like them: it opens the shared sport picker.
private struct MoreChip: View {
    let action: () -> Void
    @Environment(\.sceneTheme) private var theme

    private let height = 34.0

    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.xxs) {
                Image(systemName: "plus")
                    .font(.system(size: Sizing.smallIcon, weight: .medium))
                    .accessibilityHidden(true)
                Text("更多", bundle: .module)
                    .typeStyle(TypeRamp.callout)
                    .lineLimit(1)
                    .fixedSize()
            }
            .foregroundStyle(Color(role: .fgDefault, in: theme))
            .padding(.horizontal, Space.s)
            .frame(minHeight: height)
            .background(
                Color(role: .bgSubtle, in: theme),
                in: RoundedRectangle(cornerRadius: Radius.pick, style: .continuous)
            )
            .frame(minHeight: Sizing.minimumTapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
    }
}

/// A planned day's name: the sport, 训练, or 休息.
private struct DayName: View {
    let day: PlanDay

    var body: some View { text }

    var text: Text {
        switch day {
        case .train(let activity?): activity.cardName
        case .train(nil): Text("训练", bundle: .module)
        case .rest: Text("休息", bundle: .module)
        }
    }
}
#endif
