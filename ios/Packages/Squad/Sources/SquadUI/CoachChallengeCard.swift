#if os(iOS)
import Contracts
import DesignSystem
import DesignSystemUI
import SquadDomain
import SwiftUI

/// A day's challenge's answers, under its card.
struct ChallengeAnswers: View {
    let deck: CoachDeck
    let card: CoachPageCard
    @Binding var stamped: Bool
    @Binding var reason: String
    var typing: FocusState<Bool>.Binding
    let putAway: ((CoachPageCard) -> Void)?
    @Environment(\.sceneTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 接受挑战, big, on top; under it a small field to tell the coach why and 不接挑战 (Tracy,
    /// 2026-11-08). Accepting stamps the card and pops the button before the card goes; declining
    /// sends the card away at once, with what was typed.
    var body: some View {
        VStack(spacing: Space.s) {
            Button(action: accept) {
                Text(copy: "接受挑战", bundle: .module).frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle(.large))
            .accentTone(.scene)
            .keyframeAnimator(initialValue: 1.0, trigger: stamped && !reduceMotion) { content, scale in
                content.scaleEffect(scale)
            } keyframes: { _ in
                KeyframeTrack {
                    CubicKeyframe(0.92, duration: DeckMetrics.squash)
                    SpringKeyframe(1.06, duration: DeckMetrics.squash * 2, spring: .snappy)
                    SpringKeyframe(1, duration: Motion.celebrate.response, spring: .bouncy)
                }
            }
            .haptic(.land, trigger: stamped)
            .accessibilityIdentifier("coachDeck.accept")
            HStack(spacing: Space.xs) {
                reasonField
                Button(action: decline) { Text(copy: "不接挑战", bundle: .module) }
                    .buttonStyle(SecondaryButtonStyle(.onInk))
                    .overlay {
                        Capsule().strokeBorder(Color(role: .borderDefault, in: theme), lineWidth: Sizing.hairline)
                    }
                    .accessibilityIdentifier("coachDeck.decline")
            }
        }
    }

    /// 「原因（可选）」: one line, as long as the API takes.
    private var reasonField: some View {
        let prompt = Text(copy: "原因（可选）", bundle: .module)
        return TextField(text: $reason, prompt: prompt.foregroundStyle(Color(role: .fgSubtle, in: theme))) {
            prompt
        }
        .typeStyle(TypeRamp.field)
        .foregroundStyle(Color(role: .fgDefault, in: theme))
        .focused(typing)
        .submitLabel(.done)
        .padding(.horizontal, Space.m)
        .frame(height: Sizing.control)
        .overlay { Capsule().strokeBorder(Color(role: .borderDefault, in: theme), lineWidth: Sizing.hairline) }
        .onChange(of: reason) { _, typed in
            if typed.count > CoachChallengeAnswer.reasonLimit {
                reason = String(typed.prefix(CoachChallengeAnswer.reasonLimit))
            }
        }
        .accessibilityIdentifier("coachDeck.reason")
    }

    private func accept() {
        typing.wrappedValue = false
        Task {
            await deck.answer(card, .accepted)
            guard deck.current(card).challenge?.answer != nil else { return }
            stamped = true
            try? await Task.sleep(for: .seconds(reduceMotion ? 0 : DeckMetrics.stampHold))
            putAway?(card)
        }
    }

    private func decline() {
        typing.wrappedValue = false
        Task {
            await deck.answer(card, .declined, reason: reason)
            if deck.current(card).challenge?.answer != nil { putAway?(card) }
        }
    }
}

/// A day's challenge: what to do first, then its amount big in the scene's colour with its unit
/// (「早餐加鸡蛋」, 「1 个」; Tracy, 2026-11-08), the coach's line, and the round 挑战 stamp, which
/// comes down again when the challenge is accepted.
struct ChallengeFace: View {
    let challenge: CoachPageCard.Challenge
    var stamped = false
    @Environment(\.sceneTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xxs) {
            Text(verbatim: challenge.title)
                .typeStyle(TypeRamp.taskTitle)
                .foregroundStyle(Color(role: .fgDefault, in: theme))
                .lineLimit(1)
            if let amount = challenge.amount {
                HStack(alignment: .firstTextBaseline, spacing: Space.xxs + 2) {
                    Text(verbatim: "\(amount)")
                        .typeStyle(TypeRamp.scoreEnding)
                        .minimumScaleFactor(0.6)
                    if let unit = challenge.unit {
                        Text(verbatim: unit).typeStyle(TypeRamp.title)
                    }
                }
                .foregroundStyle(Color(role: .fgAccent, in: theme))
                .lineLimit(1)
            }
            if let line = challenge.line {
                Text(verbatim: line)
                    .typeStyle(TypeRamp.callout)
                    .foregroundStyle(Color(role: .fgMuted, in: theme))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.trailing, DeckMetrics.stamp)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .topTrailing) {
            ChallengeStamp()
                .keyframeAnimator(initialValue: 1.0, trigger: stamped && !reduceMotion) { stamp, scale in
                    stamp.scaleEffect(scale)
                } keyframes: { _ in
                    // Lifted, then slammed down past its size, then settled.
                    KeyframeTrack {
                        CubicKeyframe(1.5, duration: DeckMetrics.squash)
                        CubicKeyframe(0.9, duration: DeckMetrics.squash)
                        SpringKeyframe(1, duration: Motion.celebrate.response, spring: .bouncy)
                    }
                }
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("coachDeck.challenge")
    }
}

/// 挑战 in a double ring, tilted like a rubber stamp, in the scene's colour (Tracy, 2026-11-08:
/// simple, no other words).
struct ChallengeStamp: View {
    @Environment(\.sceneTheme) private var theme

    var body: some View {
        let ink = Color(role: .fgAccent, in: theme)
        Text(copy: "挑战", bundle: .module)
            .typeStyle(TypeRamp.title)
            .tracking(2)
            .foregroundStyle(ink)
            .frame(width: DeckMetrics.stamp, height: DeckMetrics.stamp)
            .overlay {
                Circle().strokeBorder(ink, lineWidth: 3)
                Circle().strokeBorder(ink, lineWidth: 1.2).padding(Space.xxs + 2)
            }
            .rotationEffect(.degrees(-14))
    }
}
#endif
