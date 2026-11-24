#if os(iOS)
import DesignSystem
import DesignSystemUI
import SwiftUI

/// Where 打卡 stood before it moved into the tab bar's ＋ (Tracy, 2026-11-21): for a moment after
/// my pat lands, 「你拍了拍小米」. Empty otherwise, so the scene shows. (A post going out is told
/// at the top, `OutgoingBanner`.)
struct CheckInSpot: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let model: TodayModel

    var body: some View {
        Group {
            if let told = model.pats.told {
                PatToldPill(told: told)
                    .id(told.id)
                    .transition(.blurReplace)
            }
        }
        .animation(.wildcard(Motion.sheet, reduceMotion: reduceMotion), value: model.pats.told)
    }
}

/// 「你拍了拍小米」: 打卡's capsule, with the hand that taps, saying whom my pat landed on.
private struct PatToldPill: View {
    let told: PatStage.Told

    var body: some View {
        Button {
        } label: {
            Label {
                Text(copy: "你拍了拍\(told.name)", bundle: .module)
            } icon: {
                Image(systemName: "hand.tap.fill")
            }
        }
        .buttonStyle(PrimaryButtonStyle())
        .allowsHitTesting(false)
        .accessibilityIdentifier("today.patTold")
    }
}
#endif
