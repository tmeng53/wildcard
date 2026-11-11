#if os(iOS)
import CheckInDomain
import DesignSystem
import DesignSystemUI
import SwiftUI

/// A letter in its envelope over 今天, as the approved 教练交接信 (version 3) plays it: new, it
/// flies in sealed in the brand's graphite envelope, whose Wildcard seal pulses until tapped
/// (开封): the seal pops, the flap opens, the letter (`sheet`, given how much of its button
/// shows) slides out and up, the envelope drops away and the letter unfolds. Opened again, it
/// simply shows, and a tap around it puts it away too. The coach's 交接信 and the team's 感谢信
/// both open this way. Its parts' times are `LetterOpening`'s, on the home's clock; sizes are
/// the prototype's 300-point letter, scaled to the screen's width.
struct LetterEnvelope<Sheet: View>: View {
    @Environment(\.sceneTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let isSealed: Bool
    /// Where the envelope flies out of (global); nil flies it from low on the left.
    let from: CGPoint?
    let clock: () -> Date
    let putAway: () -> Void
    /// Whom it is to and from, on the envelope's pocket.
    let address: Text
    let sheet: (Double) -> Sheet
    @State private var opening: LetterOpening

    init(
        isSealed: Bool, shownAt: Date, from: CGPoint?, clock: @escaping () -> Date, putAway: @escaping () -> Void,
        address: Text, @ViewBuilder sheet: @escaping (Double) -> Sheet
    ) {
        (self.isSealed, self.from, self.clock, self.putAway) = (isSealed, from, clock, putAway)
        (self.address, self.sheet) = (address, sheet)
        _opening = State(initialValue: LetterOpening(shown: shownAt))
    }

    var body: some View {
        if isSealed {
            TimelineView(.animation(paused: reduceMotion || opening.isOpen(at: clock()))) { _ in
                let moment = reduceMotion ? Date.distantFuture : clock()
                ZStack {
                    Color(role: .bgBrand, in: theme).opacity(Scrim.dimOpacity * opening.scrim(at: moment))
                        .ignoresSafeArea()
                        .accessibilityHidden(true)
                    GeometryReader { proxy in
                        sealed(Frame(proxy, from: from), at: moment)
                    }
                }
            }
            .haptic(.unseal, trigger: opening.opened)
            // Over 今天 as a card popup is: VoiceOver stays on the envelope until it is opened.
            .accessibilityAddTraits(.isModal)
        } else {
            ZStack {
                Color(role: .bgBrand, in: theme).opacity(Scrim.dimOpacity)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture(perform: putAway)
                    .accessibilityHidden(true)
                GeometryReader { proxy in
                    let frame = Frame(proxy, from: nil)
                    sheet(1)
                        .frame(width: frame.width, height: frame.height)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.ticket, style: .continuous))
                        .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                }
            }
            // As a card popup: VoiceOver stays on the letter, and its scrub puts it away.
            .accessibilityAddTraits(.isModal)
            .accessibilityAction(.escape, putAway)
        }
    }

    /// The envelope and the letter coming out of it, at `moment`.
    private func sealed(_ frame: Frame, at moment: Date) -> some View {
        let flight = opening.flight(at: moment)
        let drop = opening.drop(at: moment) * frame.screen.height
        let (place, grow) = opening.unfold(at: moment)
        let rise = opening.rise(at: moment)
        let zoom = frame.scale
        let top = Tween.mix(
            Tween.mix(frame.envelopeTop + 18 * zoom, frame.envelopeTop - 150 * zoom, rise), frame.letterTop, place)
        let height = Tween.mix(300 * zoom, frame.height, grow)
        let flown = moment >= opening.shown
        // Once dropped off the screen the envelope is gone, so the popup's frame is the letter's.
        let envelope = opening.showsEnvelope(at: moment)
        return ZStack(alignment: .topLeading) {
            if envelope {
                EnvelopeBack(backFlap: opening.backFlap(at: moment))
                    .frame(width: frame.envelope.width, height: frame.envelope.height)
                    .modifier(Flying(frame: frame, flight: flight, drop: drop))
                    .opacity(flown ? 1 : 0)
            }
            if opening.showsLetter(at: moment) {
                sheet(opening.button(at: moment))
                    .frame(width: frame.width, height: frame.height)
                    .frame(width: frame.width, height: height, alignment: .top)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.ticket, style: .continuous))
                    .shadow(color: Color(role: .bgBrand, in: theme).opacity(0.25), radius: 15, y: 10)
                    .scaleEffect(Tween.mix(0.88, 1, place), anchor: .top)
                    .position(x: frame.screen.width / 2, y: top + height / 2)
                    .mask(alignment: .top) {
                        // In the envelope, the pocket hides what is below its foot.
                        Rectangle()
                            .frame(
                                height: opening.clipsLetter(at: moment)
                                    ? frame.envelopeTop + frame.envelope.height : frame.screen.height * 2)
                    }
            }
            if envelope {
                EnvelopeFront(
                    address: address, frontFlap: opening.frontFlap(at: moment),
                    // Under Reduce Motion the seal holds still.
                    seal: reduceMotion && opening.opened == nil ? (1, 1) : opening.seal(at: moment), scale: zoom
                )
                .frame(width: frame.envelope.width, height: frame.envelope.height)
                .modifier(Flying(frame: frame, flight: flight, drop: drop))
                .opacity(flown ? 1 : 0)
                .onTapGesture(perform: openSeal)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(copy: "开信", bundle: .module))
                .accessibilityAddTraits(.isButton)
                .accessibilityHidden(opening.opened != nil)
                .accessibilityIdentifier("today.letter.seal")
                .accessibilityAction { openSeal() }
            }
        }
        .frame(width: frame.screen.width, height: frame.screen.height, alignment: .topLeading)
    }

    /// 开封: the seal pops and the letter comes out. Under Reduce Motion the envelope was simply
    /// there, so it opens at once.
    private func openSeal() {
        let now = clock()
        opening.open(at: reduceMotion ? max(now, opening.shown.addingTimeInterval(LetterOpening.flight)) : now)
    }

    typealias Frame = LetterGeometry
}

/// Where everything goes on this screen: the prototype's 300-point letter at the screen's width
/// (`scale`), up to its 572 points tall where the screen has room, with the envelope a little
/// under the middle.
struct LetterGeometry {
    let screen: CGSize
    let scale: Double
    let width: Double
    let height: Double
    let envelope: CGSize
    let envelopeTop: Double
    let letterTop: Double
    /// The coach the envelope flies out of, from the envelope's own middle.
    let start: CGSize

    init(_ proxy: GeometryProxy, from: CGPoint?) {
        let width = min(proxy.size.width - 2 * Space.pageMargin, 340)
        let scale = width / 300
        let height = min(572, proxy.size.height - 2 * Space.l)
        let envelope = CGSize(width: 292 * scale, height: 184 * scale)
        let middle = proxy.size.height / 2
        let envelopeTop = middle + 42 * scale - envelope.height / 2
        let global = proxy.frame(in: .global)
        let start =
            from.map {
                CGSize(
                    width: $0.x - global.minX - proxy.size.width / 2,
                    height: $0.y - global.minY - (envelopeTop + envelope.height / 2))
            } ?? CGSize(width: -94 * scale, height: 40 * scale)
        (screen, self.width, self.scale, self.height) = (proxy.size, width, scale, height)
        (self.envelope, self.envelopeTop, letterTop, self.start) = (
            envelope, envelopeTop, middle - height / 2, start
        )
    }
}

/// The envelope's flight in from the coach, small, to its place, and its drop away once empty.
private struct Flying: ViewModifier {
    let frame: LetterGeometry
    let flight: Double
    let drop: Double

    func body(content: Content) -> some View {
        content
            .scaleEffect(Tween.mix(0.12, 1, flight))
            .position(
                x: frame.screen.width / 2 + Tween.mix(frame.start.width, 0, flight),
                y: frame.envelopeTop + frame.envelope.height / 2 + Tween.mix(frame.start.height, 0, flight) + drop)
    }
}

/// The envelope's inside and its flap once folded open above it, behind the letter.
private struct EnvelopeBack: View {
    @Environment(\.sceneTheme) private var theme
    let backFlap: Double?

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .fill(Color(role: .bgBrandLamp, in: theme))
                if let backFlap {
                    FlapShape()
                        .fill(Color(role: .bgBrandLamp, in: theme))
                        .frame(height: proxy.size.height * EnvelopeFront.flapDepth)
                        .rotation3DEffect(.degrees(backFlap), axis: (x: 1, y: 0, z: 0), anchor: .top, perspective: 0.4)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// The envelope's pocket, folded up over the letter, with whom it is to and from, the flap
/// sealed shut over it, and the seal.
private struct EnvelopeFront: View {
    @Environment(\.sceneTheme) private var theme
    let address: Text
    let frontFlap: Double?
    let seal: (scale: Double, opacity: Double)
    let scale: Double

    /// How far down the flap reaches, and where the pocket's fold meets in the middle.
    static let flapDepth = 0.62
    private static let pocketFold = 0.56
    private static let seal: Double = 46
    private static let sealMark: Double = 34
    private static let sealRing: Double = 2

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack(alignment: .topLeading) {
                PocketShape(fold: Self.pocketFold)
                    .fill(Color(role: .bgBrand, in: theme))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                Path { path in
                    path.move(to: CGPoint(x: 1, y: size.height - 1))
                    path.addLine(to: CGPoint(x: size.width / 2, y: size.height * 103 / 184))
                    path.addLine(to: CGPoint(x: size.width - 1, y: size.height - 1))
                }
                .stroke(Color(role: .bgBrandLamp, in: theme), lineWidth: Sizing.selectionStroke)
                address
                    .typeStyle(TypeRamp.footnoteEmphasis)
                    .foregroundStyle(Color(role: .fgOnBrand, in: theme).opacity(0.9))
                    .lineLimit(1)
                    .padding(.leading, Space.m + Space.xxs / 2)
                    .padding(.bottom, Space.s + Space.xxs / 2)
                    .frame(width: size.width, height: size.height, alignment: .bottomLeading)
                if let frontFlap {
                    FlapShape()
                        .fill(Color(role: .bgBrandStub, in: theme))
                        .frame(width: size.width, height: size.height * Self.flapDepth)
                        .rotation3DEffect(.degrees(frontFlap), axis: (x: 1, y: 0, z: 0), anchor: .top, perspective: 0.4)
                }
                Circle()
                    .fill(Color(role: .bgBrand, in: theme))
                    .overlay(Circle().strokeBorder(Color(role: .fgBrandStamp, in: theme), lineWidth: Self.sealRing))
                    .overlay {
                        TicketLogo(on: .bgBrand, ink: .bgBrandPage)
                            .frame(width: Self.sealMark * scale, height: Self.sealMark * scale)
                    }
                    .frame(width: Self.seal * scale, height: Self.seal * scale)
                    .scaleEffect(seal.scale)
                    .opacity(seal.opacity)
                    .position(x: size.width / 2, y: size.height * Self.flapDepth - 7 * scale)
            }
        }
    }
}
#endif
