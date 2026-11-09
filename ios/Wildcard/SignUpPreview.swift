import DesignSystem
import DesignSystemUI
import Foundation
import HealthUI
import LocationUI
import OnboardingUI
import SwiftUI

/// 预览注册, which 设置 offers admins: sign-up from the open screen to 上场 (or, for a squad
/// made, its scene's drop) on the in-memory sample squad, so an admin sees it as a newcomer does
/// on the App Store build. Nothing reaches the server: the open screen's button only moves on, and
/// every step saves into memory. It closes at the end, or from the open screen's 结束预览.
struct SignUpPreview: View {
    let model: SignUpModel
    let close: () -> Void

    /// A new sign-up on the sample squad, as a newcomer meets it now: 连上 Apple 健康 and the
    /// location step included, each on its sample, so 连接 plays without asking the system.
    static func model() -> SignUpModel {
        SignUpModel(
            service: InMemorySignUpService.sampleSquad(), nickname: "", now: Date(), health: sampleHealth(),
            location: .sample())
    }

    /// Apple Health not yet connected, on a sample day, keeping nothing on this phone.
    private static func sampleHealth() -> HealthConnection {
        let suite = "signUpPreview.health"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        return HealthConnection(library: SampleHealthLibrary(connected: false), defaults: defaults)
    }

    var body: some View {
        SignUpView(model: model, privacyPolicy: PolicyPages.privacyPolicy, terms: PolicyPages.terms) {
            ContinueWithApple { model.signedIn(name: nil) }
        } tabs: { showsBar, content in
            MainTabs.entranceTabs(showsBar: showsBar, content: content)
        }
        // On the open screen only: the steps after it keep their own buttons at the top, and their
        // back leads here.
        .overlay(alignment: .topLeading) {
            if model.step == .welcome {
                HeaderButton(Text(copy: "结束预览", bundle: .main), systemImage: "xmark", action: close)
                    .padding(.horizontal, Space.pageMargin)
                    .accessibilityIdentifier("signUpPreview.close")
            }
        }
        .onChange(of: model.finished) { _, finished in
            if finished != nil { close() }
        }
    }
}
