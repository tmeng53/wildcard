#if os(iOS)
import Contracts
import DesignSystem
import DesignSystemUI
import SquadDomain
import SwiftUI

/// The coach's page (the approved deck, 2026-11-08), pushed from a tap on the coach on 今天: what
/// the coach has for the member that they haven't seen, a stack of cards, one thing each, oldest
/// on top. Swiped right, a card flies into 以前 (the clock, top right, which gives a nudge);
/// nothing turns by itself. Each card is as tall as what it says; under the stack, how many are
/// left and 下一张, which puts the top one away as the swipe does (Tracy, 2026-11-21), and on
/// opening the top card leans right and back once to show it (Tracy, 2026-11-09). Top right,
/// from the left: 招聘会, 简历, 以前. Once all are seen,
/// the last card says so with 看以前的.
public struct CoachDeckPage: View {
    private let deck: CoachDeck
    private let coach: CoachSpeaker
    private let coachLook: String
    private let cast: DeckCast
    private let places: CoachDeckPlaces
    /// The top card's drag, and where it flies once let go far enough.
    @State private var drag: CGSize = .zero
    @State private var flying: CoachPageCard.Key?
    /// The top card has leaned right and back once since the page opened.
    @State private var nudged = false
    /// The top card's height, which the cards under it take so only their edges peek out.
    @State private var topHeight: Double?
    @Environment(\.sceneTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(deck: CoachDeck, coach: CoachSpeaker, coachLook: String, cast: DeckCast, places: CoachDeckPlaces) {
        (self.deck, self.coach, self.coachLook, self.cast, self.places) = (deck, coach, coachLook, cast, places)
    }

    public var body: some View {
        content
            .padding(.horizontal, Space.pageMargin)
            .padding(.top, Space.xs)
            .padding(.bottom, Space.m)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(role: .bgCanvas, in: theme))
            .navigationTitle(Text(verbatim: coach.name))
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button(action: places.market) { Image(systemName: "briefcase") }
                        .accessibilityLabel(Text(copy: "教练招聘会", bundle: .module))
                        .accessibilityIdentifier("coachDeck.market")
                    Button(action: places.resume) { Image(systemName: "doc.text") }
                        .accessibilityLabel(Text(copy: "简历", bundle: .module))
                        .accessibilityIdentifier("coachDeck.resume")
                    Button(action: places.earlier) {
                        Image(systemName: "clock").symbolEffect(.bounce, value: deck.putAway)
                    }
                    .accessibilityLabel(Text(copy: "以前", bundle: .module))
                    .accessibilityIdentifier("coachDeck.history")
                }
            }
            .pushedPage()
            // A swipe right on a card puts it away; going back is the edge swipe or the button.
            .backSwipeFromEdgeOnly()
            .haptic(.tick, trigger: deck.putAway)
            .task {
                await deck.reload()
                await nudge()
            }
    }

    /// Once a page opening, the top card leans right and springs back, as a swipe would start.
    private func nudge() async {
        guard !nudged, !reduceMotion, !deck.stack.isEmpty else { return }
        try? await Task.sleep(for: .seconds(DeckMetrics.nudgeDelay))
        guard !Task.isCancelled, !nudged, drag == .zero, flying == nil else { return }
        nudged = true
        withAnimation(.wildcard(Motion.sheet, reduceMotion: reduceMotion)) {
            drag = CGSize(width: DeckMetrics.nudge, height: 0)
        }
        try? await Task.sleep(for: .seconds(Motion.sheet.response))
        guard drag.width == DeckMetrics.nudge else { return }
        withAnimation(.wildcard(Motion.celebrate, reduceMotion: reduceMotion)) { drag = .zero }
    }

    @ViewBuilder private var content: some View {
        switch deck.load {
        case .loading where deck.stack.isEmpty:
            LoadingDots().frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed:
            StateView.offline(retryIdentifier: "coachDeck.retry") { Task { await deck.reload() } }
        default:
            stack
        }
    }

    /// 「还有 3 张」 or 「最后一张」, and 下一张, which puts the top card away as a swipe right does.
    private func pager(_ top: CoachPageCard, left: Int) -> some View {
        HStack(spacing: Space.s) {
            Group {
                if left > 0 {
                    Text(copy: "还有 \(left) 张", bundle: .module)
                } else {
                    Text(copy: "最后一张", bundle: .module)
                }
            }
            .typeStyle(TypeRamp.caption)
            .foregroundStyle(Color(role: .fgMuted, in: theme))
            .lineLimit(1)
            .contentTransition(.numericText())
            .animation(.wildcard(Motion.change, reduceMotion: reduceMotion), value: left)
            .accessibilityIdentifier("coachDeck.hint")
            Button {
                putAway(top)
            } label: {
                HStack(spacing: Space.xxs) {
                    Text(copy: "下一张", bundle: .module)
                    Image(systemName: "chevron.right").imageScale(.small).accessibilityHidden(true)
                }
            }
            .buttonStyle(SecondaryButtonStyle(.onInk, size: .compact))
            .overlay { Capsule().strokeBorder(Color(role: .borderDefault, in: theme), lineWidth: Sizing.hairline) }
            .disabled(flying != nil)
            .accessibilityIdentifier("coachDeck.next")
        }
        .frame(maxWidth: .infinity)
    }

    /// The top card over the next two, which peek out under it.
    private var stack: some View {
        GeometryReader { proxy in
            let shown = Array(deck.stack.prefix(3))
            // The stack at the top, its pager at the page's foot, just above the tab bar
            // (Tracy, 2026-11-21).
            VStack(spacing: 0) {
                ZStack(alignment: .top) {
                    ForEach(Array(shown.enumerated().reversed()), id: \.element.key) { depth, card in
                        let isTop = depth == 0
                        CoachDeckCard(
                            deck: deck, card: card, coach: card.coach, coachLook: card.look, cast: cast, places: places,
                            isTop: isTop, putAway: putAway, height: isTop ? nil : topHeight
                        )
                        // A tall card stops short of the pager under it, as it stopped at the stack's edge before.
                        .frame(
                            maxHeight: proxy.size.height - 2 * DeckMetrics.peek - Sizing.control - Space.m,
                            alignment: .top
                        )
                        .onGeometryChange(for: Double.self) {
                            $0.size.height
                        } action: { height in
                            if isTop { topHeight = height }
                        }
                        .padding(.horizontal, Double(depth) * DeckMetrics.peek)
                        .offset(y: Double(depth) * DeckMetrics.peek)
                        .offset(isTop ? drag : .zero)
                        .rotationEffect(.degrees(isTop ? drag.width / proxy.size.width * 8 : 0), anchor: .bottom)
                        .modifier(FlyIntoClock(isFlying: flying == card.key, size: proxy.size))
                        .allowsHitTesting(isTop)
                        .accessibilityHidden(!isTop)
                        .gesture(swipe(card, width: proxy.size.width), isEnabled: isTop)
                        .accessibilityAction(named: Text(copy: "收进以前", bundle: .module)) { putAway(card) }
                    }
                    if shown.isEmpty {
                        CoachDeckCard(
                            deck: deck, card: nil, coach: coach, coachLook: coachLook, cast: cast, places: places)
                    }
                }
                Spacer(minLength: DeckMetrics.peek * Double(max(shown.count - 1, 0)) + Space.m)
                if let top = shown.first {
                    pager(top, left: deck.stack.count - 1)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
        }
    }

    /// Right, far or fast enough, puts the card away; anything else springs it back.
    private func swipe(_ card: CoachPageCard, width: Double) -> some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                // Only to the right; the page leaves iOS only its back swipe from the edge.
                drag = CGSize(width: max(0, value.translation.width), height: value.translation.height * 0.2)
            }
            .onEnded { value in
                if value.translation.width > width * 0.28 || value.predictedEndTranslation.width > width * 0.6 {
                    putAway(card)
                } else {
                    withAnimation(.wildcard(Motion.sheet, reduceMotion: reduceMotion)) { drag = .zero }
                }
            }
    }

    /// The card flies up into the clock, then goes into 以前.
    private func putAway(_ card: CoachPageCard) {
        guard flying == nil else { return }
        withAnimation(.wildcard(Motion.page, reduceMotion: reduceMotion)) {
            flying = card.key
        } completion: {
            var instant = Transaction()
            instant.disablesAnimations = true
            withTransaction(instant) {
                flying = nil
                drag = .zero
            }
            withAnimation(.wildcard(Motion.sheet, reduceMotion: reduceMotion)) { deck.seen(card) }
        }
    }
}

/// A card on its way into 以前: up and right to the clock, shrinking to a speck.
private struct FlyIntoClock: ViewModifier {
    let isFlying: Bool
    let size: CGSize

    func body(content: Content) -> some View {
        content
            .scaleEffect(isFlying ? 0.05 : 1, anchor: .topTrailing)
            .offset(x: isFlying ? size.width * 0.05 : 0, y: isFlying ? -Space.xl * 2 : 0)
            .opacity(isFlying ? 0 : 1)
    }
}
#endif
