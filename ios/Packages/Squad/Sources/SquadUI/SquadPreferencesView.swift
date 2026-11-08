#if os(iOS)
import Contracts
import DesignSystem
import DesignSystemUI
import SquadDomain
import SwiftUI

/// 小队设置 (Tracy, 2026-11-08: what is a setting rather than the squad's play leaves 小队), pushed
/// from the gear on 小队's header: 比赛时区 as a plain row, then 退出小队. The captain's row opens
/// the system's zone list, the one sign-up's 建小队 shows, and a change counts at once (Tracy,
/// 2026-11-08); in the hours it waits for Monday on the new clock, one short line under the row says
/// so. Everyone else only reads it. Then 小队语言, the language the coach and 战报 are written in,
/// with the one line that says so (Tracy, 2026-11-08: without it the setting is confusing); the
/// captain's opens the same menu 我's 语言 does. No other help text.
struct SquadPreferencesView: View {
    @Bindable var model: SquadSettingsModel
    /// The page's squad as the model has it now, so a saved change shows here at once.
    private var settings: SquadSettings? { model.settings }
    @State private var isChoosingZone = false
    @State private var isChoosingLanguage = false
    @State private var isLeaving = false
    @State private var isLeavingNow = false
    @Environment(\.sceneTheme) private var theme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.l) {
                Text("小队设置", bundle: .module)
                    .typeStyle(TypeRamp.largeTitle)
                    .foregroundStyle(Color(role: .fgDefault, in: theme))
                    .accessibilityAddTraits(.isHeader)
                if model.changeFailed {
                    InlineFailure()
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
        .barTitleOnScroll(Text("小队设置", bundle: .module))
        .background(Color(role: .bgCanvas, in: theme))
        .disabled(model.isSaving)
        .pushedPage()
        .accessibilityIdentifier("squad.preferences")
    }

    // MARK: 比赛时区

    private var zone: SquadTimeZone {
        settings?.matchTimeZone
            ?? SquadTimeZone(timeZone: SquadTimeZone.newYork, nextTimeZone: SquadTimeZone.newYork, canChange: false)
    }

    private var timeZone: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Group {
                if model.canChangeTimeZone {
                    ListRow(Text("比赛时区", bundle: .module), value: zoneValue, showsDivider: false) {
                        isChoosingZone = true
                    }
                } else {
                    ListRow(Text("比赛时区", bundle: .module), value: zoneValue, showsDivider: false)
                }
            }
            .accessibilityIdentifier("squad.timeZone")
            if model.canChangeTimeZone, zone.nextTimeZone != zone.timeZone {
                Text("下周起：\(nextLabel)", bundle: .module)
                    .typeStyle(TypeRamp.footnote)
                    .foregroundStyle(Color(role: .fgMuted, in: theme))
                    .accessibilityIdentifier("squad.timeZone.next")
            }
        }
        .sheet(isPresented: $isChoosingZone) {
            TimeZonePicker(selected: zone.nextTimeZone) { picked in
                isChoosingZone = false
                Task { await model.setTimeZone(picked) }
            }
        }
    }

    /// The zone's region (北美东部时间); the zone list shows the cities.
    private var zoneValue: Text { Text(verbatim: name(zone.timeZone).region) }

    /// Next week's zone by its region, or by its city when the region is the same (New York to Toronto).
    private var nextLabel: String {
        let now = name(zone.timeZone)
        let next = name(zone.nextTimeZone)
        return next.region == now.region ? next.city : next.region
    }

    private func name(_ identifier: String) -> ZoneName {
        ZoneName(identifier, locale: AppLanguage.current.locale)
    }

    // MARK: 小队语言

    private var language: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Group {
                if model.canChangeLanguage {
                    ListRow(Text("小队语言", bundle: .module), value: languageValue, showsDivider: false) {
                        isChoosingLanguage = true
                    }
                } else {
                    ListRow(Text("小队语言", bundle: .module), value: languageValue, showsDivider: false)
                }
            }
            .accessibilityIdentifier("squad.language")
            Text("教练和战报用这个语言", bundle: .module)
                .typeStyle(TypeRamp.footnote)
                .foregroundStyle(Color(role: .fgMuted, in: theme))
                .accessibilityIdentifier("squad.language.use")
        }
        .glassMenu(
            isPresented: $isChoosingLanguage, title: Text("小队语言", bundle: .module),
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
            Text("退出小队", bundle: .module)
                .loadingLabel(isLeavingNow && model.isSaving)
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
                    Text("退出小队？", bundle: .module), message: leaveMessage,
                    label: Text("退出小队", bundle: .module), id: "squad.leave.confirm")
            ) {
                isLeavingNow = true
                Task { await model.leave() }
            }
        )
    }

    /// What leaving does beyond the member's own seat, when it does more.
    private var leaveMessage: Text? {
        if settings?.squad.members.count == 1 { return Text("小队会解散", bundle: .module) }
        if model.isCaptain { return Text("队长会交给最早加入的队友", bundle: .module) }
        return nil
    }
}
#endif
