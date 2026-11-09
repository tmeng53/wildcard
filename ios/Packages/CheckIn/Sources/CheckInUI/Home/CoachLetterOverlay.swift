#if os(iOS)
import AvatarArt
import AvatarDomain
import AvatarUI
import CheckInDomain
import Contracts
import DesignSystem
import DesignSystemUI
import SwiftUI
import UIKit

/// The coach's letter (交接信) opened, as the approved 教练交接信 (version 3) draws it: on white, the
/// Wildcard tickets and the date at its head over a hairline, whom it is to, its lines on ruled
/// paper, the 落款 (the coach's head and name), and 收下. Over 今天, and from the coach's 简历.
public struct CoachLetterSheet: View {
    @Environment(\.sceneTheme) private var theme
    let letter: CoachLetter
    /// How much 收下 shows, 0 to 1, while the letter unfolds.
    var button: Double = 1
    let putAway: () -> Void
    @State private var head: CharacterPlayer?
    /// The room the letter's lines have; a letter longer than it scrolls (a long one at large type).
    @State private var room: CGFloat = 0

    public init(letter: CoachLetter, putAway: @escaping () -> Void) {
        self.letter = letter
        self.putAway = putAway
    }

    init(letter: CoachLetter, button: Double, putAway: @escaping () -> Void) {
        self.letter = letter
        self.button = button
        self.putAway = putAway
    }

    /// The letterhead's tickets, and the 落款's head.
    private static let mark: Double = 28
    private static let face: Double = 34
    /// The sheet's padding at its sides and top: the prototype's 20 points.
    private static let inset = Space.m + Space.xxs

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                TicketLogo(on: .bgCanvas, ink: .bgBrand)
                    .frame(width: Self.mark, height: Self.mark)
                Spacer()
                Text(verbatim: letter.day.description.replacingOccurrences(of: "-", with: "."))
                    .typeStyle(TypeRamp.ticketDate)
                    .foregroundStyle(Color(role: .fgMuted, in: theme))
            }
            .padding(.bottom, Space.s)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Color(role: .borderDefault, in: theme)).frame(height: Sizing.hairline)
            }
            Text("各位和\(letter.recipient.name)：", bundle: .module)
                .typeStyle(TypeRamp.headline)
                .foregroundStyle(Color(role: .fgDefault, in: theme))
                .padding(.top, Space.s)
                .padding(.bottom, Space.xs)
            ScrollView {
                RuledLines(lines: letter.lines, minHeight: room)
                    .accessibilityIdentifier("today.letter.text")
            }
            .scrollBounceBehavior(.basedOnSize)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.height
            } action: {
                room = $0
            }
            HStack(spacing: Space.xs) {
                Spacer()
                MemberHead(player: head, size: Self.face, figure: .coach)
                    .accessibilityHidden(true)
                Text(verbatim: letter.from.name)
                    .typeStyle(TypeRamp.calloutEmphasis)
                    .foregroundStyle(Color(role: .fgDefault, in: theme))
            }
            .padding(.top, Space.xs)
            Button(action: putAway) {
                Text("收下", bundle: .module).frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle(.regular))
            .accentTone(.brand)
            .padding(.top, Space.s)
            .opacity(button)
            .allowsHitTesting(button > 0.5)
            .accessibilityHidden(button < 0.5)
            .accessibilityIdentifier("today.letter.putAway")
        }
        .padding([.horizontal, .top], Self.inset)
        .padding(.bottom, Space.m)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(role: .bgCanvas, in: theme))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("today.letter")
        .task(id: letter.from.id) {
            let id = letter.from.id.rawValue
            guard CoachCharacter.exists(id) else { return }
            head = try? CharacterPlayer(figure: CoachCharacter.figure(id), idle: CoachCharacter.clip(.idle, coach: id))
        }
    }
}

/// The letter's lines on ruled paper: a rule under every line of text, as the prototype's 1.6
/// line height draws them, on down to the sheet's foot.
private struct RuledLines: View {
    @Environment(\.sceneTheme) private var theme
    let lines: [String]
    /// The rules run on down to here at least: the sheet's foot.
    let minHeight: CGFloat
    /// One line of text and the room around it: 1.6 times the body's 15 points.
    @ScaledMetric(relativeTo: .callout) private var rule = 24.0

    var body: some View {
        let style = TypeRamp.callout
        let font = UIFontMetrics(forTextStyle: .callout).scaledFont(
            for: UIFont(name: style.face.postScriptName, size: style.size) ?? .systemFont(ofSize: style.size))
        let leading = max(0, rule - font.lineHeight)
        Text(verbatim: lines.joined(separator: "\n"))
            .typeStyle(style)
            .lineSpacing(leading)
            .foregroundStyle(Color(role: .fgDefault, in: theme))
            .padding(.top, leading / 2)
            .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .topLeading)
            .background {
                Canvas { context, size in
                    var line = rule
                    while line <= size.height {
                        context.fill(
                            Path(CGRect(x: 0, y: line - Sizing.hairline, width: size.width, height: Sizing.hairline)),
                            with: .color(Color(role: .borderDefault, in: theme)))
                        line += rule
                    }
                }
            }
    }
}

/// A letter over 今天 (the approved 教练交接信, version 3). New on this phone, it flies in sealed in
/// the brand's graphite envelope from the coach, whose Wildcard seal pulses until tapped (开封):
/// the seal pops, the flap opens, the letter slides out and up, the envelope drops away and the
/// letter unfolds, with 收下 under it. Opened again, it simply shows, and a tap around it puts it
/// away too. Its parts' times are `LetterOpening`'s, on the home's clock; sizes are the
/// prototype's 300-point letter, scaled to the screen's width.
struct CoachLetterOverlay: View {
    @Environment(\.sceneTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let shown: ShownLetter
    /// Where the coach stands on screen (global), which the envelope flies out of; nil flies it
    /// from the prototype's place, low on the left.
    let from: CGPoint?
    let clock: () -> Date
    let putAway: () -> Void
    @State private var opening: LetterOpening

    init(shown: ShownLetter, shownAt: Date, from: CGPoint?, clock: @escaping () -> Date, putAway: @escaping () -> Void)
    {
        self.shown = shown
        self.from = from
        self.clock = clock
        self.putAway = putAway
        _opening = State(initialValue: LetterOpening(shown: shownAt))
    }

    var body: some View {
        if shown.isSealed {
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
                    CoachLetterSheet(letter: shown.letter, putAway: putAway)
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
                CoachLetterSheet(letter: shown.letter, button: opening.button(at: moment), putAway: putAway)
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
                    letter: shown.letter, frontFlap: opening.frontFlap(at: moment),
                    // Under Reduce Motion the seal holds still.
                    seal: reduceMotion && opening.opened == nil ? (1, 1) : opening.seal(at: moment), scale: zoom
                )
                .frame(width: frame.envelope.width, height: frame.envelope.height)
                .modifier(Flying(frame: frame, flight: flight, drop: drop))
                .opacity(flown ? 1 : 0)
                .onTapGesture(perform: openSeal)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("开信", bundle: .module))
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

    /// Where everything goes on this screen: the prototype's 300-point letter at the screen's
    /// width (`scale`), up to its 572 points tall where the screen has room, with the envelope a
    /// little under the middle.
    struct Frame {
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
}

/// The envelope's flight in from the coach, small, to its place, and its drop away once empty.
private struct Flying: ViewModifier {
    let frame: CoachLetterOverlay.Frame
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
    let letter: CoachLetter
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
                Text("给小队和 \(letter.recipient.name) · \(letter.from.name)", bundle: .module)
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
