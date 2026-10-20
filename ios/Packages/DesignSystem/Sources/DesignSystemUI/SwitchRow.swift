#if canImport(SwiftUI)
import DesignSystem
import SwiftUI

/// A 52-point row that turns a setting on or off (每日提醒): an icon, the title and a switch, in
/// the same list as `ListRow`. The whole row is the tap target. On, the switch fills with the
/// scene's accent; off, the hairline grey; the knob is white with no shadow. VoiceOver reads it
/// as a switch.
public struct SwitchRow: View {
    @Environment(\.sceneTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let title: Text
    private let systemImage: String?
    @Binding private var isOn: Bool
    private let showsDivider: Bool

    public init(_ title: Text, systemImage: String? = nil, isOn: Binding<Bool>, showsDivider: Bool = true) {
        self.title = title
        self.systemImage = systemImage
        _isOn = isOn
        self.showsDivider = showsDivider
    }

    public var body: some View {
        Button {
            withAnimation(.wildcard(Motion.sheet, reduceMotion: reduceMotion)) { isOn.toggle() }
        } label: {
            HStack(spacing: Space.s) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: Sizing.smallIcon + 2))
                        .frame(width: Sizing.icon)
                        .foregroundStyle(Color(role: .fgDefault, in: theme))
                        .accessibilityHidden(true)
                }
                title
                    .typeStyle(TypeRamp.body)
                    .foregroundStyle(Color(role: .fgDefault, in: theme))
                    .frame(maxWidth: .infinity, alignment: .leading)
                SwitchTrack(isOn: isOn)
            }
            .frame(minHeight: Sizing.pickRow)
            .overlay(alignment: .bottom) {
                if showsDivider {
                    Rectangle()
                        .fill(Color(role: .borderDefault, in: theme))
                        .frame(height: Sizing.hairline)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .haptic(.pick, trigger: isOn)
        .accessibilityRepresentation {
            Toggle(isOn: $isOn) { title }
        }
    }
}

/// The switch itself: a 51×31 capsule and its knob.
private struct SwitchTrack: View {
    @Environment(\.sceneTheme) private var theme
    let isOn: Bool

    var body: some View {
        Capsule()
            .fill(Color(role: isOn ? .bgAccent : .borderDefault, in: theme))
            .frame(width: Sizing.switchWidth, height: Sizing.switchHeight)
            .overlay(alignment: isOn ? .trailing : .leading) {
                Circle()
                    .fill(Color(role: .bgCanvas, in: theme))
                    .padding(Sizing.switchKnobInset)
                    .frame(width: Sizing.switchHeight, height: Sizing.switchHeight)
            }
    }
}
#endif
