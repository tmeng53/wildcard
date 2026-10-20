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
        // The 请假条 composer and the compose page make room for the keyboard. The scene sits in
        // the background, so it neither sizes this stack nor moves with the keyboard: as a layer
        // of it, the scene, taller than what the keyboard leaves, would push the composer and the
        // page up under the status bar.
        ZStack {
            if model.step == .disclaimer {
                DisclaimerComposer(model: model)
                    .transition(.opacity)
            }

            if case .composing(let kind) = model.step {
                ComposeView(model: model, kind: kind)
                    .transition(reduceMotion ? .opacity : .move(edge: .trailing))
                    .zIndex(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            scene.ignoresSafeArea(.keyboard)
        }
        .environment(\.sceneTheme, theme)
        .animation(.wildcard(Motion.page, reduceMotion: reduceMotion), value: model.step)
        .animation(.wildcard(Motion.celebrate, reduceMotion: reduceMotion), value: model.board)
        .animation(.wildcard(Motion.sheet, reduceMotion: reduceMotion), value: model.payoff)
        .sheet(isPresented: isPickingPhotos) {
            PhotoStep(model: model)
                .environment(\.sceneTheme, theme)
        }
        // The one strong haptic of the payoff.
        .haptic(.checkIn, trigger: model.posts)
        .task { await model.load() }
    }

    /// The floor, the week's card, the character and the 打卡 burst.
    private var scene: some View {
        ZStack {
            SceneFloor(isBlurred: model.isSceneDimmed)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                if let board = model.board {
                    TopCard(board: board)
                        .padding(.horizontal, Space.pageMargin)
                        .padding(.top, Space.xs)
                        .blur(radius: model.isBurstOpen ? Scrim.blurRadius : 0)
                        // Out of the way while the 请假条 composer is up.
                        .opacity(model.step == .disclaimer ? 0 : 1)
                        .offset(y: model.step == .disclaimer ? -Space.s : 0)
                }
                Spacer(minLength: Space.l)
                Stage(model: model)
                    .blur(radius: model.isSceneDimmed ? Scrim.blurRadius : 0)
                    // The 请假条 composer shows the character above the keyboard instead.
                    .opacity(model.step == .disclaimer ? 0 : 1)
                Spacer(minLength: Space.l)
                // Holds the burst's place while the 请假条 composer hides it.
                Color.clear.frame(height: Sizing.primaryControl)
                    .padding(.bottom, Space.l)
            }

            if model.isBurstOpen {
                // A tap anywhere outside the capsules closes the burst.
                Color.clear
                    .contentShape(Rectangle())
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.wildcard(Motion.sheet, reduceMotion: reduceMotion)) { model.isBurstOpen = false }
                    }
                    .accessibilityHidden(true)
            }

            if model.step != .disclaimer {
                VStack {
                    Spacer()
                    CheckInBurst(
                        isOpen: $model.isBurstOpen, unavailable: model.unavailable, identifierPrefix: "today"
                    ) { kind in
                        model.pick(kind)
                    }
                    .padding(.bottom, Space.l)
                }
                .transition(.opacity)
            }
        }
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

/// The character on the scene. The payoff's bubble sits on its head, pointing down at it, and
/// the cover photo is pinned beside it like a polaroid: one figure, not three objects.
private struct Stage: View {
    /// The figure's height on the scene.
    private static let figureHeight: Double = 220
    /// How far below the top of the figure's frame the bubble's tail ends: the art leaves this
    /// much room above the hair for hats and the cheer's jump.
    private static let headroom: Double = 0.16
    /// Width over height of the empty spot that stands in for missing art.
    private static let placeholderAspect: Double = 0.6

    let model: TodayModel

    var body: some View {
        figure
            .frame(height: Self.figureHeight)
            .overlay(alignment: .top) {
                PayoffBubble(line: model.payoff?.line)
                    .alignmentGuide(.top) { $0[.bottom] - Self.figureHeight * Self.headroom }
            }
            .overlay(alignment: .topTrailing) {
                PinnedCover(cover: model.payoff?.cover)
                    .alignmentGuide(.trailing) { $0[.leading] + Space.xxs }
                    .alignmentGuide(.top) { $0[.top] - Self.figureHeight * 0.18 }
            }
            .frame(maxWidth: .infinity)
    }

    /// The character, or an empty spot of its size if its art failed to load, so a post still
    /// shows its line and cover.
    @ViewBuilder private var figure: some View {
        if let player = model.player {
            CharacterView(player: player)
        } else {
            Color.clear.frame(width: Self.figureHeight * Self.placeholderAspect)
        }
    }
}

/// The caption in the character's speech bubble. Nothing until the first post with a line.
private struct PayoffBubble: View {
    /// The widest a bubble grows before its line wraps.
    private static let maxWidth: Double = 230

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let line: String?

    var body: some View {
        if let line {
            SpeechBubble(Text(verbatim: line))
                // A fixed-width frame centres the bubble; the text inside takes only the width it needs.
                .frame(width: Self.maxWidth)
                .transition(.speech(reduceMotion: reduceMotion))
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("today.bubble")
        }
    }
}

/// The post's cover photo, pinned beside the character's head.
private struct PinnedCover: View {
    @Environment(\.sceneTheme) private var theme
    let cover: PreparedPhoto?

    var body: some View {
        if let cover {
            PhotoImage(photo: cover)
                .frame(width: 58, height: 58)
                .clipShape(RoundedRectangle(cornerRadius: Radius.thumbnail - Space.xxs, style: .continuous))
                .padding(Space.xxs)
                .background(
                    Color(role: .bgCanvas, in: theme),
                    in: RoundedRectangle(cornerRadius: Radius.thumbnail, style: .continuous)
                )
                .rotationEffect(.degrees(8))
                .transition(.scale(scale: 0.6).combined(with: .opacity))
                .accessibilityHidden(true)
        }
    }
}

#Preview {
    TodayView(
        model: TodayModel(service: InMemoryCheckInService.sampleSquad(now: .now), writer: DiceDisclaimerWriter()))
}
#endif
