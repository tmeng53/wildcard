#if os(iOS)
import Contracts
import DesignSystem
import DesignSystemUI
import SquadDomain
import SwiftUI

/// The coach's page (the approved deck, 2026-11-08), pushed from a tap on the coach on 今天: what
/// the coach has for the member that they haven't seen, a stack of cards, one thing each, oldest
/// on top. Swiped right, a card flies into 以前 (the clock, top right, which gives a nudge; no
/// count); nothing turns by itself. Top right, from the left: 招聘会, 简历, 以前. Once all are seen,
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
                        .accessibilityLabel(Text("教练招聘会", bundle: .module))
                        .accessibilityIdentifier("coachDeck.market")
                    Button(action: places.resume) { Image(systemName: "doc.text") }
                        .accessibilityLabel(Text("简历", bundle: .module))
                        .accessibilityIdentifier("coachDeck.resume")
                    Button(action: places.earlier) {
                        Image(systemName: "clock").symbolEffect(.bounce, value: deck.putAway)
                    }
                    .accessibilityLabel(Text("以前", bundle: .module))
                    .accessibilityIdentifier("coachDeck.history")
                }
            }
            .pushedPage()
            .haptic(.tick, trigger: deck.putAway)
            .task { await deck.reload() }
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

    /// The top card over the next two, which peek out under it.
    private var stack: some View {
        GeometryReader { proxy in
            let shown = Array(deck.stack.prefix(3))
            ZStack(alignment: .top) {
                ForEach(Array(shown.enumerated().reversed()), id: \.element.key) { depth, card in
                    let isTop = depth == 0
                    CoachDeckCard(
                        deck: deck, card: card, coach: card.coach, coachLook: card.look, cast: cast, places: places,
                        isTop: isTop
                    )
                    .padding(.horizontal, Double(depth) * DeckMetrics.peek)
                    .offset(y: Double(depth) * DeckMetrics.peek)
                    .offset(isTop ? drag : .zero)
                    .rotationEffect(.degrees(isTop ? drag.width / proxy.size.width * 8 : 0), anchor: .bottom)
                    .modifier(FlyIntoClock(isFlying: flying == card.key, size: proxy.size))
                    .allowsHitTesting(isTop)
                    .accessibilityHidden(!isTop)
                    .gesture(swipe(card, width: proxy.size.width), isEnabled: isTop)
                    .accessibilityAction(named: Text("收进以前", bundle: .module)) { putAway(card) }
                }
                if shown.isEmpty {
                    CoachDeckCard(
                        deck: deck, card: nil, coach: coach, coachLook: coachLook, cast: cast, places: places)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height - 2 * DeckMetrics.peek, alignment: .top)
        }
    }

    /// Right, far or fast enough, puts the card away; anything else springs it back.
    private func swipe(_ card: CoachPageCard, width: Double) -> some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                // Only to the right: left is the system's back swipe from the edge, and nothing else.
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
