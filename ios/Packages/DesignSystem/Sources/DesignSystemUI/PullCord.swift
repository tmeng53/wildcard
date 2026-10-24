#if canImport(SwiftUI)
import DesignSystem
import SwiftUI

// swiftlint:disable identifier_name - x and y are the names CGPoint and CGRect use.

/// The light switch at night (开灯, the approved prototype of 2026-10-24): a ball chain hanging
/// from the top of its frame with a little bulb-shaped pull at its end, white when the lights are
/// off and warm when they are on. Drag it down and it follows with resistance (`PullCordMotion`),
/// clicking at 24 points, which calls `action` once; let go and it springs back and swings. A tap
/// pulls it by itself. The caller hangs it under what it belongs to and plays the haptic. For
/// VoiceOver it is a button named by `label` (开灯 or 关灯).
public struct PullCord: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The frame: as wide as a tap target, and tall enough for the chain pulled all the way down.
    public static let size = CGSize(width: 44, height: PullCordMotion.length + bulbHeight + PullCordMotion.maxPull)
    /// The cap, screw base and bulb under the chain.
    private static let bulbHeight = 26.0
    /// The cap's own corners.
    private static let capCorner = 1.5
    /// Where a finger can take hold: around the bulb, at least 44 by 44.
    private static let grip = CGRect(x: 0, y: 36, width: 44, height: 66)

    private let label: Text
    private let isOn: Bool
    private let action: () -> Void

    @State private var drag: Drag?
    @State private var tapStart: Date?
    @State private var release: Release?

    private struct Drag {
        var pull = 0.0
        var clicked = false
        var moved = false
    }

    private struct Release: Equatable {
        let from: Double
        let at: Date
    }

    public init(_ label: Text, isOn: Bool, action: @escaping () -> Void) {
        self.label = label
        self.isOn = isOn
        self.action = action
    }

    public var body: some View {
        let moving = drag != nil || tapStart != nil || release != nil
        TimelineView(.animation(minimumInterval: nil, paused: !moving)) { timeline in
            let (pull, degrees) = state(at: timeline.date)
            Canvas { context, size in
                context.translateBy(x: size.width / 2, y: 0)
                Self.draw(length: PullCordMotion.length + pull, isOn: isOn, in: &context)
            }
            .frame(width: Self.size.width, height: Self.size.height)
            .rotationEffect(.degrees(degrees), anchor: .top)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .contentShape(Grip())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in dragged(value) }
                .onEnded { _ in letGo() }
        )
        .task(id: tapStart) {
            guard let tapStart else { return }
            try? await Task.sleep(for: .seconds(PullCordMotion.tapDuration))
            guard !Task.isCancelled else { return }
            action()
            release = Release(from: PullCordMotion.tapPull, at: tapStart.addingTimeInterval(PullCordMotion.tapDuration))
            self.tapStart = nil
        }
        .task(id: release) {
            guard release != nil else { return }
            try? await Task.sleep(for: .seconds(PullCordMotion.releaseDuration))
            guard !Task.isCancelled else { return }
            release = nil
        }
        .accessibilityElement()
        .accessibilityLabel(label)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { pullByItself() }
    }

    /// How far down the cord is and how far it swings at `date`.
    private func state(at date: Date) -> (pull: Double, degrees: Double) {
        if let drag { return (drag.pull, 0) }
        if let tapStart { return (PullCordMotion.tap(at: date.timeIntervalSince(tapStart)), 0) }
        if let release {
            let moved = PullCordMotion.release(
                from: release.from, at: date.timeIntervalSince(release.at), swings: !reduceMotion)
            return (moved.offset, moved.degrees)
        }
        return (0, 0)
    }

    private func dragged(_ value: DragGesture.Value) {
        guard tapStart == nil else { return }
        var current = drag ?? Drag()
        release = nil
        let travel = max(abs(value.translation.height), abs(value.translation.width))
        if travel > PullCordMotion.tapSlop { current.moved = true }
        current.pull = PullCordMotion.pull(dragged: value.translation.height)
        if !current.clicked, current.pull >= PullCordMotion.clickPull {
            current.clicked = true
            action()
        }
        drag = current
    }

    private func letGo() {
        guard let current = drag else { return }
        drag = nil
        if current.moved {
            release = Release(from: current.pull, at: .now)
        } else {
            pullByItself()
        }
    }

    /// A tap: the cord pulls down by itself, clicks, and springs back.
    private func pullByItself() {
        guard tapStart == nil, drag == nil else { return }
        release = nil
        tapStart = .now
    }

    /// The chain from (0, 0) down to `length`, then the cap, the screw base and the bulb, in the
    /// prototype's points.
    private static func draw(length: Double, isOn: Bool, in context: inout GraphicsContext) {
        let chain = Color(Palette.cordChain)
        var bead = 2.0
        while bead < length - 1 {
            context.fill(Path(ellipseIn: CGRect(x: -1.5, y: bead - 1.5, width: 3, height: 3)), with: .color(chain))
            bead += 4.4
        }
        let y = length
        context.fill(
            Path(roundedRect: CGRect(x: -4, y: y, width: 8, height: 5), cornerRadius: Self.capCorner),
            with: .color(Color(Palette.cordCap)))
        for ring in [y + 4, y + 7] {
            context.fill(Path(CGRect(x: -5, y: ring, width: 10, height: 2)), with: .color(Color(Palette.cordScrew)))
        }
        // The bulb: a neck flaring out from the screw base into a round bottom, 8 points across.
        let centre = y + 17.5
        let round = 8 * 0.552_284_75
        var bulb = Path()
        bulb.move(to: CGPoint(x: -5, y: y + 9))
        bulb.addCurve(
            to: CGPoint(x: -8, y: centre), control1: CGPoint(x: -5, y: y + 12), control2: CGPoint(x: -8, y: y + 13))
        bulb.addCurve(
            to: CGPoint(x: 0, y: centre + 8), control1: CGPoint(x: -8, y: centre + round),
            control2: CGPoint(x: -round, y: centre + 8))
        bulb.addCurve(
            to: CGPoint(x: 8, y: centre), control1: CGPoint(x: round, y: centre + 8),
            control2: CGPoint(x: 8, y: centre + round))
        bulb.addCurve(
            to: CGPoint(x: 5, y: y + 9), control1: CGPoint(x: 8, y: y + 13), control2: CGPoint(x: 5, y: y + 12))
        bulb.closeSubpath()
        context.fill(bulb, with: .color(Color(isOn ? Palette.bulbLit : Palette.white)))
        context.stroke(bulb, with: .color(Color(isOn ? Palette.bulbLitLine : Palette.cordChain)), lineWidth: 1.4)
        var filament = Path()
        filament.move(to: CGPoint(x: -2.5, y: y + 17))
        filament.addLine(to: CGPoint(x: -0.8, y: y + 14.6))
        filament.addLine(to: CGPoint(x: 0.8, y: y + 17))
        filament.addLine(to: CGPoint(x: 2.4, y: y + 14.6))
        context.stroke(
            filament, with: .color(Color(isOn ? Palette.bulbFilament : Palette.cordChain)),
            style: StrokeStyle(lineWidth: 1.1, lineCap: .round, lineJoin: .round))
    }

    /// Only the bulb and the chain just above it take a touch, so the rest of the frame doesn't
    /// cover what is under it.
    private struct Grip: Shape {
        func path(in rect: CGRect) -> Path {
            Path(PullCord.grip)
        }
    }
}

// swiftlint:enable identifier_name
#endif
