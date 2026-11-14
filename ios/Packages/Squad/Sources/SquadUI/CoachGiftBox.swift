#if os(iOS)
import DesignSystem
import DesignSystemUI
import SwiftUI

/// A gift's box, as the approved deck draws it: it pops out of the coach's hand with its dot;
/// 拆开 throws its lid off and the gift floats up out of it; 立刻穿上 flies the gift onto the
/// member as the box goes, and 一会儿再说 shrinks it back in and puts the lid back on.
struct GiftBox: View {
    let moment: GiftMoment
    let picture: AnyView?
    let size: Double
    @State private var popped = false
    @State private var bob = false
    /// The gift reached the member or the box, and fades.
    @State private var landed = false
    @Environment(\.sceneTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            BoxBody(ink: ink, ribbon: ribbon)
                .frame(width: size, height: size)
                .opacity(moment == .worn ? 0 : 1)
                .overlay(alignment: .topTrailing) {
                    if moment == .boxed {
                        Circle()
                            .fill(ink)
                            .overlay { Circle().strokeBorder(ribbon, lineWidth: 2) }
                            .frame(width: size * 0.3, height: size * 0.3)
                            .offset(x: -size * 0.04, y: size * 0.12)
                    }
                }
            BoxLid(ink: ink, ribbon: ribbon)
                .frame(width: size, height: size)
                .rotationEffect(.degrees(lidOpen ? 60 : 0))
                .offset(x: lidOpen ? size * 0.31 : 0, y: lidOpen ? -size * 1.38 : 0)
                .opacity(lidOpen ? 0 : 1)
            if let picture, moment != .boxed {
                picture
                    .frame(width: size, height: size)
                    .scaleEffect(giftScale)
                    .offset(giftOffset)
                    .opacity(landed ? 0 : 1)
            }
        }
        .scaleEffect(popped || reduceMotion ? 1 : 0.15, anchor: .bottom)
        .offset(x: popped || reduceMotion ? 0 : -size * 0.8, y: popped || reduceMotion ? 0 : size * 0.7)
        .animation(.wildcard(Motion.celebrate, reduceMotion: reduceMotion), value: moment)
        .onAppear {
            landed = moment == .worn || moment == .stowed
            withAnimation(.wildcard(Motion.celebrate, reduceMotion: reduceMotion)) { popped = true }
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: StageTiming.bob).repeatForever(autoreverses: true)) { bob = true }
        }
        .onChange(of: moment) { _, now in
            guard now == .worn || now == .stowed else { return }
            // Once there, it fades into the member or the box.
            Task {
                try? await Task.sleep(for: .seconds(reduceMotion ? 0 : StageTiming.landing))
                withAnimation(.wildcard(Motion.change, reduceMotion: reduceMotion)) { landed = true }
            }
        }
    }

    private var ink: Color { Color(role: .bgInk, in: theme) }
    private var ribbon: Color { Color(role: .bgCanvas, in: theme) }
    /// The lid is off from 拆开 until the gift is back in the box.
    private var lidOpen: Bool { moment == .floating || moment == .worn }

    private var giftScale: Double {
        switch moment {
        case .boxed: 0.2
        case .floating: 1.7
        case .worn: 0.9
        case .stowed: 0.3
        }
    }

    private var giftOffset: CGSize {
        switch moment {
        case .boxed: CGSize(width: 0, height: size * 0.17)
        case .floating: CGSize(width: 0, height: -size * 2.07 + (bob ? -size * 0.08 : size * 0.08))
        case .worn: CGSize(width: size * 1.48, height: -size)
        case .stowed: CGSize(width: 0, height: size * 0.14)
        }
    }
}

/// The box's body, with its ribbon: the deck's drawing on a 40-point square.
private struct BoxBody: View {
    let ink: Color
    let ribbon: Color

    var body: some View {
        Canvas { context, size in
            let unit = size.width / 40
            let corner = 3 * unit
            context.fill(
                Path(
                    roundedRect: CGRect(x: 6 * unit, y: 16 * unit, width: 28 * unit, height: 20 * unit),
                    cornerRadius: corner),
                with: .color(ink))
            context.fill(
                Path(CGRect(x: 18 * unit, y: 16 * unit, width: 4 * unit, height: 20 * unit)), with: .color(ribbon))
        }
    }
}

/// The box's lid with its bow, which comes off on 拆开.
private struct BoxLid: View {
    let ink: Color
    let ribbon: Color

    var body: some View {
        Canvas { context, size in
            let unit = size.width / 40
            let corner = 2 * unit
            context.fill(
                Path(
                    roundedRect: CGRect(x: 4 * unit, y: 10 * unit, width: 32 * unit, height: 8 * unit),
                    cornerRadius: corner),
                with: .color(ink))
            context.fill(
                Path(CGRect(x: 18 * unit, y: 10 * unit, width: 4 * unit, height: 8 * unit)), with: .color(ribbon))
            var bow = Path()
            for side in [-1.0, 1.0] {
                bow.move(to: CGPoint(x: 20 * unit, y: 10 * unit))
                bow.addCurve(
                    to: CGPoint(x: (20 + side * 10) * unit, y: 7 * unit),
                    control1: CGPoint(x: (20 + side * 4) * unit, y: 3 * unit),
                    control2: CGPoint(x: (20 + side * 11) * unit, y: 3 * unit))
                bow.addCurve(
                    to: CGPoint(x: 20 * unit, y: 10 * unit),
                    control1: CGPoint(x: (20 + side * 9.4) * unit, y: 9 * unit),
                    control2: CGPoint(x: (20 + side * 5) * unit, y: 10 * unit))
            }
            context.fill(bow, with: .color(ribbon))
            context.stroke(bow, with: .color(ink), lineWidth: 1.5 * unit)
        }
    }
}
#endif
