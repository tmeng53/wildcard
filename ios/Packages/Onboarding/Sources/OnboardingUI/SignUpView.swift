#if os(iOS)
import CharacterEditorUI
import DesignSystem
import DesignSystemUI
import OnboardingDomain
import SwiftUI

/// Sign-up, from the open screen to 上场. Each step slides in from the side it comes from.
/// `signIn` is the open screen's 通过 Apple 继续, which the app wires to its account; it calls
/// `SignUpModel.signedIn(name:)` once the member is in. The open screen's terms line and the AI
/// consent link to the published policy pages the app passes.
public struct SignUpView<SignIn: View>: View {
    private let model: SignUpModel
    private let policies: PolicyLinks
    private let signIn: SignIn
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(model: SignUpModel, privacyPolicy: URL, terms: URL, @ViewBuilder signIn: () -> SignIn) {
        self.model = model
        self.policies = PolicyLinks(privacyPolicy: privacyPolicy, terms: terms)
        self.signIn = signIn()
    }

    public var body: some View {
        ZStack {
            switch model.step {
            case .welcome:
                WelcomeScreen(model: model, policies: policies, signIn: signIn)
                    .transition(transition)
            case .character:
                if let editor = model.editor {
                    CharacterEditorView(
                        model: editor, context: .signUp(step: 1, total: SignUpStep.counted.count), onBack: model.back,
                        onDone: model.finishCharacter
                    )
                    .transition(transition)
                }
            case .squad:
                SquadStep(model: model, privacyPolicy: policies.privacyPolicy)
                    .transition(transition)
            case .sports:
                SportsStep(model: model)
                    .transition(transition)
            case .week:
                WeekStep(model: model)
                    .transition(transition)
            case .entrance:
                EntranceScreen(model: model)
                    .transition(.opacity)
            }
        }
        .animation(.wildcard(Motion.page, reduceMotion: reduceMotion), value: model.step)
    }

    private var transition: AnyTransition {
        if reduceMotion { return .opacity }
        return model.isGoingForward
            ? .asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading))
            : .asymmetric(insertion: .move(edge: .leading), removal: .move(edge: .trailing))
    }
}

/// The published privacy policy and terms.
struct PolicyLinks {
    let privacyPolicy: URL
    let terms: URL
}
#endif
