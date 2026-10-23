#if os(iOS)
import Contracts
import DesignSystem
import DesignSystemUI
import OnboardingDomain
import SwiftUI

/// 你的小队, step 2: 加入小队 by invite code, with the squad it finds, or 建一个小队 with a
/// name. The character just made stands beside the title.
struct SquadStep: View {
    let model: SignUpModel
    let privacyPolicy: URL
    @Environment(\.sceneTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        StepPage(step: .squad, title: Text("你的小队", bundle: .module), character: model.myCharacter, onBack: model.back) {
            VStack(alignment: .leading, spacing: Space.xs) {
                PickRow(Text("加入小队", bundle: .module), systemImage: "person.2", isSelected: isJoining) {
                    model.choose(.join)
                }
                .accessibilityIdentifier("squad.join")
                if isJoining {
                    JoinPanel(model: model)
                        .transition(panelTransition)
                }
                PickRow(Text("建一个小队", bundle: .module), systemImage: "plus", isSelected: !isJoining) {
                    model.choose(.create)
                }
                .accessibilityIdentifier("squad.create")
                if !isJoining {
                    CreatePanel(model: model)
                        .transition(panelTransition)
                }
            }
            .animation(.wildcard(Motion.sheet, reduceMotion: reduceMotion), value: isJoining)
            // Back here after joining or making the squad: it shows what was chosen, read-only.
            .disabled(model.joined != nil)
        } actions: {
            if model.asksForAIConsent {
                AIConsentLine(privacyPolicy: privacyPolicy)
            }
            FailureLine(failure: model.failure)
            StepButton(
                title: isJoining ? Text("加入小队", bundle: .module) : Text("建小队", bundle: .module),
                isWorking: model.isWorking, isEnabled: model.canFinishSquad, action: model.finishSquad
            )
            .accessibilityIdentifier("squad.done")
        }
    }

    private var isJoining: Bool { model.squad.choice == .join }

    private var panelTransition: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .offset(y: -Space.xs))
    }
}

/// 邀请码 in one box per letter, typed into a field the boxes cover, and the squad it finds.
private struct JoinPanel: View {
    let model: SignUpModel
    @Environment(\.sceneTheme) private var theme
    @FocusState private var isTyping: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Space.labelGap) {
            SectionLabel(Text("邀请码", bundle: .module))
            ZStack {
                TextField(
                    text: Binding(get: { model.squad.typedCode }, set: { model.typeCode($0) }),
                    prompt: Text(verbatim: "")
                ) {
                    Text("邀请码", bundle: .module)
                }
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .keyboardType(.asciiCapable)
                .focused($isTyping)
                // The boxes show what is typed; the field only takes the keys.
                .opacity(0.02)
                .accessibilityIdentifier("squad.code")
                HStack(spacing: Space.xxs + 2) {
                    ForEach(0..<InviteCode.length, id: \.self) { index in
                        CodeBox(
                            letter: index < model.squad.codeLetters.count ? model.squad.codeLetters[index] : nil,
                            isNext: isTyping && index == min(model.squad.codeLetters.count, InviteCode.length - 1))
                    }
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
            .onTapGesture { isTyping = true }
            SquadFound(lookup: model.preview)
                .padding(.top, Space.xxs)
        }
        .padding(.vertical, Space.xs)
        .onAppear { if model.squad.code == nil { isTyping = true } }
    }
}

/// One letter of the invite code, in big Barlow on a subtle box; the box the next letter goes
/// into takes the accent border while typing.
private struct CodeBox: View {
    let letter: Character?
    let isNext: Bool
    @Environment(\.sceneTheme) private var theme
    private let height: Double = 52

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.pick, style: .continuous)
        Text(verbatim: letter.map(String.init) ?? "")
            .typeStyle(TypeRamp.scoreCard)
            .foregroundStyle(Color(role: .fgDefault, in: theme))
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(Color(role: .bgSubtle, in: theme), in: shape)
            .overlay {
                if isNext {
                    shape.strokeBorder(Color(role: .bgAccent, in: theme), lineWidth: Sizing.selectionStroke)
                }
            }
    }
}

/// The squad a whole code finds: its name and how many are in it, or why there's none.
private struct SquadFound: View {
    let lookup: SignUpModel.Lookup
    @Environment(\.sceneTheme) private var theme

    var body: some View {
        switch lookup {
        case .none:
            EmptyView()
        case .looking:
            HStack(spacing: Space.xs) {
                ProgressView()
                Text("正在找这个小队", bundle: .module)
                    .typeStyle(TypeRamp.footnote)
                    .foregroundStyle(Color(role: .fgMuted, in: theme))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
        case .found(let squad):
            HStack(spacing: Space.s) {
                Image(systemName: "flag.checkered")
                    .font(.system(size: Sizing.icon, weight: .semibold))
                    .foregroundStyle(Color(role: .fgAccent, in: theme))
                    .frame(width: Sizing.control, height: Sizing.control)
                    .background(
                        Color(role: .bgAccentSubtle, in: theme), in: RoundedRectangle(cornerRadius: Radius.thumbnail)
                    )
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Space.xxs) {
                    Text(verbatim: squad.name)
                        .typeStyle(TypeRamp.headline)
                        .foregroundStyle(Color(role: .fgDefault, in: theme))
                        .lineLimit(1)
                    Group {
                        if squad.isFull {
                            Text("\(squad.memberCount) 人 · 满员了", bundle: .module)
                        } else {
                            Text("\(squad.memberCount) 人", bundle: .module)
                        }
                    }
                    .typeStyle(TypeRamp.footnote)
                    .foregroundStyle(Color(role: .fgMuted, in: theme))
                }
                Spacer(minLength: 0)
            }
            .card()
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("squad.found")
        case .failed(_, let failure):
            FailureLine(failure: failure)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// The AI consent, one small grey line under the button (Tracy, 2026-10-23): going on agrees to
/// send the text the member writes to third-party AI, and 隐私政策 says which and what for. The
/// catalog marks the link `privacy:`, which becomes the page the app passes.
private struct AIConsentLine: View {
    let privacyPolicy: URL
    @Environment(\.sceneTheme) private var theme

    var body: some View {
        Text(line)
            .typeStyle(TypeRamp.footnote)
            .foregroundStyle(Color(role: .fgMuted, in: theme))
            .tint(Color(role: .fgDefault, in: theme))
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .accessibilityIdentifier("squad.aiConsent")
    }

    private var line: AttributedString {
        var line = AttributedString(
            localized: "继续即表示同意把你写的文字发给第三方 AI · [隐私政策](privacy:)", bundle: .module)
        for (link, range) in line.runs[\.link] where link != nil {
            line[range].link = privacyPolicy
            line[range].underlineStyle = .single
        }
        return line
    }
}

/// 小队名, starting from 「Tracy 的小队」.
private struct CreatePanel: View {
    let model: SignUpModel

    var body: some View {
        VStack(alignment: .leading, spacing: Space.labelGap) {
            SectionLabel(Text("小队名", bundle: .module))
            InputField(
                text: Binding(get: { model.squad.typedName }, set: { model.typeName($0) }),
                label: Text("小队名", bundle: .module), limit: SquadName.maxLength
            )
            .accessibilityIdentifier("squad.name")
        }
        .padding(.top, Space.xs)
    }
}
#endif
