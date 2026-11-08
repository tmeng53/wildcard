#if os(iOS)
import Contracts
import DesignSystem
import DesignSystemUI
import SwiftUI

/// 小队's 比赛时区 (approved 2026-11-07, A): a white row with the zone's region over its city.
/// The captain's opens the system's zone list, the one sign-up's 建小队 shows; a change counts
/// from next week, which a line under the row says, over the line on what the zone is for. Everyone
/// else reads the row, which says when the week settles instead of the chevron.
struct SquadTimeZoneRow: View {
    let zone: SquadTimeZone
    let canChange: Bool
    let pick: (String) -> Void
    @Environment(\.sceneTheme) private var theme
    @State private var isChoosing = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Group {
                if canChange {
                    Button {
                        isChoosing = true
                    } label: {
                        row { chevron }
                    }
                    .buttonStyle(.plain)
                } else {
                    row {
                        Text(copy: "周日 20:00 结算", bundle: .module)
                            .typeStyle(TypeRamp.footnote)
                            .foregroundStyle(Color(role: .fgMuted, in: theme))
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .accessibilityIdentifier("squad.timeZone")
            if canChange {
                if zone.nextTimeZone != zone.timeZone {
                    let next = name(zone.nextTimeZone)
                    Text(copy: "下周起改为\(next.region)（\(next.city)）", bundle: .module)
                        .typeStyle(TypeRamp.footnoteEmphasis)
                        .foregroundStyle(Color(role: .fgDefault, in: theme))
                        .accessibilityIdentifier("squad.timeZone.next")
                }
                Text(copy: "用于全队都能看到的内容，比如周日晚 8 点的战报", bundle: .module)
                    .typeStyle(TypeRamp.footnote)
                    .foregroundStyle(Color(role: .fgMuted, in: theme))
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .sheet(isPresented: $isChoosing) {
            TimeZonePicker(selected: zone.nextTimeZone) { picked in
                pick(picked)
                isChoosing = false
            }
        }
    }

    private func row(@ViewBuilder trailing: () -> some View) -> some View {
        let now = name(zone.timeZone)
        return HStack(spacing: Space.s) {
            VStack(alignment: .leading, spacing: Space.xxs / 2) {
                Text(verbatim: now.region)
                    .typeStyle(TypeRamp.body)
                    .foregroundStyle(Color(role: .fgDefault, in: theme))
                Text(verbatim: now.city)
                    .typeStyle(TypeRamp.footnote)
                    .foregroundStyle(Color(role: .fgMuted, in: theme))
            }
            Spacer(minLength: Space.xs)
            trailing()
        }
        .frame(maxWidth: .infinity, minHeight: Sizing.pickRow, alignment: .leading)
        .contentShape(Rectangle())
        .card()
    }

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: Sizing.smallIcon - 2, weight: .semibold))
            .foregroundStyle(Color(role: .fgSubtle, in: theme))
            .accessibilityHidden(true)
    }

    private func name(_ identifier: String) -> ZoneName {
        ZoneName(identifier, locale: AppLanguage.current.locale)
    }
}
#endif
