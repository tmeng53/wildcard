#if os(iOS)
import AvatarUI
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
        StepPage(
            step: .squad, title: Text(copy: "你的小队", bundle: .module), character: model.myCharacter, onBack: model.back
        ) {
            VStack(alignment: .leading, spacing: Space.xs) {
                PickRow(Text(copy: "加入小队", bundle: .module), systemImage: "person.2", isSelected: isJoining) {
                    model.choose(.join)
                }
                .accessibilityIdentifier("squad.join")
                if isJoining {
                    JoinPanel(model: model)
                        .transition(panelTransition)
                }
                PickRow(Text(copy: "建一个小队", bundle: .module), systemImage: "plus", isSelected: !isJoining) {
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
            FailureLine(failure: model.failure)
            StepButton(
                title: isJoining ? Text(copy: "加入小队", bundle: .module) : Text(copy: "建小队", bundle: .module),
                isWorking: model.isWorking, isEnabled: model.canFinishSquad, action: model.finishSquad
            )
            .accessibilityIdentifier("squad.done")
            if model.asksForAIConsent {
                AIConsentLine(privacyPolicy: privacyPolicy)
                    .padding(.top, Space.xxs)
            }
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
            SectionLabel(Text(copy: "邀请码", bundle: .module))
            ZStack {
                TextField(
                    text: Binding(get: { model.squad.typedCode }, set: { model.typeCode($0) }),
                    prompt: Text(verbatim: "")
                ) {
                    Text(copy: "邀请码", bundle: .module)
                }
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .keyboardType(.asciiCapable)
                .submitLabel(.done)
                .onSubmit { isTyping = false }
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
            SquadFound(lookup: model.preview, heads: model.previewHeads)
                .padding(.top, Space.xxs)
        }
        .padding(.vertical, Space.xs)
        .onAppear { if model.squad.code == nil { isTyping = true } }
        // A whole code puts the keyboard away, so the squad it finds shows above the button.
        .onChange(of: model.squad.code) { _, code in if code != nil { isTyping = false } }
    }
}

/// One letter of the invite code, in big Barlow on a white box with a hairline, like the rows
/// around it; the box the next letter goes into takes the accent border while typing.
private struct CodeBox: View {
    let letter: Character?
    let isNext: Bool
    @Environment(\.sceneTheme) private var theme
    @Environment(\.accentTone) private var tone
    private let height: Double = 52

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.pick, style: .continuous)
        Text(verbatim: letter.map(String.init) ?? "")
            .typeStyle(TypeRamp.scoreCard)
            .foregroundStyle(Color(role: .fgDefault, in: theme))
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(Color(role: .bgCanvas, in: theme), in: shape)
            .overlay {
                if isNext {
                    shape.strokeBorder(Color(role: tone.fill, in: theme), lineWidth: Sizing.selectionStroke)
                } else {
                    shape.strokeBorder(Color(role: .borderDefault, in: theme), lineWidth: Sizing.hairline)
                }
            }
    }
}

/// The squad a whole code finds, on a white card with a hairline like the rows around it (Tracy,
/// 2026-11-08): its name, its members' heads and how many are in it, or why there's none.
private struct SquadFound: View {
    let lookup: SignUpModel.Lookup
    let heads: [CastMember]
    @Environment(\.sceneTheme) private var theme

    var body: some View {
        switch lookup {
        case .none:
            EmptyView()
        case .looking:
            HStack(spacing: Space.xs) {
                // The card says what is happening, so its dots show at once.
                LoadingDots(delay: 0)
                    .foregroundStyle(Color(role: .fgDefault, in: theme))
                Text(copy: "正在找这个小队", bundle: .module)
                    .typeStyle(TypeRamp.footnote)
                    .foregroundStyle(Color(role: .fgMuted, in: theme))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
        case .found(let squad):
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(verbatim: squad.name)
                    .typeStyle(TypeRamp.headline)
                    .foregroundStyle(Color(role: .fgDefault, in: theme))
                    .lineLimit(1)
                HStack(spacing: Space.xs) {
                    if !heads.isEmpty {
                        HeadStack(heads.map(\.player), size: Sizing.characterHead, on: .bgCanvas)
                    }
                    Group {
                        if squad.isFull {
                            Text(copy: "\(squad.memberCount) 人 · 满员了", bundle: .module)
                        } else {
                            Text(copy: "\(squad.memberCount) 人 · 人均每周 \(squad.daysPerMember) 次", bundle: .module)
                        }
                    }
                    .typeStyle(TypeRamp.footnote)
                    .foregroundStyle(Color(role: .fgMuted, in: theme))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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
        var line = AppCopyLines.attributed("继续即表示同意把你写的文字发给第三方 AI · [隐私政策](privacy:)", bundle: .module)
        for (link, range) in line.runs[\.link] where link != nil {
            line[range].link = privacyPolicy
            line[range].underlineStyle = .single
        }
        return line
    }
}

/// 小队名, starting from 「Tracy 的小队」, under it 小队目标: each member's days a week, 3 to
/// begin with, which the captain changes later on 小队, then 比赛时区: the phone's to begin with.
private struct CreatePanel: View {
    let model: SignUpModel
    @Environment(\.sceneTheme) private var theme
    @State private var isChoosingZone = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.labelGap) {
            SectionLabel(Text(copy: "小队名", bundle: .module))
            InputField(
                text: Binding(get: { model.squad.typedName }, set: { model.typeName($0) }),
                label: Text(copy: "小队名", bundle: .module), limit: SquadName.maxLength
            )
            .accessibilityIdentifier("squad.name")
            SectionLabel(Text(copy: "小队目标 · 每人每周练几次", bundle: .module))
                .padding(.top, Space.s)
            HStack(spacing: Space.xxs) {
                ForEach(Array(SquadWeeklyGoal.choices), id: \.self) { days in
                    PickPill(Text(verbatim: "\(days)"), isSelected: days == model.squad.daysPerMember) {
                        model.pickDaysPerMember(days)
                    }
                    .accessibilityLabel(Text(copy: "人均 \(days) 次", bundle: .module))
                    .accessibilityAddTraits(days == model.squad.daysPerMember ? .isSelected : [])
                    .accessibilityIdentifier("squad.goal.pick.\(days)")
                }
            }
            SectionLabel(Text(copy: "比赛时区", bundle: .module))
                .padding(.top, Space.s)
            ListRow(Text(verbatim: zone.region), value: Text(verbatim: zone.city), showsDivider: false) {
                isChoosingZone = true
            }
            .accessibilityIdentifier("squad.timeZone")
            Text(copy: "用于全队都能看到的内容，比如周日晚 8 点的战报", bundle: .module)
                .typeStyle(TypeRamp.footnote)
                .foregroundStyle(Color(role: .fgMuted, in: theme))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, Space.xs)
        .sheet(isPresented: $isChoosingZone) {
            TimeZonePicker(selected: model.squad.timeZone) { picked in
                model.pickTimeZone(picked)
                isChoosingZone = false
            }
        }
    }

    private var zone: ZoneName { ZoneName(model.squad.timeZone, locale: AppLanguage.current.locale) }
}

extension SignUpModel {
    /// 比赛时区, for the squad being made: any zone the phone knows.
    func pickTimeZone(_ identifier: String) {
        guard TimeZone(identifier: identifier) != nil else { return }
        squad.timeZone = identifier
    }

    /// 小队目标 · 每人每周练几次, for the squad being made.
    func pickDaysPerMember(_ days: Int) {
        guard SquadWeeklyGoal.choices.contains(days) else { return }
        squad.daysPerMember = days
    }

    /// The squad's goal this week, before and after the member's 人均 N 次 adds to it.
    var squadGoal: (before: Int, after: Int) {
        let before = joined?.weekGoal ?? 0
        return (before, before + (joined?.daysPerMember ?? 0))
    }

    /// 「Tracy 的小队」.
    static func suggestedName(for nickname: String) -> String {
        String(copy: "\(nickname) 的小队", bundle: .module)
    }
}

extension SignUpModel {
    /// The invite code found while looking one up.
    enum Lookup: Equatable {
        case none
        case looking(InviteCode)
        case found(SquadPreview)
        case failed(InviteCode, SignUpError)
    }
}
#endif
