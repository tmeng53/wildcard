#if canImport(SwiftUI)
import DesignSystem
import DesignSystemUI
import ScenePickDomain
import SwiftUI

/// The reveal after 「就它了」, over the page it was picked on: it draws `Unboxing`'s frames,
/// scaled from the design's 390-point width to the screen. `page` is what it plays over (the
/// 战报's last page), so the carton's landing can shake it; `backdrop` is the picked scene as
/// home draws it, filling the screen, which the card shows cropped as it rises. Once the card
/// covers the screen it calls `onCovered`, and the home takes over under the last of the
/// confetti; `onFinished` comes when nothing is left to draw. One haptic, as the flaps fly.
/// With Reduce Motion it fades straight to the covered moment.
public struct UnboxRevealView<Page: View, Backdrop: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var burst = false
    private let unboxing: Unboxing
    private let scene: SceneTheme
    private let startedAt: Date
    private let frozenAt: Double?
    private let onCovered: () -> Void
    private let onFinished: (_ coveredAt: Date) -> Void
    private let page: Page
    private let backdrop: Backdrop

    /// `frozenAt` holds the reveal on one moment, for screenshots and previews.
    public init(
        _ unboxing: Unboxing, scene: SceneTheme, startedAt: Date, frozenAt: Double? = nil,
        onCovered: @escaping () -> Void = {}, onFinished: @escaping (_ coveredAt: Date) -> Void = { _ in },
        @ViewBuilder page: () -> Page, @ViewBuilder backdrop: () -> Backdrop
    ) {
        self.unboxing = unboxing
        self.scene = scene
        self.startedAt = startedAt
        self.frozenAt = frozenAt
        self.onCovered = onCovered
        self.onFinished = onFinished
        self.page = page()
        self.backdrop = backdrop()
    }

    public var body: some View {
        GeometryReader { geometry in
            TimelineView(.animation(minimumInterval: nil, paused: frozenAt != nil)) { timeline in
                UnboxStage(
                    frame: unboxing.frame(at: frozenAt ?? clock(at: timeline.date)), scene: scene,
                    size: geometry.size, page: page, backdrop: backdrop)
            }
        }
        .ignoresSafeArea()
        .haptic(.unbox, trigger: burst) { _, burst in burst }
        .task {
            guard frozenAt == nil else { return }
            if unboxing.boxed, !reduceMotion { await wait(until: Unboxing.flapsOpen) { burst = true } }
            await wait(until: shown(unboxing.covered)) { onCovered() }
            // Reduce Motion holds the covered moment, so it ends there rather than on still confetti.
            // The home's drop counts from the covered screen, not from here.
            await wait(until: shown(reduceMotion ? unboxing.covered : unboxing.finished)) {
                onFinished(startedAt.addingTimeInterval(shown(unboxing.covered)))
            }
        }
        .accessibilityHidden(true)
    }

    /// The reveal's clock: the time since 「就它了」, or with Reduce Motion the page, then the
    /// scene filling the screen.
    private func clock(at date: Date) -> Double {
        let elapsed = date.timeIntervalSince(startedAt)
        guard reduceMotion else { return elapsed }
        return elapsed < Motion.reducedDuration ? 0 : unboxing.covered
    }

    /// When a moment of the reveal comes on screen: with Reduce Motion, everything up to the
    /// covered screen comes after one short fade.
    private func shown(_ moment: Double) -> Double {
        reduceMotion ? Motion.reducedDuration + max(0, moment - unboxing.covered) : moment
    }

    private func wait(until moment: Double, then act: () -> Void) async {
        let remaining = moment - Date.now.timeIntervalSince(startedAt)
        if remaining > 0 { try? await Task.sleep(for: .seconds(remaining)) }
        guard !Task.isCancelled else { return }
        act()
    }
}

/// One frame on screen, back to front as the prototype stacks it: the page, the dim, the card,
/// the ring, the carton, then dust and confetti; all of it jolted by the landing.
struct UnboxStage<Page: View, Backdrop: View>: View {
    let frame: UnboxFrame
    let scene: SceneTheme
    let size: CGSize
    let page: Page
    let backdrop: Backdrop

    var body: some View {
        let unit = size.width / Unboxing.stage.width
        ZStack(alignment: .topLeading) {
            page
                .frame(width: size.width, height: size.height)
            Color(Reveal.dim).opacity(frame.dim)
            if let card = frame.card { cardView(card, unit: unit) }
            if let ring = frame.ring {
                Circle()
                    .inset(by: ring.lineWidth * unit / 2)
                    .stroke(Color(role: .ring, in: scene), lineWidth: ring.lineWidth * unit)
                    .frame(width: ring.diameter * unit, height: ring.diameter * unit)
                    .position(x: ring.center.x * unit, y: ring.center.y * unit)
                    .opacity(ring.opacity)
            }
            if let carton = frame.carton { cartonView(carton, unit: unit) }
            ForEach(Array(frame.dust.enumerated()), id: \.offset) { _, puff in
                Circle()
                    .fill(Color(role: .bgCanvas, in: scene))
                    .frame(width: puff.diameter * unit, height: puff.diameter * unit)
                    .position(x: puff.center.x * unit, y: puff.center.y * unit)
                    .opacity(puff.opacity)
            }
            ForEach(frame.confetti, id: \.index) { piece in
                RoundedRectangle(cornerRadius: piece.cornerRadius * unit)
                    .fill(color(of: piece.color))
                    .frame(width: piece.size.width * unit, height: piece.size.height * unit)
                    .rotationEffect(.degrees(piece.rotation))
                    .position(
                        x: (piece.origin.x + piece.size.width / 2) * unit,
                        y: (piece.origin.y + piece.size.height / 2) * unit
                    )
                    .opacity(piece.opacity)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .offset(x: frame.shake.x * unit, y: frame.shake.y * unit)
    }

    /// The card shows the backdrop as CSS's `object-fit: cover` would: laid out at the screen's
    /// size, scaled to fill the card and cropped about its middle. Full, it is the screen exactly,
    /// whatever the phone's height.
    private func cardView(_ card: CardPose, unit: Double) -> some View {
        let stage = Unboxing.stage
        let rect =
            card.frame == Rect(x: 0, y: 0, width: stage.width, height: stage.height)
            ? CGRect(origin: .zero, size: size)
            : CGRect(
                x: card.frame.x * unit, y: card.frame.y * unit, width: card.frame.width * unit,
                height: card.frame.height * unit)
        let cover = max(rect.width / size.width, rect.height / size.height)
        let shape = RoundedRectangle(cornerRadius: card.cornerRadius * unit, style: .circular)
        return
            backdrop
            .frame(width: size.width, height: size.height)
            .scaleEffect(cover)
            .frame(width: rect.width, height: rect.height)
            .clipShape(shape)
            .background {
                RoundedRectangle(cornerRadius: (card.cornerRadius + card.border) * unit, style: .circular)
                    .fill(Color(role: .bgCanvas, in: scene))
                    .padding(-card.border * unit)
            }
            .scaleEffect(card.scale)
            .rotationEffect(.degrees(card.rotation))
            .opacity(card.opacity)
            .position(x: rect.midX, y: rect.midY)
    }

    /// The carton moves and squashes about the middle of its base, (195, 520) on the stage.
    private func cartonView(_ carton: CartonPose, unit: Double) -> some View {
        let box = CartonPose.frame
        return CartonBox(
            leftFlap: CartonBox.Flap(x: carton.leftFlap.x, y: carton.leftFlap.y, degrees: carton.leftFlap.rotation),
            rightFlap: CartonBox.Flap(x: carton.rightFlap.x, y: carton.rightFlap.y, degrees: carton.rightFlap.rotation),
            flapOpacity: carton.flapOpacity
        )
        .scaleEffect(x: carton.scaleX, y: carton.scaleY, anchor: .bottom)
        .rotationEffect(.degrees(carton.rotation), anchor: .bottom)
        .offset(y: carton.offsetY)
        .opacity(carton.opacity)
        .scaleEffect(unit, anchor: .topLeading)
        .frame(width: box.width * unit, height: box.height * unit, alignment: .topLeading)
        .position(x: (box.x + box.width / 2) * unit, y: (box.y + box.height / 2) * unit)
    }

    private func color(of confetti: ConfettiColor) -> Color {
        switch confetti {
        case .signature(let other): Color(role: .bgAccent, in: other)
        case .white: Color(role: .bgCanvas, in: scene)
        case .kraft: Color(Reveal.kraft)
        case .picked: Color(role: .bgAccent, in: scene)
        }
    }
}
#endif
