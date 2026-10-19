#if canImport(SwiftUI)
import DesignSystem
import SwiftUI

/// The scene's floor: a quiet wash with faint signature lane lines, so the 打卡 button is the
/// only strong color. Blurred lightly while a check-in is open. A stand-in until the scene art
/// lands.
public struct SceneFloor: View {
    @Environment(\.sceneTheme) private var theme
    private let isBlurred: Bool

    public init(isBlurred: Bool = false) {
        self.isBlurred = isBlurred
    }

    public var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                Color(role: .signatureWash, in: theme)
                Rectangle()
                    .fill(Color(role: .signature, in: theme).opacity(0.35))
                    .frame(height: Space.xxs)
                ForEach(1..<4, id: \.self) { lane in
                    Rectangle()
                        .fill(Color(role: .signature, in: theme).opacity(0.22))
                        .frame(width: 2)
                        .offset(x: proxy.size.width * Double(lane) / 4 - 1)
                }
            }
            .blur(radius: isBlurred ? Scrim.blurRadius : 0)
            .overlay(Color(Scrim.tint).opacity(isBlurred ? Scrim.tintOpacity : 0))
            .animation(.easeOut(duration: isBlurred ? Scrim.fadeIn : Scrim.fadeOut), value: isBlurred)
        }
        .accessibilityHidden(true)
    }
}
#endif
