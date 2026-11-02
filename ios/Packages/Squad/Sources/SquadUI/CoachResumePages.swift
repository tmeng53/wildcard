#if os(iOS)
import Contracts
import DesignSystem
import DesignSystemUI
import SquadDomain
import SwiftUI

/// The coach's pages over 小队设置, the last on top, each swiping back to the one under it.
/// 招聘, 换教练 and 确认解雇 all end back on 小队设置, the change on its 教练 card.
struct CoachPageStack: View {
    @Bindable var model: SquadSettingsModel
    @Binding var pages: [CoachRoute]
    /// The page whose change didn't get through, which says so until the member moves on.
    @State private var failed: CoachRoute?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ForEach(Array(pages.enumerated()), id: \.offset) { index, route in
            page(route)
                .swipesBack(isEnabled: index == pages.count - 1, perform: back)
                .transition(.move(edge: .trailing))
                .zIndex(Double(index + 1))
        }
    }

    @ViewBuilder private func page(_ route: CoachRoute) -> some View {
        switch route {
        case .market:
            CoachMarketPage(
                market: model.market, current: model.coach?.coach.id, back: back,
                retry: { Task { await model.loadMarket() } },
                open: { coach in
                    withAnimation(.wildcard(Motion.change, reduceMotion: reduceMotion)) {
                        failed = nil
                        pages.append(.resume(coach))
                    }
                }
            )
            .task { await model.loadMarket() }
        case .resume(let coach):
            CoachResumePage(
                coach: coach, isCurrent: model.coach?.coach.id == coach.id, canHire: model.canHireCoach,
                isSaving: model.isSaving, failed: failed == route, back: back,
                hire: { Task { finish(route, await model.hire(coach.id)) } })
        case .fire(let coach):
            FireCoachPage(
                coach: coach, isSaving: model.isSaving, failed: failed == route, back: back,
                fire: { Task { finish(route, await model.fireCoach()) } })
        }
    }

    private func back() {
        guard !pages.isEmpty else { return }
        failed = nil
        withAnimation(.wildcard(Motion.change, reduceMotion: reduceMotion)) { _ = pages.removeLast() }
    }

    /// A change that landed, or that the squad has moved past, ends on 小队设置.
    private func finish(_ route: CoachRoute, _ change: CoachChange) {
        guard change != .unavailable else {
            failed = route
            return
        }
        failed = nil
        withAnimation(.wildcard(Motion.change, reduceMotion: reduceMotion)) { pages = [] }
    }
}

/// A coach's 简历: its stage, name and title, then 履历, 执教, 风格 and 期望待遇, and 招聘 for
/// the captain. The field names never wrap: each keeps one line and the column grows to the
/// longest.
struct CoachResumePage: View {
    let coach: Coach
    /// The squad has this coach now: nothing to hire.
    let isCurrent: Bool
    let canHire: Bool
    let isSaving: Bool
    let failed: Bool
    let back: () -> Void
    let hire: () -> Void
    @Environment(\.sceneTheme) private var theme

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    CoachStage(
                        catchphrase: coach.catchphrase, bubble: .center, figureWidth: CoachMetrics.resumeFigure,
                        floor: CoachMetrics.resumeFloor
                    )
                    .frame(height: min(CoachMetrics.resumeStage, proxy.size.height * 0.42) + proxy.safeAreaInsets.top)
                    sheet
                        .padding(.top, -CoachMetrics.sheetOverlap)
                }
            }
            .scrollIndicators(.hidden)
            .ignoresSafeArea(edges: .top)
            .overlay(alignment: .topLeading) {
                HeaderButton(Text("返回", bundle: .module), systemImage: "chevron.left", on: .scene, action: back)
                    .padding(.leading, Space.pageMargin)
                    .padding(.top, Space.xs)
                    .accessibilityIdentifier("coach.resume.back")
            }
            .safeAreaInset(edge: .bottom) { action }
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
        Rectangle()
            .fill(Color(role: .borderDefault, in: theme))
            .frame(height: Sizing.hairline)
            .gridCellColumns(2)
            .gridCellUnsizedAxes(.horizontal)
    }

    @ViewBuilder private var action: some View {
        VStack(spacing: Space.xs) {
            if failed {
                Text("网络开小差了，没存上", bundle: .module)
                    .typeStyle(TypeRamp.footnote)
                    .foregroundStyle(Color(role: .fgMuted, in: theme))
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
        }
        .padding(.horizontal, Space.pageMargin)
        .padding(.top, Space.xs)
        .padding(.bottom, Space.xs)
        .frame(maxWidth: .infinity)
        .background(Color(role: .bgCanvas, in: theme).ignoresSafeArea(edges: .bottom))
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
                HeaderButton(Text("返回", bundle: .module), systemImage: "chevron.left", action: back)
                    .accessibilityIdentifier("coach.fire.back")
                Text("解雇\(coach.name)", bundle: .module)
                    .typeStyle(TypeRamp.largeTitle)
                    .foregroundStyle(Color(role: .fgDefault, in: theme))
                    .accessibilityAddTraits(.isHeader)
                CoachStage(
                    catchphrase: String(localized: "我才刚记住大家的外号……", bundle: .module.inAppLanguage),
                    bubble: .center, figureWidth: CoachMetrics.resumeFigure, floor: CoachMetrics.fireFloor,
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
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: Space.xs) {
                if failed {
                    Text("网络开小差了，没存上", bundle: .module)
                        .typeStyle(TypeRamp.footnote)
                        .foregroundStyle(Color(role: .fgMuted, in: theme))
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
            .padding(.horizontal, Space.pageMargin)
            .padding(.top, Space.xs)
            .background(Color(role: .bgCanvas, in: theme).ignoresSafeArea(edges: .bottom))
        }
        .background(Color(role: .bgCanvas, in: theme).ignoresSafeArea())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("coach.fire")
    }
}

#endif
