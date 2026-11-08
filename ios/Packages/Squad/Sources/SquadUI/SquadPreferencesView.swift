#if os(iOS)
import Contracts
import DesignSystem
import DesignSystemUI
import SquadDomain
import SwiftUI

/// 小队设置 (Tracy, 2026-11-08: what is a setting rather than the squad's play leaves 小队), pushed
/// from the gear on 小队's header: 比赛时区 as a plain row, then 退出小队. The captain's row opens
/// the system's zone list, the one sign-up's 建小队 shows, and a change counts from next week, which
/// a line under the row says; everyone else only reads it.
struct SquadPreferencesView: View {
    @Bindable var model: SquadSettingsModel
    let settings: SquadSettings
    @State private var isChoosingZone = false
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

    private var zone: SquadTimeZone { settings.matchTimeZone }

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
                let next = name(zone.nextTimeZone)
                Text("下周起改为\(next.region)（\(next.city)）", bundle: .module)
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

    /// The zone's region and city, so two zones of one region (New York, Toronto) tell apart.
    private var zoneValue: Text {
        let now = name(zone.timeZone)
        return Text(verbatim: "\(now.region) · \(now.city)")
    }

    private func name(_ identifier: String) -> ZoneName {
        ZoneName(identifier, locale: AppLanguage.current.locale)
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
        if settings.squad.members.count == 1 { return Text("你走了，小队就散了", bundle: .module) }
        if model.isCaptain { return Text("队长会交给最早加入的队友", bundle: .module) }
        return nil
    }
}
#endif
