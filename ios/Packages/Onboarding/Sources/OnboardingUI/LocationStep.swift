#if os(iOS)
import DesignSystem
import DesignSystemUI
import LocationDomain
import OnboardingDomain
import SwiftUI

/// 下雨天也有安排 (Tracy, 2026-11-08), after 连上 Apple 健康: a rainy afternoon and the run planned
/// for it with what it could become, naming no coach yet, a line on what the place is for, then 允许, which shows the system's prompt for approximate location.
/// Allowed, it says 已打开 and goes on with 下一步; refused, it goes straight on; 以后再说 skips it.
struct LocationStep: View {
    let model: SignUpModel
    @Environment(\.sceneTheme) private var theme

    var body: some View {
        StepPage(
            step: .location, title: Text("下雨天也有安排", bundle: .module), character: model.myCharacter,
            onBack: model.back
        ) {
            VStack(alignment: .leading, spacing: Space.m) {
                if isAllowed {
                    allowed
                } else {
                    SampleRainyDay()
                    Text("只用到大概在哪个城市，队友看不到。", bundle: .module)
                        .typeStyle(TypeRamp.footnote)
                        .foregroundStyle(Color(role: .fgMuted, in: theme))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("location.purpose")
                }
            }
        } actions: {
            if isAllowed {
                StepButton(
                    title: Text("下一步", bundle: .module), isWorking: false, isEnabled: true,
                    action: model.finishLocation
                )
                .accessibilityIdentifier("location.done")
            } else {
                StepButton(
                    title: Text("允许", bundle: .module), isWorking: model.isAskingLocation, isEnabled: true,
                    action: model.allowLocation
                )
                .accessibilityIdentifier("location.allow")
                Button(action: model.finishLocation) {
                    Text("以后再说", bundle: .module)
                }
                .buttonStyle(TextButtonStyle())
                .accessibilityIdentifier("location.skip")
            }
        }
        .task { await model.location?.refresh() }
    }

    private var isAllowed: Bool { model.location?.access == .allowed }

    /// 已打开大概位置: a line with a check, as 已连接 Apple 健康 is.
    private var allowed: some View {
        Label {
            Text("已打开大概位置", bundle: .module)
                .typeStyle(TypeRamp.calloutEmphasis)
                .foregroundStyle(Color(role: .fgDefault, in: theme))
        } icon: {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color(role: .fgDefault, in: theme))
        }
        .accessibilityIdentifier("location.allowed")
    }
}

/// A rainy afternoon on a sample day: the weather, then the run planned and what it could become,
/// as the coach would suggest once it knows the member's weather.
private struct SampleRainyDay: View {
    @Environment(\.sceneTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(spacing: Space.s) {
                Image(systemName: "cloud.rain")
                    .typeStyle(TypeRamp.title)
                    .foregroundStyle(Color(role: .fgDefault, in: theme))
                VStack(alignment: .leading, spacing: Space.xxs / 2) {
                    Text("今天下午 小雨", bundle: .module)
                        .typeStyle(TypeRamp.calloutEmphasis)
                        .foregroundStyle(Color(role: .fgDefault, in: theme))
                    Text("8–13°C · 降水 80%", bundle: .module)
                        .typeStyle(TypeRamp.footnote)
                        .foregroundStyle(Color(role: .fgMuted, in: theme))
                }
            }
            Divider()
            row(Text("原计划", bundle: .module), Text("跑步 5 公里", bundle: .module), emphasis: false)
            row(Text("可以改成", bundle: .module), Text("早上跑，或者室内练", bundle: .module), emphasis: true)
        }
        .padding(Space.m)
        .overlay {
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(Color(role: .borderDefault, in: theme), lineWidth: Sizing.hairline)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("location.sample")
    }

    private func row(_ label: Text, _ value: Text, emphasis: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.s) {
            label
                .foregroundStyle(Color(role: .fgMuted, in: theme))
            Spacer(minLength: Space.s)
            value
                .foregroundStyle(Color(role: .fgDefault, in: theme))
                .multilineTextAlignment(.trailing)
        }
        .typeStyle(emphasis ? TypeRamp.calloutEmphasis : TypeRamp.callout)
    }
}
#endif
