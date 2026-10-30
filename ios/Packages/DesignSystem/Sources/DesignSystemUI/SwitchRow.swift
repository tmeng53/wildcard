#if canImport(SwiftUI)
import DesignSystem
import SwiftUI

/// A 52-point row that turns a setting on or off (每日提醒): an icon, the title and a switch, in
/// the same list as `ListRow`. The whole row is the tap target. On, the switch fills with the
/// accent tone's colour; off, the hairline grey (muted ink with Increase Contrast on, so it stands
/// out on a white card); the knob is white with no shadow. VoiceOver reads it as a switch.
public struct SwitchRow: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let title: Text
    private let systemImage: String?
    @Binding private var isOn: Bool
    @State private var taps = 0
    private let showsDivider: Bool

    public init(_ title: Text, systemImage: String? = nil, isOn: Binding<Bool>, showsDivider: Bool = true) {
        self.title = title
        self.systemImage = systemImage
        _isOn = isOn
        self.showsDivider = showsDivider
    }

    public var body: some View {
        Button {
            taps += 1
            withAnimation(.wildcard(Motion.change, reduceMotion: reduceMotion)) { isOn.toggle() }
        } label: {
            RowShell(title: title, systemImage: systemImage, showsDivider: showsDivider) {
                SwitchTrack(isOn: isOn)
            }
        }
        .buttonStyle(.plain)
        // On taps only: a setting loaded or synced from elsewhere changes quietly.
        .haptic(.pick, trigger: taps)
        .accessibilityRepresentation {
            Toggle(isOn: $isOn) { title }
        }
    }
}

/// The switch itself: a 51×31 capsule and its knob.
private struct SwitchTrack: View {
    @Environment(\.sceneTheme) private var theme
    @Environment(\.accentTone) private var tone
    @Environment(\.colorSchemeContrast) private var contrast
    let isOn: Bool

    var body: some View {
        Capsule()
            .fill(Color(role: isOn ? tone.fill : offTrack, in: theme))
            .frame(width: Sizing.switchWidth, height: Sizing.switchHeight)
            .overlay(alignment: isOn ? .trailing : .leading) {
                Circle()
                    .fill(Color(role: .bgCanvas, in: theme))
                    .padding(Sizing.switchKnobInset)
                    .frame(width: Sizing.switchHeight, height: Sizing.switchHeight)
            }
    }

    private var offTrack: ColorRole { contrast == .increased ? .fgMuted : .borderDefault }
}
#endif
