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
/// tagged 队长) with the coach and 「+ 邀请」, then graphite cards: the weekly goal, the match time zone (比赛时区), the coach,
/// this week's scene, the invite code; the members, and leaving. The captain renames the
/// squad and manages members from each row's ··· menu; last week's crown winner, or the captain
/// when nobody won, picks the scene once. It is pushed on 今天's NavigationStack, so the system's
/// back button and swipe go back, and the coach's pages are pushed over it through `openCoach`;
/// the app follows `model.hasLeft`. A pick ends where every pick does, on home with the squad
/// dropping in: once the reveal is over, `picked` hands the scene to the app, which takes over;
/// while the reveal plays, `revealing` is true, so the app can put away its tab bar.
public struct SquadSettingsView: View {
    @Bindable private var model: SquadSettingsModel
    private let picked: (_ scene: SceneTheme, _ coveredAt: Date) -> Void
    /// Pushes one of the coach's pages (`CoachPage`) over this one.
    private let openCoach: (CoachRoute) -> Void
    @Binding private var revealing: Bool
    /// Opens a teammate's player card, from their row; the app pops it up over everything.
    private let openTeammate: ((MemberID) -> Void)?
    @State private var renaming: String?
    @State private var isLeaving = false
    @State private var reveal: Reveal?
    /// The change last asked for, so its own control shows the wait while it saves.
    @State private var working: Working?
    @Environment(\.sceneTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        model: SquadSettingsModel, picked: @escaping (_ scene: SceneTheme, _ coveredAt: Date) -> Void,
        openCoach: @escaping (CoachRoute) -> Void, revealing: Binding<Bool>,
        openTeammate: ((MemberID) -> Void)? = nil
    ) {
        self.model = model
        self.picked = picked
        self.openCoach = openCoach
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
                    SquadFailed { Task { await model.reload() } }
                case .loaded(let settings):
                    page(settings)
                }
            }
            .loadingCover(model.load == .loading) {
                TicketSpinner(on: .light(.bgCanvas))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(role: .bgCanvas, in: theme).ignoresSafeArea())
            }
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
        // While the reveal fills the screen, the bar and the way back are away.
        .pushedPage(canGoBack: reveal == nil)
        .toolbarVisibility(reveal == nil ? .automatic : .hidden, for: .navigationBar)
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
        .barTitleOnScroll(Text(verbatim: settings.squad.name))
        .refreshable { await model.reload() }
        .disabled(model.isSaving)
        .accessibilityIdentifier("squad.page")
        .alert(Text(copy: "改队名", bundle: .module), isPresented: isRenaming) {
            renameAlert
        }
    }

    private func sections(_ settings: SquadSettings) -> some View {
        VStack(alignment: .leading, spacing: Space.l) {
            VStack(alignment: .leading, spacing: Space.m) {
                header(settings)
                SquadHeads(
                    members: model.members, coach: model.coach, canHireCoach: model.canHireCoach,
                    squad: settings.squad, openSpots: model.openSpots, openCoach: openCoach)
            }
            if model.changeFailed {
                InlineFailure()
                    .accessibilityIdentifier("squad.changeFailed")
            }
            section(Text(copy: "每周目标", bundle: .module)) {
                SquadGoalCard(goal: settings.goal, canChange: model.canChangeGoal) { days in
                    Task { await model.setGoal(days) }
                }
            }
            section(Text(copy: "比赛时区", bundle: .module)) {
                SquadTimeZoneRow(zone: settings.matchTimeZone, canChange: model.canChangeTimeZone) { zone in
                    Task { await model.setTimeZone(zone) }
                }
            }
            section(Text(copy: "教练", bundle: .module)) { coachCard }
            section(Text(copy: "本周场地", bundle: .module)) { sceneCard }
            section(Text(copy: "邀请队友", bundle: .module)) {
                InviteCard(squad: settings.squad, openSpots: model.openSpots)
            }
            section(Text(copy: "队员 \(settings.squad.members.count)/\(SquadSize.memberLimit)", bundle: .module)) {
                memberRows
            }
            leaveButton(settings)
        }
    }

    @ViewBuilder private var renameAlert: some View {
        TextField(text: Binding(get: { renaming ?? "" }, set: { renaming = $0 })) {
            Text(copy: "队名", bundle: .module)
        }
        .accessibilityIdentifier("squad.rename.field")
        Button(role: .cancel) {
            renaming = nil
        } label: {
            Text(copy: "取消", bundle: .module)
        }
        Button {
            let typed = renaming ?? ""
            renaming = nil
            working = .rename
            Task { await model.rename(to: typed) }
        } label: {
            Text(copy: "保存", bundle: .module)
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
            Text(copy: "退出小队", bundle: .module)
                .loadingLabel(isSaving(.leave))
        }
        .buttonStyle(TextButtonStyle(.danger))
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier("squad.leave")
        .glassConfirm(
            isPresented: $isLeaving,
            GlassMenuItem(
                Text(copy: "退出小队", bundle: .module), systemImage: "rectangle.portrait.and.arrow.right",
                role: .destructive,
                id: "squad.leave.menu",
                confirm: .init(
                    Text(copy: "退出小队？", bundle: .module), message: leaveMessage(settings),
                    label: Text(copy: "退出小队", bundle: .module), id: "squad.leave.confirm")
            ) {
                working = .leave
                Task { await model.leave() }
            }
        )
    }

    /// What leaving does beyond the member's own seat, when it does more.
    private func leaveMessage(_ settings: SquadSettings) -> Text? {
        if settings.squad.members.count == 1 { return Text(copy: "你走了，小队就散了", bundle: .module) }
        if model.isCaptain { return Text(copy: "队长会交给最早加入的队友", bundle: .module) }
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
                    HeaderButton(Text(copy: "改队名", bundle: .module), systemImage: "pencil") {
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
                            Text(copy: "换场地", bundle: .module)
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
        CoachCard(hire: model.coach, week: model.coachWeek, canHire: model.canHireCoach, open: openCoach)
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
