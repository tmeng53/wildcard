#if os(iOS)
import AvatarUI
import CheckInDomain
import DesignSystem
import DesignSystemUI
import SwiftUI

/// The 今天 tab: the squad's scene with the week's card on top, your character, and 打卡.
/// Every check-in starts and ends here: the burst opens over the lightly blurred scene, and
/// after posting you stay on the scene for the payoff (spec rev 186, section 1).
public struct TodayView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var model: TodayModel

    public init(model: TodayModel) {
        _model = State(initialValue: model)
    }

    public var body: some View {
        let theme = model.board?.scene ?? .track
        ZStack {
            SceneFloor(isBlurred: model.isSceneDimmed)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                if let board = model.board {
                    TopCard(board: board)
                        .padding(.horizontal, Space.gutter)
                        .padding(.top, Space.xs)
                        .blur(radius: model.isBurstOpen ? Scrim.blurRadius : 0)
                        // Out of the way while the 免责声明 card is up.
                        .opacity(model.step == .disclaimer ? 0 : 1)
                        .offset(y: model.step == .disclaimer ? -Space.s : 0)
                }
                Spacer(minLength: Space.l)
                Stage(model: model)
                    .blur(radius: model.isSceneDimmed ? Scrim.blurRadius : 0)
                Spacer(minLength: Space.l)
                // Holds the burst's place while the 免责声明 card hides it.
                Color.clear.frame(height: Sizing.checkInHeight)
                    .padding(.bottom, Space.l)
            }
            // The scene keeps its layout under the keyboard; only the card and the compose page
            // make room for it. Otherwise the scene, taller than what the keyboard leaves, pushes
            // them up under the status bar.
            .ignoresSafeArea(.keyboard)

            if model.isBurstOpen {
                // A tap anywhere outside the capsules closes the burst.
                Color.clear
                    .contentShape(Rectangle())
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.wildcard(Motion.burst, reduceMotion: reduceMotion)) { model.isBurstOpen = false }
                    }
                    .accessibilityHidden(true)
            }

            if model.step != .disclaimer {
                VStack {
                    Spacer()
                    CheckInBurst(
                        isOpen: $model.isBurstOpen, unavailable: model.unavailable, identifierPrefix: "today"
                    ) { meaning in
                        model.pick(meaning)
                    }
                    .padding(.bottom, Space.l)
                }
                .ignoresSafeArea(.keyboard)
                .transition(.opacity)
            }

            if model.step == .disclaimer {
                VStack {
                    DisclaimerCard(model: model)
                        .padding(.horizontal, Space.gutter)
                        .padding(.top, Space.xs)
                    Spacer()
                }
                .transition(
                    reduceMotion ? .opacity : .scale(scale: 0.7, anchor: .bottom).combined(with: .opacity))
            }

            if case .composing(let meaning) = model.step {
                ComposeView(model: model, meaning: meaning)
                    .transition(reduceMotion ? .opacity : .move(edge: .trailing))
                    .zIndex(1)
            }
        }
        .environment(\.sceneTheme, theme)
        .animation(.wildcard(Motion.smooth, reduceMotion: reduceMotion), value: model.step)
        .animation(.wildcard(Motion.bouncy, reduceMotion: reduceMotion), value: model.board)
        .animation(.wildcard(Motion.panel, reduceMotion: reduceMotion), value: model.payoff)
        .sheet(isPresented: isPickingPhotos) {
            PhotoStep(model: model)
                .environment(\.sceneTheme, theme)
        }
        // The one strong haptic of the payoff.
        .sensoryFeedback(.impact(weight: .heavy), trigger: model.posts)
        .task { await model.load() }
    }

    private var isPickingPhotos: Binding<Bool> {
        Binding {
            if case .pickingPhotos = model.step { true } else { false }
        } set: { isPresented in
            // Swiped down: the same as 取消.
            if !isPresented, case .pickingPhotos = model.step { model.cancel() }
        }
    }
}

/// The character on the scene, with the payoff's bubble and pinned cover above it.
private struct Stage: View {
    let model: TodayModel

    var body: some View {
        VStack(spacing: Space.s) {
            PayoffBubble(payoff: model.payoff)
                .frame(minHeight: Space.xxl)
            if let player = model.player {
                CharacterView(player: player)
                    .frame(height: 220)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

/// The caption in a bubble over the character, with the cover photo pinned beside it like a
/// polaroid. Nothing until the first post.
private struct PayoffBubble: View {
    @Environment(\.sceneTheme) private var theme
    let payoff: TodayModel.Payoff?

    var body: some View {
        if let payoff, payoff.line != nil || payoff.cover != nil {
            HStack(alignment: .top, spacing: Space.xs) {
                if let line = payoff.line {
                    Text(verbatim: line)
                        .typeStyle(TypeRamp.caption)
                        .foregroundStyle(Color(role: .textPrimary, in: theme))
                        .multilineTextAlignment(.leading)
                        .padding(.horizontal, Space.s)
                        .padding(.vertical, Space.xs)
                        .frame(maxWidth: 230, alignment: .leading)
                        .background(
                            Color(Palette.white).opacity(0.94),
                            in: RoundedRectangle(cornerRadius: Radius.m, style: .continuous))
                }
                if let cover = payoff.cover {
                    PhotoImage(photo: cover)
                        .frame(width: 58, height: 58)
                        .clipShape(RoundedRectangle(cornerRadius: Space.xxs, style: .continuous))
                        .padding(Space.xxs)
                        .background(Color(Palette.white), in: RoundedRectangle(cornerRadius: Space.xs))
                        .rotationEffect(.degrees(8))
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, Space.gutter)
            .transition(.scale(scale: 0.6, anchor: .bottom).combined(with: .opacity))
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("today.bubble")
        }
    }
}

#Preview {
    TodayView(
        model: TodayModel(service: InMemoryCheckInService.sampleSquad(now: .now), writer: DiceDisclaimerWriter()))
}
#endif
