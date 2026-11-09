#if os(iOS)
import CheckInUI
import Contracts
import DesignSystem
import DesignSystemUI
import SquadDomain
import SwiftUI

/// One of the coach's pages (教练招聘会, a 简历, 解雇), pushed on the NavigationStack over 小队.
/// `pages` are the coach's pages on the stack, this one among them: a page pushes the next by
/// adding it, and 招聘, 换教练 and 确认解雇 end by taking them all away, back on 小队, the change on
/// its 教练 card.
public struct CoachPage: View {
    @Bindable private var model: SquadSettingsModel
    private let route: CoachRoute
    @Binding private var pages: [CoachRoute]
    /// The coach's 战术板 line of the day, pinned on its own 简历.
    private let note: CoachNote?
    /// The letter the squad's coach was left when it took over (交接信), which its 简历 opens again.
    private let letter: CoachLetter?
    /// 确认换教练 landed, from the first coach to the second: the app goes back to 今天, where they
    /// change places.
    private let swapped: (Coach, Coach) -> Void
    /// This page's change didn't get through: it says so until the member moves on.
    @State private var failed = false

    public init(
        route: CoachRoute, model: SquadSettingsModel, pages: Binding<[CoachRoute]>, note: CoachNote?,
        letter: CoachLetter? = nil, swapped: @escaping (Coach, Coach) -> Void = { _, _ in }
    ) {
        self.route = route
        self.model = model
        _pages = pages
        self.note = note
        self.letter = letter
        self.swapped = swapped
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
            .task {
                // Opened straight from 今天, past 小队: who may hire comes from the squad, so read
                // it again when it never loaded.
                await model.loadMarket()
                if model.settings == nil { await model.reload() }
            }
        case .resume(let coach):
            CoachResumePage(
                coach: coach, isCurrent: model.coach?.coach.id == coach.id,
                note: model.coach?.coach.id == coach.id && note?.coach.id == coach.id ? note : nil,
                letter: model.coach?.coach.id == coach.id && letter?.recipient.id == coach.id ? letter : nil,
                canHire: model.canHireCoach,
                isSaving: model.isSaving, failed: failed,
                hire: { hire(coach) },
                change: { push(.market) }, fire: { push(.fire(coach)) })
        case .fire(let coach):
            CoachLeavingPage(
                leaving: coach, title: Text(copy: "解雇\(coach.name)", bundle: .module),
                line: Text(copy: "小队的记忆会留给下一个教练", bundle: .module),
                keep: Text(copy: "先不解雇", bundle: .module), confirm: Text(copy: "确认解雇", bundle: .module),
                identifier: "coach.fire", parting: .fired, isSaving: model.isSaving, failed: failed, back: back,
                action: { Task { finish(await model.fireCoach()) } })
        case .swap(let leaving, let coming):
            CoachLeavingPage(
                leaving: leaving, title: Text(copy: "换成\(coming.name)？", bundle: .module),
                line: Text(copy: "\(leaving.name)会离开，\(coming.name)会来", bundle: .module),
                keep: Text(copy: "先不换", bundle: .module), confirm: Text(copy: "确认换教练", bundle: .module),
                identifier: "coach.swap", parting: .swapped, isSaving: model.isSaving, failed: failed, back: back,
                action: {
                    Task {
                        let change = await model.hire(coming.id)
                        if change == .done { swapped(leaving, coming) }
                        finish(change)
                    }
                })
        }
    }

    /// 招聘 hires at once into an empty spot; with a coach in it, it asks first, since that
    /// coach leaves.
    private func hire(_ coach: Coach) {
        if let current = model.coach?.coach, current.id != coach.id {
            push(.swap(leaving: current, coming: coach))
        } else {
            Task { finish(await model.hire(coach.id)) }
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
    /// The letter it was left when it took over, on the squad's own coach's 简历.
    let letter: CoachLetter?
    let canHire: Bool
    let isSaving: Bool
    let failed: Bool
    let hire: () -> Void
    /// 教练招聘会, to hire another coach in this one's place.
    let change: () -> Void
    let fire: () -> Void
    @Environment(\.sceneTheme) private var theme
    /// The letter opened again.
    @State private var reading: CoachLetter?

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    CoachStage(
                        coach: coach.id, catchphrase: coach.catchphrase,
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
        .sheet(item: $reading) { letter in
            CoachLetterSheet(letter: letter) { reading = nil }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
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
            CoachResumeFields(coach: coach, labelIdentifier: "coach.resume.label")
            if let letter {
                ListRow(
                    Text(copy: "\(letter.from.name)的交接信", bundle: .module), systemImage: "envelope", showsDivider: false
                ) {
                    reading = letter
                }
                .accessibilityIdentifier("coach.resume.letter")
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
                    Text(copy: "今天", bundle: .module)
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

    @ViewBuilder private var action: some View {
        VStack(spacing: Space.xs) {
            if failed {
                InlineFailure()
                    .accessibilityIdentifier("coach.resume.failed")
            }
            if !canHire {
                Text(copy: "只有队长能雇教练", bundle: .module)
                    .typeStyle(TypeRamp.footnote)
                    .foregroundStyle(Color(role: .fgMuted, in: theme))
                    .frame(minHeight: Sizing.control)
                    .accessibilityIdentifier("coach.resume.captainOnly")
            } else if !isCurrent {
                Button(action: hire) {
                    Text(copy: "招聘", bundle: .module).loadingLabel(isSaving).frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle(.large))
                .accentTone(.ink)
                .disabled(isSaving)
                .accessibilityIdentifier("coach.resume.hire")
            } else {
                HStack(spacing: Space.l) {
                    Button(action: change) { Text(copy: "换教练", bundle: .module) }
                        .buttonStyle(TextButtonStyle(.muted))
                        .accessibilityIdentifier("coach.resume.change")
                    Button(action: fire) { Text(copy: "解雇", bundle: .module) }
                        .buttonStyle(TextButtonStyle(.danger))
                        .accessibilityIdentifier("coach.resume.fire")
                }
                .disabled(isSaving)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

/// A coach leaving, 解雇 or 换教练: the leaving coach on its stage, a line under it, and the
/// buttons to keep it or let it go. Fired, it cries and letting it go is the red text button
/// under 先不解雇; swapped, it is a neutral change (Tracy, 2026-11-08): the coach stands at ease
/// saying its catchphrase, and 确认换教练 is the ink button over a plain 先不换.
struct CoachLeavingPage: View {
    enum Parting { case fired, swapped }

    let leaving: Coach
    let title: Text
    let line: Text
    let keep: Text
    let confirm: Text
    let identifier: String
    let parting: Parting
    let isSaving: Bool
    let failed: Bool
    let back: () -> Void
    let action: () -> Void
    @Environment(\.sceneTheme) private var theme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.l) {
                title
                    .typeStyle(TypeRamp.largeTitle)
                    .foregroundStyle(Color(role: .fgDefault, in: theme))
                    .accessibilityAddTraits(.isHeader)
                CoachStage(
                    coach: leaving.id,
                    catchphrase: parting == .fired
                        ? String(copy: "我才刚记住大家的外号……", bundle: .module) : leaving.catchphrase,
                    figureHeight: CoachMetrics.resumeFigure, floor: CoachMetrics.fireFloor,
                    mood: parting == .fired ? .crying : .calm, surface: .page
                )
                .frame(height: CoachMetrics.fireStage)
                .clipShape(RoundedRectangle(cornerRadius: Radius.ticket, style: .continuous))
                line
                    .typeStyle(TypeRamp.footnote)
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
                switch parting {
                case .fired:
                    keepButton.buttonStyle(PrimaryButtonStyle(.large)).accentTone(.ink)
                    confirmButton.buttonStyle(TextButtonStyle(.danger))
                case .swapped:
                    confirmButton.buttonStyle(PrimaryButtonStyle(.large)).accentTone(.ink)
                    keepButton.buttonStyle(TextButtonStyle(.muted))
                }
            }
        }
        .background(Color(role: .bgCanvas, in: theme).ignoresSafeArea())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
    }

    private var keepButton: some View {
        Button(action: back) {
            keep.frame(maxWidth: parting == .fired ? .infinity : nil)
        }
        .accessibilityIdentifier("\(identifier).keep")
    }

    private var confirmButton: some View {
        Button(action: action) {
            confirm.loadingLabel(isSaving).frame(maxWidth: parting == .swapped ? .infinity : nil)
        }
        .disabled(isSaving)
        .accessibilityIdentifier("\(identifier).confirm")
    }
}

#endif
