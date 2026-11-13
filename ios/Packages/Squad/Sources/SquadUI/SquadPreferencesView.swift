#if os(iOS)
import Contracts
import DesignSystem
import DesignSystemUI
import SquadDomain
import SwiftUI

/// 小队设置 (Tracy, 2026-11-08: what is a setting rather than the squad's play leaves 小队), pushed
/// from the gear on 小队's header and from 我's 设置 (Tracy, 2026-11-12), which reads the squad first
/// when 小队 hasn't yet: 邀请队友 first while the squad has room, 比赛时区 as a plain row, then
/// 退出小队. The captain's zone row opens the system's zone list, the one sign-up's 建小队 shows, and
/// a change counts at once (Tracy, 2026-11-08), or from next week once this week's Sunday 8pm has
/// passed on either clock (Tracy, 2026-11-13); the row shows the pick either way. Everyone else only
/// reads it. Then 小队语言, the language the coach and 战报 are written in, with the one line that
/// says so (Tracy, 2026-11-08: without it the setting is confusing); the captain's opens the same
/// menu 我's 语言 does. No other help text.
public struct SquadPreferencesView: View {
    @Bindable var model: SquadSettingsModel
    /// The page's squad as the model has it now, so a saved change shows here at once.
    private var settings: SquadSettings? { model.settings }
    @State private var isChoosingZone = false
    @State private var isChoosingLanguage = false
    @State private var isLeaving = false
    @State private var isLeavingNow = false
    @Environment(\.sceneTheme) private var theme

    public init(model: SquadSettingsModel) {
        self.model = model
    }

    public var body: some View {
        if settings == nil, case .failed = model.load {
            // Opened from 我 before 小队 read the squad, and the read failed.
            SquadFailed { Task { await model.reload() } }
                .background(Color(role: .bgCanvas, in: theme))
                .pushedPage()
        } else {
            page
        }
    }

    private var page: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.l) {
                Text(copy: "小队设置", bundle: .module)
                    .typeStyle(TypeRamp.largeTitle)
                    .foregroundStyle(Color(role: .fgDefault, in: theme))
                    .accessibilityAddTraits(.isHeader)
                if model.changeFailed {
                    InlineFailure()
                }
                invite
                if Switchboard.shared.isOn(.freePlan, at: .now) {
                    subscription
                }
                timeZone
                language
                leaveButton
            }
            .padding(.horizontal, Space.pageMargin)
            .padding(.top, Space.xs)
            .padding(.bottom, Space.xl)
        }
        .scrollIndicators(.hidden)
        .barTitleOnScroll(Text(copy: "小队设置", bundle: .module))
        .background(Color(role: .bgCanvas, in: theme))
        .disabled(model.isSaving)
        .pushedPage()
        .task { if model.settings == nil { await model.reload() } }
        .accessibilityIdentifier("squad.preferences")
    }

    // MARK: 邀请队友

    /// The squad's invite, as 小队's 分享 shares it (Tracy, 2026-11-12: someone who just made a squad
    /// looks for it here), with how many more can join; gone once the squad is full.
    @ViewBuilder private var invite: some View {
        if let squad = settings?.squad, model.openSpots > 0 {
            InviteShareLink(squad: squad) {
                ListRow(
                    Text(copy: "邀请队友", bundle: .module),
                    value: Text(copy: "还剩 \(model.openSpots) 个名额", bundle: .module), showsDivider: false)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("squad.preferences.invite")
        }
    }

    // MARK: 订阅

    /// Nothing to open yet: the squad's plan is free while the public beta runs, and the row
    /// shows only while its switch (`BetaFeature.freePlan`) is on.
    private var subscription: some View {
        HStack(spacing: Space.s) {
            Text(copy: "订阅", bundle: .module)
                .typeStyle(TypeRamp.body)
                .foregroundStyle(Color(role: .fgDefault, in: theme))
            Spacer(minLength: 0)
            InkTag(Text(copy: "限时免费", bundle: .module))
        }
        .frame(minHeight: Sizing.pickRow)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("squad.subscription")
    }

    // MARK: 比赛时区

    private var zone: SquadTimeZone {
        settings?.matchTimeZone
            ?? SquadTimeZone(timeZone: SquadTimeZone.newYork, canChange: false)
    }

    private var timeZone: some View {
        Group {
            if model.canChangeTimeZone {
                ListRow(Text(copy: "比赛时区", bundle: .module), value: zoneValue, showsDivider: false) {
                    isChoosingZone = true
                }
            } else {
                ListRow(Text(copy: "比赛时区", bundle: .module), value: zoneValue, showsDivider: false)
            }
        }
        .accessibilityIdentifier("squad.timeZone")
        .sheet(isPresented: $isChoosingZone) {
            TimeZonePicker(selected: zone.nextTimeZone) { picked in
                isChoosingZone = false
                Task { await model.setTimeZone(picked) }
            }
        }
    }

    /// The picked zone's region (北美东部时间); the zone list shows the cities.
    private var zoneValue: Text { Text(verbatim: name(zone.nextTimeZone).region) }

    private func name(_ identifier: String) -> ZoneName {
        ZoneName(identifier, locale: AppLanguage.current.locale)
    }

    // MARK: 小队语言

    private var language: some View {
        // The note sits right under its row: the row's own padding is gap enough.
        VStack(alignment: .leading, spacing: 0) {
            Group {
                if model.canChangeLanguage {
                    ListRow(Text(copy: "小队语言", bundle: .module), value: languageValue, showsDivider: false) {
                        isChoosingLanguage = true
                    }
                } else {
                    ListRow(Text(copy: "小队语言", bundle: .module), value: languageValue, showsDivider: false)
                }
            }
            .accessibilityIdentifier("squad.language")
            Text(copy: "教练和战报用这个语言", bundle: .module)
                .typeStyle(TypeRamp.footnote)
                .foregroundStyle(Color(role: .fgMuted, in: theme))
                .accessibilityIdentifier("squad.language.use")
        }
        .glassMenu(
            isPresented: $isChoosingLanguage, title: Text(copy: "小队语言", bundle: .module),
            items: SquadLanguage.Language.allCases.map { choice in
                GlassMenuItem(
                    Text(verbatim: name(of: choice)), isSelected: choice == settings?.language.language,
                    id: "squad.language.\(choice.rawValue)"
                ) {
                    Task { await model.setLanguage(choice) }
                }
            })
    }

    /// The language by its own name (简体中文, 繁體中文, English), as 我's 语言 shows it.
    private var languageValue: Text {
        Text(verbatim: name(of: settings?.language.language ?? .simplifiedChinese))
    }

    private func name(of language: SquadLanguage.Language) -> String {
        AppLanguage(rawValue: language.rawValue)?.name ?? language.rawValue
    }

    // MARK: 退出小队

    private var leaveButton: some View {
        Button {
            isLeaving = true
        } label: {
            Text(copy: "退出小队", bundle: .module)
                .loadingLabel(isLeavingNow && model.isSaving)
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
                    Text(copy: "退出小队？", bundle: .module), message: leaveMessage,
                    label: Text(copy: "退出小队", bundle: .module), id: "squad.leave.confirm")
            ) {
                isLeavingNow = true
                Task { await model.leave() }
            }
        )
    }

    /// What leaving does beyond the member's own seat, when it does more.
    private var leaveMessage: Text? {
        if settings?.squad.members.count == 1 { return Text(copy: "小队会解散", bundle: .module) }
        if model.isCaptain { return Text(copy: "队长会交给最早加入的队友", bundle: .module) }
        return nil
    }
}
#endif
