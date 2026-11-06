#if os(iOS)
import AvatarArt
import AvatarDomain
import AvatarUI
import CheckInUI
import Contracts
import DesignSystem
import DesignSystemUI
import ScenePickDomain
import ScenePickUI
import SquadDomain
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// 小队, the squad's page (approved canvas, 2026-10-22; its cards redone with the weekly goal,
/// 2026-11-06), opened from the home's squad card (a tab from 2026-11-02 until Tracy took the tab
/// away on 2026-11-04): 返回, the squad's name, a still row of everyone's heads (the captain's
/// tagged 队长) with the coach and 「+ 邀请」, then graphite cards: the weekly goal, the coach,
/// this week's scene, the invite code; the members, and leaving. The captain renames the
/// squad and manages members from each row's ··· menu; last week's crown winner, or the captain
/// when nobody won, picks the scene once. `close` (返回 or a swipe) goes back; the app follows
/// `model.hasLeft`. A pick ends where every pick does, on home with the squad dropping in: once
/// the reveal is over, `picked` hands the scene to the app, which takes over; while the reveal
/// plays, `revealing` is true, so the app can put away its tab bar.
public struct SquadSettingsView: View {
    @Bindable private var model: SquadSettingsModel
    private let picked: (_ scene: SceneTheme, _ coveredAt: Date) -> Void
    private let close: () -> Void
    @Binding private var revealing: Bool
    /// Opens a teammate's player card, from their row; the app pops it up over everything.
    private let openTeammate: ((MemberID) -> Void)?
    /// The coach's 战术板 line of the day, pinned on its 简历.
    private let coachNote: CoachNote?
    @State private var renaming: String?
    @State private var isLeaving = false
    @State private var reveal: Reveal?
    /// The change last asked for, so its own control shows the wait while it saves.
    @State private var working: Working?
    /// The coach's pages open over the page, the last on top.
    @State private var coachPages: [CoachRoute] = []
    @Environment(\.sceneTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        model: SquadSettingsModel, picked: @escaping (_ scene: SceneTheme, _ coveredAt: Date) -> Void,
        close: @escaping () -> Void, revealing: Binding<Bool>,
        openTeammate: ((MemberID) -> Void)? = nil, coachNote: CoachNote? = nil
    ) {
        self.coachNote = coachNote
        self.model = model
        self.picked = picked
        self.close = close
        _revealing = revealing
        self.openTeammate = openTeammate
    }

    public var body: some View {
        ZStack {
            Color(role: .bgCanvas, in: theme).ignoresSafeArea()
            Group {
                switch model.load {
                case .loading:
                    Color.clear
                case .failed:
                    VStack(alignment: .leading, spacing: 0) {
                        backButton
                            .padding(.horizontal, Space.pageMargin)
                            .padding(.top, Space.xs)
                        SquadFailed { Task { await model.reload() } }
                    }
                case .loaded(let settings):
                    page(settings)
                }
            }
            .swipesBack(isEnabled: coachPages.isEmpty && reveal == nil, perform: close)
            .loadingCover(model.load == .loading) {
                TicketSpinner(on: .light(.bgCanvas))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(role: .bgCanvas, in: theme).ignoresSafeArea())
            }
            CoachPageStack(model: model, pages: $coachPages, note: coachNote)
            if let reveal {
                UnboxRevealView(
                    reveal.unboxing, scene: reveal.scene, startedAt: reveal.startedAt,
                    onFinished: { coveredAt in
                        picked(reveal.scene, coveredAt)
                        self.reveal = nil
                        Task { await model.picked() }
                    },
                    page: { Color(role: .bgCanvas, in: theme) },
                    backdrop: { SceneBackdrop(scene: reveal.scene) })
            }
        }
        .task { await model.reload() }
        .onChange(of: reveal != nil) { _, playing in revealing = playing }
    }

    private func page(_ settings: SquadSettings) -> some View {
        ScrollView {
            sections(settings)
                .padding(.horizontal, Space.pageMargin)
                .padding(.top, Space.xs)
                .padding(.bottom, Space.xl)
        }
        .scrollIndicators(.hidden)
        .refreshable { await model.reload() }
        .disabled(model.isSaving)
        .accessibilityIdentifier("squad.page")
        .alert(Text("改队名", bundle: .module), isPresented: isRenaming) {
            renameAlert
        }
    }

    private func sections(_ settings: SquadSettings) -> some View {
        VStack(alignment: .leading, spacing: Space.l) {
            backButton
            VStack(alignment: .leading, spacing: Space.m) {
                header(settings)
                SquadHeads(
                    members: model.members, coach: model.coach, canHireCoach: model.canHireCoach,
                    squad: settings.squad, openSpots: model.openSpots, openCoach: openCoachPage)
            }
            if model.changeFailed {
                InlineFailure()
                    .accessibilityIdentifier("squad.changeFailed")
            }
            section(Text("每周目标", bundle: .module)) {
                SquadGoalCard(goal: settings.goal, canChange: model.canChangeGoal) { days in
                    Task { await model.setGoal(days) }
                }
            }
            section(Text("教练", bundle: .module)) { coachCard }
            section(Text("本周场地", bundle: .module)) { sceneCard }
            section(Text("邀请队友", bundle: .module)) { InviteCard(squad: settings.squad, openSpots: model.openSpots) }
            section(Text("队员 \(settings.squad.members.count)/\(SquadSize.memberLimit)", bundle: .module)) {
                memberRows
            }
            leaveButton(settings)
        }
    }

    @ViewBuilder private var renameAlert: some View {
        TextField(text: Binding(get: { renaming ?? "" }, set: { renaming = $0 })) {
            Text("队名", bundle: .module)
        }
        .accessibilityIdentifier("squad.rename.field")
        Button(role: .cancel) {
            renaming = nil
        } label: {
            Text("取消", bundle: .module)
        }
        Button {
            let typed = renaming ?? ""
            renaming = nil
            working = .rename
            Task { await model.rename(to: typed) }
        } label: {
            Text("保存", bundle: .module)
        }
        .accessibilityIdentifier("squad.rename.save")
    }

    private var isRenaming: Binding<Bool> {
        Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })
    }

    // MARK: 队员

    private var memberRows: some View {
        VStack(spacing: 0) {
            ForEach(Array(model.members.enumerated()), id: \.element.id) { index, member in
                MemberRow(
                    member: member, showsDivider: index > 0, isSaving: isSaving(.member(member.id)),
                    open: member.isMe ? nil : openTeammate.map { open in { open(member.id) } }
                ) { action in
                    perform(action)
                }
            }
        }
    }

    private func perform(_ action: MemberAction) {
        switch action {
        case .handCaptaincy(let member, _):
            working = .member(member)
            Task { await model.handCaptaincy(to: member) }
        case .remove(let member, _):
            working = .member(member)
            Task { await model.remove(member) }
        }
    }

    // MARK: 退出小队

    private func leaveButton(_ settings: SquadSettings) -> some View {
        Button {
            isLeaving = true
        } label: {
            Text("退出小队", bundle: .module)
                .loadingLabel(isSaving(.leave))
        }
        .buttonStyle(TextButtonStyle(.danger))
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier("squad.leave")
        .glassConfirm(
            isPresented: $isLeaving,
            GlassMenuItem(
                Text("退出小队", bundle: .module), systemImage: "rectangle.portrait.and.arrow.right", role: .destructive,
                id: "squad.leave.menu",
                confirm: .init(
                    Text("退出小队？", bundle: .module), message: leaveMessage(settings),
                    label: Text("退出小队", bundle: .module), id: "squad.leave.confirm")
            ) {
                working = .leave
                Task { await model.leave() }
            }
        )
    }

    /// What leaving does beyond the member's own seat, when it does more.
    private func leaveMessage(_ settings: SquadSettings) -> Text? {
        if settings.squad.members.count == 1 { return Text("你走了，小队就散了", bundle: .module) }
        if model.isCaptain { return Text("队长会交给最早加入的队友", bundle: .module) }
        return nil
    }
}

extension SquadSettingsView {
    private func header(_ settings: SquadSettings) -> some View {
        HStack(alignment: .top, spacing: Space.s) {
            Text(verbatim: settings.squad.name)
                .typeStyle(TypeRamp.largeTitle)
                .foregroundStyle(Color(role: .fgDefault, in: theme))
                .lineLimit(2)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("squad.name")
                .frame(maxWidth: .infinity, alignment: .leading)
            if model.isCaptain {
                LoadingSwap(isSaving(.rename)) {
                    HeaderButton(Text("改队名", bundle: .module), systemImage: "pencil") {
                        renaming = settings.squad.name
                    }
                    .accessibilityIdentifier("squad.rename")
                    .disabled(isSaving(.rename))
                }
                .foregroundStyle(Color(role: .fgDefault, in: theme))
                .frame(minWidth: Sizing.minimumTapTarget, minHeight: Sizing.minimumTapTarget)
            }
        }
    }

    private var backButton: some View {
        HeaderButton(Text("返回", bundle: .module), systemImage: "chevron.left", action: close)
            .accessibilityIdentifier("squad.back")
    }

    private func section(_ title: Text, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: Space.labelGap) {
            SectionLabel(title)
            content()
        }
    }

    // MARK: 本周场地

    /// The scene's own art as a banner over a graphite strip with its name and, for whoever may
    /// pick this week, 换场地; the tiles open under the card.
    private var sceneCard: some View {
        VStack(spacing: Space.s) {
            VStack(spacing: 0) {
                SceneBackdrop(scene: model.scene)
                    .frame(maxWidth: .infinity)
                    .frame(height: SquadSettingsMetrics.sceneBanner)
                    .clipped()
                    .accessibilityHidden(true)
                HStack(spacing: Space.s) {
                    model.scene.name
                        .typeStyle(TypeRamp.headline)
                        .foregroundStyle(Color(role: .fgOnBrand, in: theme))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("squad.scene")
                    if model.canPickScene, model.picker == nil {
                        Button {
                            withAnimation(.wildcard(Motion.change, reduceMotion: reduceMotion)) { model.openPicker() }
                        } label: {
                            Text("换场地", bundle: .module)
                        }
                        .buttonStyle(SecondaryButtonStyle(.inCard))
                        .fixedSize()
                        .accessibilityIdentifier("squad.changeScene")
                    }
                }
                .padding(.horizontal, Space.cardPadding)
                .padding(.vertical, Space.s)
                .frame(minHeight: Sizing.minimumTapTarget + Space.s * 2)
                .background(Color(role: .bgBrand, in: theme))
            }
            .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            if let picker = model.picker {
                ScenePickerGrid(
                    picker: picker,
                    onPicked: { unboxing, scene in
                        reveal = Reveal(unboxing: unboxing, scene: scene, startedAt: .now)
                    },
                    onRefused: { Task { await model.pickRefused() } })
            }
        }
    }

    // MARK: 教练

    private var coachCard: some View {
        CoachCard(hire: model.coach, week: model.coachWeek, canHire: model.canHireCoach, open: openCoachPage)
    }

    private func openCoachPage(_ route: CoachRoute) {
        withAnimation(.wildcard(Motion.change, reduceMotion: reduceMotion)) { coachPages.append(route) }
    }

    /// Whether `change` is the one saving now.
    private func isSaving(_ change: Working) -> Bool {
        model.isSaving && working == change
    }
}

/// The scene picker's reveal, once 「确认」 saved.
private struct Reveal {
    let unboxing: Unboxing
    let scene: SceneTheme
    let startedAt: Date
}

/// A change the page saves, by the control that asked for it.
enum Working: Hashable {
    case rename
    case member(MemberID)
    case leave
}
#endif
