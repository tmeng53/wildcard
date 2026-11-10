import DesignSystem
import DesignSystemUI
import SwiftUI

/// What a build older than the lowest the catalog lets run shows, over everything (Tracy,
/// 2026-11-09): the logo, 有新版本 and one button to the App Store. It can't be closed; the next
/// catalog read with a lower minimum takes it away.
struct UpdateRequired: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: Space.m) {
            Spacer()
            Image("LaunchMark")
                .resizable()
                .scaledToFit()
                .frame(width: Self.markSize, height: Self.markSize)
                .accessibilityHidden(true)
            Text(copy: "有新版本", bundle: .main)
                .typeStyle(TypeRamp.largeTitle)
                .foregroundStyle(Color(role: .fgDefault, in: .gym))
            Text(copy: "更新后才能继续使用外卡", bundle: .main)
                .typeStyle(TypeRamp.body)
                .foregroundStyle(Color(role: .fgMuted, in: .gym))
            Spacer()
            Button {
                if let appStore = URL(string: "https://apps.apple.com/app/id6826015677") { openURL(appStore) }
            } label: {
                Text(copy: "去更新", bundle: .main).frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle(.large))
            .accentTone(.brand)
            .accessibilityIdentifier("update.open")
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, Space.l)
        .padding(.bottom, Space.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(role: .bgCanvas, in: .gym))
        .accessibilityIdentifier("update.required")
    }

    /// The logo's side, as on the design.
    private static let markSize: CGFloat = 88
}
