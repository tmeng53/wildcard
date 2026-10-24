#if os(iOS)
import CheckInUI
import DesignSystem
import DesignSystemUI
import OnboardingDomain
import ScenePickUI
import SwiftUI

/// 这周在哪练？, for whoever made the squad (approved 2026-10-23): five cartons, as the squad has
/// trained nowhere yet. 「就它了」 saves the pick, and its carton opens over the page as on the
/// 战报's last page; once the scene has filled the screen sign-up is over, and the member drops
/// onto it at home.
struct SceneStep: View {
    let model: SignUpModel

    /// The design's cartons: 96 high, 8 apart, 20 under the title.
    private static let tileHeight = 96.0

    var body: some View {
        ZStack {
            page
                // Under the reveal the page is a picture: no taps, nothing for VoiceOver.
                .allowsHitTesting(model.reveal == nil)
                .accessibilityHidden(model.reveal != nil)
            if let reveal = model.reveal {
                UnboxRevealView(
                    reveal.unboxing, scene: reveal.scene, startedAt: reveal.startedAt,
                    onFinished: { _ in model.sceneRevealed() },
                    page: { page },
                    backdrop: { SceneBackdrop(scene: reveal.scene) })
            }
        }
    }

    private var page: some View {
        StepPage(
            step: .scene, title: Text("这周在哪练？", bundle: .module), character: model.myCharacter, onBack: model.back
        ) {
            if let picker = model.scenePicker {
                SceneTileRow(picker: picker, height: Self.tileHeight, spacing: Space.xs)
                    .padding(.top, Space.xxs)
            }
        } actions: {
            FailureLine(failure: model.failure)
            StepButton(
                title: Text("就它了", bundle: .module), isWorking: model.isPickingScene,
                isEnabled: model.scenePicker?.canConfirm ?? false, action: model.confirmScene
            )
            .accessibilityIdentifier("scene.done")
        }
    }
}
#endif
