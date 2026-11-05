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

/// 小队, the squad's page (approved canvas, 2026-10-22), opened from the home's squad card (a tab
/// from 2026-11-02 until Tracy took the tab away on 2026-11-04): 返回, the squad's name and
/// captain, a still row of everyone's heads with the coach and 「+ 邀请」, this week's scene and
/// who picks it, the coach, the invite code, the members, and leaving. The captain renames the
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
        .alert(Text("改队名", bundle: .module), isPresented: isRenaming) {
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
            section(Text("本周场地", bundle: .module)) { sceneCard }
            section(Text("教练", bundle: .module)) { coachCard }
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
            VStack(alignment: .leading, spacing: Space.xxs) {
                Text(verbatim: settings.squad.name)
                    .typeStyle(TypeRamp.largeTitle)
                    .foregroundStyle(Color(role: .fgDefault, in: theme))
                    .lineLimit(2)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("squad.name")
                Group {
                    if let captain = model.captainName {
                        Text("\(settings.squad.members.count) 人 · 队长 \(captain)", bundle: .module)
                    } else {
                        Text("\(settings.squad.members.count) 人", bundle: .module)
                    }
                }
                .typeStyle(TypeRamp.footnote)
                .foregroundStyle(Color(role: .fgMuted, in: theme))
                .lineLimit(1)
            }
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

    private func section(_ title: Text, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: Space.labelGap) {
            SectionLabel(title)
            content()
        }
    }

    // MARK: 本周场地

    private var sceneCard: some View {
        VStack(spacing: Space.s) {
            HStack(spacing: Space.s) {
                SceneBackdrop(scene: model.scene)
                    .frame(width: SquadSettingsMetrics.thumbnail.width, height: SquadSettingsMetrics.thumbnail.height)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.thumbnail, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Space.xxs) {
                    model.scene.name
                        .typeStyle(TypeRamp.headline)
                        .foregroundStyle(Color(role: .fgDefault, in: theme))
                        .accessibilityIdentifier("squad.scene")
                    if let line = model.sceneLine {
                        HStack(spacing: Space.xxs) {
                            Image(systemName: "crown")
                                .font(.system(size: Sizing.smallIcon - 1, weight: .semibold))
                                .accessibilityHidden(true)
                            SceneLineText(line: line)
                                .typeStyle(TypeRamp.footnote)
                                .lineLimit(2)
                                .accessibilityIdentifier("squad.sceneLine")
                        }
                        .foregroundStyle(Color(role: .fgMuted, in: theme))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if model.canPickScene, model.picker == nil {
                    Button {
                        withAnimation(.wildcard(Motion.change, reduceMotion: reduceMotion)) { model.openPicker() }
                    } label: {
                        Text("换场地", bundle: .module)
                    }
                    .buttonStyle(PrimaryButtonStyle(.regular))
                    .fixedSize()
                    .accessibilityIdentifier("squad.changeScene")
                }
            }
            if let picker = model.picker {
                ScenePickerGrid(
                    picker: picker,
                    onPicked: { unboxing, scene in
                        reveal = Reveal(unboxing: unboxing, scene: scene, startedAt: .now)
                    },
                    onRefused: { Task { await model.pickRefused() } })
            }
        }
        .card()
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
