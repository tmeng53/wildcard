#if canImport(SwiftUI)
import AvatarDomain
import DesignSystem
import DesignSystemUI
import SwiftUI

/// The pop-up the editor opens with when pieces came in (approved 2026-11-04): their kraft
/// cartons, each with a 「？」, and which store they came to, never what they are. 一键全开 opens
/// every box at once (they shake, the flaps fly off and each piece pops out), then the shopping
/// street shows with each new piece wearing NEW; nothing is put on. 先不了 leaves the boxes on
/// their racks. With reduced motion the pieces just fade in.
struct ArrivalPopup: View {
    let model: CharacterEditorModel
    let arrival: CharacterEditorModel.Arrival
    @Environment(\.sceneTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var step = Step.closed

    enum Step: Comparable {
        case closed, shaking, open, revealed
    }

    /// The most cartons that stand in a row; the rest wait behind them, out of sight.
    private let shown = 3
    /// The cartons' size, a share of the art's 170 × 190.
    private var scale: Double { arrival.pieces.count == 1 ? 0.62 : 0.44 }
    /// How long the cartons shake before the flaps go, as the prototype has it.
    private let shake = 0.52
    /// How long the pieces stay up before the street shows.
    private let hold = 0.9

    var body: some View {
        ZStack {
            // A veil over the editor, so the pop-up is the one thing to answer.
            Color(role: .bgInk, in: theme).opacity(0.4)
                .ignoresSafeArea()
                .accessibilityHidden(true)
            VStack(spacing: Space.m) {
                HStack(spacing: Space.xs) {
                    ForEach(Array(arrival.pieces.prefix(shown)), id: \.self) { piece in
                        Box(model: model, piece: piece, step: step, scale: scale, reduceMotion: reduceMotion)
                    }
                }
                .padding(.top, Space.l)
                VStack(spacing: Space.xxs) {
                    title
                        .typeStyle(TypeRamp.taskTitle)
                        .foregroundStyle(Color(role: .fgDefault, in: theme))
                        .multilineTextAlignment(.center)
                    Text("盒子里是什么，开了才知道", bundle: .module)
                        .typeStyle(TypeRamp.callout)
                        .foregroundStyle(Color(role: .fgMuted, in: theme))
                        .multilineTextAlignment(.center)
                }
                VStack(spacing: Space.xs) {
                    Button(action: open) {
                        Text("一键全开", bundle: .module).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .accessibilityIdentifier("editor.arrival.open")
                    Button(action: model.leaveArrival) {
                        Text("先不了", bundle: .module)
                    }
                    .buttonStyle(TextButtonStyle(.muted))
                    .accessibilityIdentifier("editor.arrival.leave")
                }
                .disabled(step != .closed)
            }
            .padding(Space.l)
            .background(
                Color(role: .bgCanvas, in: theme),
                in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
            )
            .padding(.horizontal, Space.pageMargin + Space.m)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("editor.arrival")
        }
        .haptic(.appear, trigger: step) { _, step in step == .open }
    }

    /// 「LAP NINE 到新货了」 when they all came to one store, else 「商店街到新货了」.
    private var title: Text {
        if arrival.store != nil, let first = arrival.pieces.first {
            UnlockNames.title(.piece, item: first)
        } else {
            Text("商店街到新货了", bundle: .module)
        }
    }

    private func open() {
        Task {
            if reduceMotion {
                withAnimation(.wildcard(Motion.sheet, reduceMotion: true)) { step = .revealed }
            } else {
                step = .shaking
                try? await Task.sleep(for: .seconds(shake))
                withAnimation(.wildcard(Motion.sheet)) { step = .open }
                try? await Task.sleep(for: .seconds(Motion.sheet.response))
                withAnimation(.wildcard(Motion.celebrate)) { step = .revealed }
            }
            try? await Task.sleep(for: .seconds(hold))
            model.openArrival()
        }
    }
}

/// One carton with its 「？」: it shakes, its flaps fly off, and its piece pops up out of it.
private struct Box: View {
    let model: CharacterEditorModel
    let piece: String
    let step: ArrivalPopup.Step
    let scale: Double
    let reduceMotion: Bool
    @Environment(\.sceneTheme) private var theme

    /// Where the flaps fly to, off their hinges, in the art's points.
    private let leftOff = CartonBox.Flap(x: -46, y: -38, degrees: -70)
    private let rightOff = CartonBox.Flap(x: 46, y: -38, degrees: 70)

    var body: some View {
        let size = CGSize(width: CartonBox.size.width * scale, height: CartonBox.size.height * scale)
        let isOpen = step >= .open && !reduceMotion
        ZStack(alignment: .bottom) {
            // The piece rises out of the box once it is open.
            if let preview = model.preview(of: piece) {
                Thumbnail(
                    outfit: preview.outfit, only: preview.slot, crop: ThumbnailCrop.of(preview.slot),
                    cache: model.thumbnails
                )
                .frame(width: size.width * 0.9, height: size.width * 0.9)
                .scaleEffect(step == .revealed ? 1 : 0.3)
                .offset(y: step == .revealed && !reduceMotion ? -size.height * 0.5 : -size.height * 0.2)
                .opacity(step == .revealed ? 1 : 0)
            }
            CartonBox(
                leftFlap: isOpen ? leftOff : .closed, rightFlap: isOpen ? rightOff : .closed,
                flapOpacity: isOpen ? 0 : 1
            )
            .overlay {
                Text(verbatim: "?")
                    .typeStyle(TypeRamp.scoreCard)
                    .foregroundStyle(Color(role: .fgOnInk, in: theme))
                    .offset(y: CartonBox.size.height * 0.16)
            }
            .scaleEffect(scale, anchor: .bottom)
            .frame(width: size.width, height: size.height)
            .keyframeAnimator(initialValue: 0.0, trigger: step >= .shaking && !reduceMotion) { box, degrees in
                box.rotationEffect(.degrees(degrees), anchor: .bottom)
            } keyframes: { _ in
                // The prototype's shake: 0, -7, 7, -5, 5, -2, 0 degrees over 0.52 seconds.
                KeyframeTrack {
                    LinearKeyframe(-7.0, duration: 0.087)
                    LinearKeyframe(7.0, duration: 0.087)
                    LinearKeyframe(-5.0, duration: 0.087)
                    LinearKeyframe(5.0, duration: 0.087)
                    LinearKeyframe(-2.0, duration: 0.086)
                    LinearKeyframe(0.0, duration: 0.086)
                }
            }
        }
        .frame(width: size.width, height: size.height)
        .accessibilityHidden(true)
    }
}
#endif
