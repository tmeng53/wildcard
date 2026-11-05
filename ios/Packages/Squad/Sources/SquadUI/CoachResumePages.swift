#if os(iOS)
import Contracts
import DesignSystem
import DesignSystemUI
import SquadDomain
import SwiftUI

/// One of the coach's pages (教练招聘会, a 简历, 解雇), pushed on the NavigationStack over 小队, or over
/// the home for the squad's coach's 简历 from a tap on the sideline. `pages` are the coach's pages
/// on the stack, this one among them: a page pushes the next by adding it, and 招聘, 换教练 and
/// 确认解雇 end by taking them all away, back on 小队 (or the home), the change on its 教练 card.
public struct CoachPage: View {
    @Bindable private var model: SquadSettingsModel
    private let route: CoachRoute
    @Binding private var pages: [CoachRoute]
    /// The coach's 战术板 line of the day, pinned on its own 简历.
    private let note: CoachNote?
    /// This page's change didn't get through: it says so until the member moves on.
    @State private var failed = false

    public init(route: CoachRoute, model: SquadSettingsModel, pages: Binding<[CoachRoute]>, note: CoachNote?) {
        self.route = route
        self.model = model
        _pages = pages
        self.note = note
    }

    public var body: some View {
        page.pushedPage()
    }

    @ViewBuilder private var page: some View {
        switch route {
        case .market:
            CoachMarketPage(
                market: model.market, current: model.coach?.coach.id,
                retry: { Task { await model.loadMarket() } },
                open: { coach in push(.resume(coach)) }
            )
            .task { await model.loadMarket() }
        case .resume(let coach):
            CoachResumePage(
                coach: coach, isCurrent: model.coach?.coach.id == coach.id,
                note: model.coach?.coach.id == coach.id && note?.coach.id == coach.id ? note : nil,
                canHire: model.canHireCoach,
                isSaving: model.isSaving, failed: failed,
                hire: { Task { finish(await model.hire(coach.id)) } },
                change: { push(.market) }, fire: { push(.fire(coach)) })
        case .fire(let coach):
            FireCoachPage(
                coach: coach, isSaving: model.isSaving, failed: failed, back: back,
                fire: { Task { finish(await model.fireCoach()) } })
        }
    }

    private func push(_ next: CoachRoute) {
        failed = false
        pages.append(next)
    }

    private func back() {
        guard !pages.isEmpty else { return }
        failed = false
        pages.removeLast()
    }

    /// A change that landed, or that the squad has moved past, ends off the coach's pages.
    private func finish(_ change: CoachChange) {
        guard change != .unavailable else {
            failed = true
            return
        }
        failed = false
        pages = []
    }
}

/// A coach's 简历: its stage, name and title, then 履历, 执教, 风格 and 期望待遇, and 招聘 for
/// the captain; on the squad's own coach, the captain's small 换教练 and 解雇 instead. The field names never wrap: each keeps one line and the column grows to the
/// longest.
struct CoachResumePage: View {
    let coach: Coach
    /// The squad has this coach now: nothing to hire.
    let isCurrent: Bool
    /// Its 战术板 line of the day, on the squad's own coach's 简历 while the day lasts.
    let note: CoachNote?
    let canHire: Bool
    let isSaving: Bool
    let failed: Bool
    let hire: () -> Void
    /// 教练招聘会, to hire another coach in this one's place.
    let change: () -> Void
    let fire: () -> Void
    @Environment(\.sceneTheme) private var theme

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    CoachStage(
                        coach: coach.id, catchphrase: coach.catchphrase, bubble: .center,
                        figureHeight: CoachMetrics.resumeFigure, floor: CoachMetrics.resumeFloor, greets: true
                    )
                    .frame(height: min(CoachMetrics.resumeStage, proxy.size.height * 0.42) + proxy.safeAreaInsets.top)
                    sheet
                        .padding(.top, -CoachMetrics.sheetOverlap)
                }
            }
            .scrollIndicators(.hidden)
            .ignoresSafeArea(edges: .top)
            .actionBar { action }
        }
        .background(Color(role: .bgCanvas, in: theme).ignoresSafeArea())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("coach.resume")
    }

    private var sheet: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
                CoachName(coach: coach, name: TypeRamp.taskTitle, title: TypeRamp.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
                StatusTag(isCurrent: isCurrent)
            }
            if let note { board(note) }
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: Space.m, verticalSpacing: 0) {
                row(Text("履历", bundle: .module)) { Text(verbatim: coach.background) }
                row(Text("执教", bundle: .module)) {
                    HStack(alignment: .firstTextBaseline, spacing: Space.xxs) {
                        Text(verbatim: "\(coach.yearsCoaching)").typeStyle(TypeRamp.scoreSmall)
                        Text("年，\(coach.experience)", bundle: .module)
                    }
                }
                row(Text("风格", bundle: .module)) { Text(verbatim: coach.style) }
                row(Text("期望待遇", bundle: .module)) { Text(verbatim: coach.pay) }
                hairline
            }
        }
        .padding(.horizontal, Space.pageMargin)
        .padding(.top, Space.m + Space.xxs)
        .padding(.bottom, Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color(role: .bgCanvas, in: theme),
            in: UnevenRoundedRectangle(
                topLeadingRadius: CoachMetrics.sheetOverlap, topTrailingRadius: CoachMetrics.sheetOverlap,
                style: .continuous))
    }

    /// 战术板: what the coach said today, pinned like 动态's (Tracy, 2026-11-04).
    private func board(_ note: CoachNote) -> some View {
        ClipboardCard {
            VStack(alignment: .leading, spacing: Space.xs) {
                HStack(spacing: Space.xxs) {
                    Text("今天", bundle: .module)
                    Text(verbatim: "·")
                    Text(note.writtenAt, format: .dateTime.hour().minute())
                }
                .typeStyle(TypeRamp.footnote)
                .foregroundStyle(Color(role: .fgMuted, in: theme))
                .lineLimit(1)
                Text(verbatim: note.text)
                    .typeStyle(TypeRamp.callout)
                    .foregroundStyle(Color(role: .fgDefault, in: theme))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Space.m)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("coach.resume.board")
    }

    private func row(_ label: Text, @ViewBuilder value: () -> some View) -> some View {
        Group {
            hairline
            GridRow {
                label
                    .typeStyle(TypeRamp.body)
                    .foregroundStyle(Color(role: .fgMuted, in: theme))
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.vertical, Space.s - 1)
                    .accessibilityIdentifier("coach.resume.label")
                value()
                    .typeStyle(TypeRamp.body)
                    .foregroundStyle(Color(role: .fgDefault, in: theme))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, Space.s - 1)
            }
        }
    }

    private var hairline: some View {
        Hairline()
            .gridCellColumns(2)
            .gridCellUnsizedAxes(.horizontal)
    }

    @ViewBuilder private var action: some View {
        VStack(spacing: Space.xs) {
            if failed {
                InlineFailure()
                    .accessibilityIdentifier("coach.resume.failed")
            }
            if !canHire {
                Text("只有队长能雇教练", bundle: .module)
                    .typeStyle(TypeRamp.footnote)
                    .foregroundStyle(Color(role: .fgMuted, in: theme))
                    .frame(minHeight: Sizing.control)
                    .accessibilityIdentifier("coach.resume.captainOnly")
            } else if !isCurrent {
                Button(action: hire) {
                    Text("招聘", bundle: .module).loadingLabel(isSaving).frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle(.large))
                .accentTone(.ink)
                .disabled(isSaving)
                .accessibilityIdentifier("coach.resume.hire")
            }
            // The squad's own coach offers nothing here for now: 换教练 and 解雇 are off the UI
            // (Tracy, 2026-11-04); `change` and `fire` stay wired for when they come back.
        }
        .frame(maxWidth: .infinity)
    }
}

/// 解雇: the coach crying on its stage, that the squad's memory stays, 先不解雇 and, in red,
/// 确认解雇.
struct FireCoachPage: View {
    let coach: Coach
    let isSaving: Bool
    let failed: Bool
    let back: () -> Void
    let fire: () -> Void
    @Environment(\.sceneTheme) private var theme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.l) {
                Text("解雇\(coach.name)", bundle: .module)
                    .typeStyle(TypeRamp.largeTitle)
                    .foregroundStyle(Color(role: .fgDefault, in: theme))
                    .accessibilityAddTraits(.isHeader)
                CoachStage(
                    coach: coach.id,
                    catchphrase: String(localized: "我才刚记住大家的外号……", bundle: .module.inAppLanguage),
                    bubble: .center, figureHeight: CoachMetrics.resumeFigure, floor: CoachMetrics.fireFloor,
                    mood: .crying, surface: .page
                )
                .frame(height: CoachMetrics.fireStage)
                .clipShape(RoundedRectangle(cornerRadius: Radius.ticket, style: .continuous))
                Text("小队的记忆会留给下一个教练", bundle: .module)
                    .typeStyle(TypeRamp.callout)
                    .foregroundStyle(Color(role: .fgMuted, in: theme))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, Space.pageMargin)
            .padding(.top, Space.xs)
            .padding(.bottom, Space.l)
        }
        .scrollIndicators(.hidden)
        .actionBar {
            VStack(spacing: Space.xs) {
                if failed {
                    InlineFailure()
                }
                Button(action: back) {
                    Text("先不解雇", bundle: .module).frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle(.large))
                .accentTone(.ink)
                .accessibilityIdentifier("coach.fire.keep")
                Button(action: fire) {
                    Text("确认解雇", bundle: .module).loadingLabel(isSaving)
                }
                .buttonStyle(TextButtonStyle(.danger))
                .disabled(isSaving)
                .accessibilityIdentifier("coach.fire.confirm")
            }
        }
        .background(Color(role: .bgCanvas, in: theme).ignoresSafeArea())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("coach.fire")
    }
}

#endif
