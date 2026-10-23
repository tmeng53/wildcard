#if os(iOS)
import AvatarUI
import Contracts
import DesignSystem
import DesignSystemUI
import OnboardingDomain
import SportsUI
import SwiftUI

/// 一周练几天？, step 4: this week as a poster, each day a sport picked in the step before or
/// 休息. Tap a day, then what it is under the poster, and the next day is selected; days already
/// over stay 休息. The character on the poster hops when a rest day becomes a training day.
struct WeekStep: View {
    let model: SignUpModel
    @Environment(\.sceneTheme) private var theme

    var body: some View {
        StepPage(step: .week, title: Text("一周练几天？", bundle: .module), character: nil, onBack: model.back) {
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

/// The week on an accent card: who and which dates, the week's number, a row a day, the
/// character in the corner and 每周训练 N/7 天 along the bottom.
private struct WeekPoster: View {
    let model: SignUpModel
    let week: WeekDraft
    @Environment(\.sceneTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The character in the poster's corner, as in the design.
    private let characterSize = CGSize(width: 132, height: 157)
    /// Days that are 休息 fade back, so the training days read first.
    private let restOpacity = 0.55
    /// The selected day's row: white over the accent, faintly.
    private let selectedFill = 0.22
    /// The total's strip along the bottom: the accent, a shade darker.
    private let stripShade = 0.18

    var body: some View {
        let ink = Color(role: .fgOnAccent, in: theme)
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: Space.xxs) {
                Text(verbatim: "\(model.nickname) · \(dates)")
                    .typeStyle(TypeRamp.footnoteEmphasis)
                    .lineLimit(1)
                Text(verbatim: "W\(model.weekNumber)")
                    .typeStyle(TypeRamp.scoreHero)
                    .accessibilityLabel(Text("第 \(model.weekNumber) 周", bundle: .module))
            }
            .padding(.horizontal, Space.m)
            .padding(.top, Space.m)
            VStack(spacing: 0) {
                ForEach(week.days.indices, id: \.self) { index in
                    dayRow(index)
                }
            }
            .padding(.horizontal, Space.xs)
            .padding(.vertical, Space.xs)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .bottomTrailing) {
                if let player = model.myCharacter?.player {
                    CharacterView(player: player)
                        .frame(width: characterSize.width, height: characterSize.height)
                        .allowsHitTesting(false)
                }
            }
            WeekTotal(trainingDays: week.trainingDays)
                .background(Color(role: .fgDefault, in: theme).opacity(stripShade))
        }
        .foregroundStyle(ink)
        .background(
            Color(role: .bgAccent, in: theme), in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .animation(.wildcard(Motion.change, reduceMotion: reduceMotion), value: week)
        .onChange(of: model.hops) { _, _ in model.myCharacter?.play("cheer") }
    }

    private func dayRow(_ index: Int) -> some View {
        let day = week.days[index]
        let isSelected = index == week.selected
        return Button {
            model.selectDay(index)
        } label: {
            HStack(spacing: Space.s) {
                Text(model.weekDays[safe: index].map(Self.weekday) ?? "")
                    .typeStyle(TypeRamp.footnoteEmphasis)
                    .frame(minWidth: Sizing.control, alignment: .leading)
                DayName(day: day)
                    .typeStyle(TypeRamp.pick)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Space.xs)
            .frame(minHeight: Sizing.minimumTapTarget)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: Radius.pick, style: .continuous)
                        .fill(Color(role: .fgOnAccent, in: theme).opacity(selectedFill))
                }
            }
            .opacity(day == .rest ? restOpacity : 1)
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
        return noon?.formatted(.dateTime.weekday(.abbreviated)) ?? ""
    }
}

/// 每周训练 on the left, small, and the count on the right, big, turning over as a day changes.
private struct WeekTotal: View {
    let trainingDays: Int

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
            Text("每周训练", bundle: .module)
                .typeStyle(TypeRamp.label)
            Spacer(minLength: 0)
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text(verbatim: "\(trainingDays)")
                    .typeStyle(TypeRamp.scoreCard)
                    .contentTransition(.numericText(value: Double(trainingDays)))
                Text(verbatim: "/\(WeeklyPlan.dayCount)")
                    .typeStyle(TypeRamp.denominator(of: TypeRamp.scoreCard))
            }
            Text("天", bundle: .module)
                .typeStyle(TypeRamp.footnoteEmphasis)
        }
        .padding(.horizontal, Space.m)
        .padding(.vertical, Space.xs)
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

    var body: some View {
        FlowRow {
            ForEach(week.choices, id: \.self) { choice in
                DayChip(day: choice, isSelected: week.days[week.selected] == choice) {
                    model.setDay(choice)
                }
                .accessibilityIdentifier("week.choice.\(Self.key(for: choice))")
            }
        }
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
                    shape.strokeBorder(Color(role: .bgAccent, in: theme), lineWidth: Sizing.selectionStroke)
                }
            }
            .frame(minHeight: Sizing.minimumTapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// A planned day's name: the sport, 训练, or 休息.
private struct DayName: View {
    let day: PlanDay

    var body: some View { text }

    var text: Text {
        switch day {
        case .train(let activity?): activity.name
        case .train(nil): Text("训练", bundle: .module)
        case .rest: Text("休息", bundle: .module)
        }
    }
}
#endif
