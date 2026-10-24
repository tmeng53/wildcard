#if os(iOS)
import DesignSystem
import DesignSystemUI
import SwiftUI

/// The open screen's 通过 Apple 继续, drawn by the app so it speaks the language picked in the
/// app (Apple's own button speaks the one the app started in). The app signs in with Apple
/// from it (`AppleSignIn.authorize`); the sample build goes straight on to 角色和昵称, and a debug
/// build signs a local test member in.
public struct ContinueWithApple: View {
    private let action: () -> Void

    /// `action` signs in, or not, then calls `SignUpModel.signedIn(name:)`.
    public init(action: @escaping () -> Void) {
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Label {
                Text("通过 Apple 继续", bundle: .module)
            } icon: {
                Image(systemName: "apple.logo")
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(PrimaryButtonStyle())
    }
}
#endif
