#if os(iOS)
import AvatarUI
import DesignSystem
import DesignSystemUI
import OnboardingDomain
import SwiftUI

/// A sign-up task step on a white page: back and the step's segments at the top, the title with
/// the character just made standing beside it, the step's content, then its buttons at the
/// bottom, above the keyboard when it's up.
struct StepPage<Content: View, Actions: View>: View {
    let step: SignUpStep
    let title: Text
    /// The character beside the title; nil where the step draws it itself.
    let character: CastMember?
    let onBack: () -> Void
    @ViewBuilder let content: Content
    @ViewBuilder let actions: Actions
    @Environment(\.sceneTheme) private var theme

    /// The character beside the title, in the design's 96 by 128.
    static var characterSize: CGSize { CGSize(width: 96, height: 128) }

    var body: some View {
        VStack(spacing: 0) {
            StepHeader(step: step.number ?? 1, of: SignUpStep.counted.count, onBack: onBack)
                .padding(.horizontal, Space.pageMargin)
                .padding(.top, Space.xs)
            ScrollView {
                VStack(alignment: .leading, spacing: Space.m) {
                    HStack(alignment: .bottom, spacing: Space.s) {
                        title
                            .typeStyle(TypeRamp.taskTitle)
                            .foregroundStyle(Color(role: .fgDefault, in: theme))
                            .accessibilityAddTraits(.isHeader)
                            .padding(.bottom, Space.s)
                        Spacer(minLength: 0)
                        if let player = character?.player {
                            CharacterView(player: player)
                                .frame(width: Self.characterSize.width, height: Self.characterSize.height)
                        }
                    }
                    // Room for the character only on the steps that show one beside the title.
                    .frame(minHeight: character == nil ? nil : Self.characterSize.height, alignment: .bottom)
                    content
                }
                .padding(.horizontal, Space.pageMargin)
                .padding(.bottom, Space.l)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: Space.xxs) { actions }
                .padding(.horizontal, Space.pageMargin)
                .padding(.top, Space.xs)
                .padding(.bottom, Space.xs)
                .background(Color(role: .bgCanvas, in: theme))
        }
        .background(Color(role: .bgCanvas, in: theme).ignoresSafeArea())
    }
}

/// The step's one primary action, full width; it shows a spinner while its call is under way.
struct StepButton: View {
    @Environment(\.sceneTheme) private var theme
    let title: Text
    let isWorking: Bool
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                title.opacity(isWorking ? 0 : 1)
                if isWorking {
                    ProgressView().tint(Color(role: .fgOnBrand, in: theme))
                }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(PrimaryButtonStyle())
        .disabled(!isEnabled || isWorking)
    }
}

/// What went wrong with the step's last call, in a line above its button.
struct FailureLine: View {
    let failure: SignUpError?
    @Environment(\.sceneTheme) private var theme

    var body: some View {
        if let failure {
            Self.message(for: failure)
                .typeStyle(TypeRamp.footnoteEmphasis)
                .foregroundStyle(Color(role: .fgDefault, in: theme))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Space.xxs)
                .accessibilityIdentifier("signup.failure")
        }
    }

    static func message(for failure: SignUpError) -> Text {
        switch failure {
        case .unknownInvite: Text("没找到这个邀请码", bundle: .module)
        case .squadFull: Text("这个小队满 8 人了", bundle: .module)
        case .tooManySquads: Text("你已经在 3 个小队里了", bundle: .module)
        case .rejected: Text("没存上，换个写法试试", bundle: .module)
        case .unavailable: Text("网络开小差了，再试一次", bundle: .module)
        }
    }
}
#endif
