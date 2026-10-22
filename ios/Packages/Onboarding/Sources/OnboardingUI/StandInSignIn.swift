#if os(iOS)
import DesignSystem
import DesignSystemUI
import SwiftUI

/// 通过 Apple 继续 for builds that can't use Sign in with Apple: the sample build goes straight on
/// to 角色和昵称, a debug build signs a local test member in first.
public struct StandInSignIn: View {
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
