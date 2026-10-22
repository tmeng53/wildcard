#if os(iOS)
import AvatarUI
import CheckInDomain
import Contracts
import DesignSystem
import DesignSystemUI
import SwiftUI

/// The squad's scene, full screen: the venue's art, every teammate where `SquadStage` puts them,
/// me front and centre, the status rings on the ground, and the lights at night. Positions are
/// the design's 390-point-wide stage, scaled to the screen's width.
struct SquadSceneView: View {
    @Environment(\.sceneTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let cast: SquadCast
    let myPlayer: CharacterPlayer?
    let myRing: RingStatus
    let phase: DayPhase
    /// Bumps on each of my 练了: the ground ring draws, the camera leans in, the streamers fall.
    let celebration: Int

    var body: some View {
        GeometryReader { proxy in
            let unit = proxy.size.width / StageLayout.width
            ZStack(alignment: .topLeading) {
                SceneArt(scene: theme, layer: .day)
                    .frame(width: proxy.size.width, height: Stage.height * unit)
                cast(unit: unit)
                if phase == .night {
                    SceneArt(scene: theme, layer: .night)
                        .frame(width: proxy.size.width, height: Stage.height * unit)
                        .allowsHitTesting(false)
                }
                CheerBubbles(cast: cast, unit: unit)
                Streamers(trigger: celebration)
                    .allowsHitTesting(false)
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
            .keyframeAnimator(initialValue: 1.0, trigger: celebration) { content, zoom in
                content.scaleEffect(
                    reduceMotion ? 1 : zoom,
                    anchor: UnitPoint(x: 0.5, y: StageLayout.mySpot.y / Stage.height))
            } keyframes: { _ in
                KeyframeTrack {
                    CubicKeyframe(1, duration: Motion.ringFill)
                    CubicKeyframe(Self.lean, duration: 0.23)
                    CubicKeyframe(1, duration: 0.42)
                }
            }
        }
        .background(Color(role: .bgSubtle, in: theme))
        .clipped()
    }

    /// How far the camera leans in when my ring closes.
    private static let lean = 1.045

    /// Everyone, back to front, redrawn each display frame so runners and swimmers move.
    private func cast(unit: Double) -> some View {
        TimelineView(.animation(minimumInterval: nil, paused: reduceMotion)) { timeline in
            let seconds = timeline.date.timeIntervalSinceReferenceDate
            let figures = placed(at: reduceMotion ? 0 : seconds)
            ZStack(alignment: .topLeading) {
                ForEach(figures) { figure in
                    StageFigure(figure: figure, unit: unit, date: timeline.date, reduceMotion: reduceMotion)
                        .zIndex(figure.depth)
                }
                ForEach(Array(Stage.fronts(of: theme).enumerated()), id: \.offset) { index, depth in
                    SceneArt(scene: theme, layer: .front(index))
                        .frame(width: StageLayout.width * unit, height: Stage.height * unit)
                        .allowsHitTesting(false)
                        .zIndex(depth)
                }
            }
        }
    }

    /// Each figure's spot this frame, back to front. Me a little in front of my own row.
    private func placed(at seconds: Double) -> [Placed] {
        var figures = cast.mates.compactMap { mate -> Placed? in
            guard let position = cast.stage.position(of: mate.id, at: seconds) else { return nil }
            return Placed(
                id: .mate(mate.id), player: mate.player, position: position, ring: mate.member.status.ring,
                pose: cast.stage.pose(of: mate.member, at: phase), sign: mate.disclaimer)
        }
        if let myPlayer {
            figures.append(
                Placed(
                    id: .mine, player: myPlayer,
                    position: .mine,
                    ring: myRing, pose: .standing, sign: nil))
        }
        return figures
    }
}

/// The design's stage: 390 (`StageLayout.width`) by 844 points, the screen it was drawn for.
enum Stage {
    static let height = 844.0

    /// The venue's parts people stand behind, by depth: the tennis net.
    static func fronts(of scene: SceneTheme) -> [Double] {
        scene == .tennis ? [388.5] : []
    }
}

/// A figure on the stage this frame.
private struct Placed: Identifiable {
    enum ID: Hashable {
        case mine
        case mate(MemberID)
    }

    let id: ID
    let player: CharacterPlayer
    let position: StagePosition
    let ring: RingStatus
    let pose: StagePose
    let sign: String?

    var depth: Double { position.point.y + (id == .mine ? 50 : 0) }
}

/// One character with its ring on the ground, its 请假条 or its sleep.
private struct StageFigure: View {
    @Environment(\.sceneTheme) private var theme
    let figure: Placed
    let unit: Double
    let date: Date
    let reduceMotion: Bool

    /// The rig's canvas and where its feet are on it.
    private static let canvas = CGSize(width: 240, height: 320)
    private static let feet = CGPoint(x: 120, y: 316)

    var body: some View {
        let scale = figure.position.scale * unit
        let point = figure.position.point
        let frame = reduceMotion ? figure.player.restFrame : figure.player.frame(at: date)
        ZStack {
            GroundRing(ring: figure.ring, scale: scale, unit: unit)
                .position(x: Self.feet.x * scale, y: Self.feet.y * scale - 2 * unit)
            CharacterCanvas(drawing: frame.drawing, placements: frame.placements)
                .scaleEffect(x: figure.position.facing, y: 1)
            if figure.pose == .holdingSign {
                SignCard(scale: scale)
                    .position(x: Self.feet.x * scale, y: 249 * scale)
            }
            if figure.pose == .asleep {
                Text(verbatim: "z z")
                    .font(.system(size: 60 * scale, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color(role: .fgOnScene, in: theme).opacity(0.85))
                    .position(x: 170 * scale, y: 60 * scale)
            }
        }
        .frame(width: Self.canvas.width * scale, height: Self.canvas.height * scale)
        .contentShape(Rectangle())
        .position(
            x: point.x * unit,
            y: point.y * unit - (Self.feet.y - Self.canvas.height / 2) * scale)
    }
}

/// The status ring on the ground under a character's feet, the same rule as the head rings in
/// the card: in the scene's ring colour once checked in, thin and grey on a rest day. When it
/// turns checked in on screen it draws itself clockwise, like the card's ring. Its size follows
/// the character (`scale`); its line stays the same on everyone (`unit`, one stage point).
private struct GroundRing: View {
    @Environment(\.sceneTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let ring: RingStatus
    let scale: Double
    let unit: Double
    @State private var drawn: Double?

    var body: some View {
        let shape = Ellipse()
        ZStack {
            switch ring {
            case .done:
                shape.trim(from: 0, to: drawn ?? 1)
                    .stroke(Color(role: .ring, in: theme), style: StrokeStyle(lineWidth: 3 * unit, lineCap: .round))
            case .restDay:
                shape.stroke(Color(role: .borderDefault, in: theme), lineWidth: 1.6 * unit)
            case .open:
                EmptyView()
            }
        }
        // The design's ellipse: 105 by 36 rig points around the feet.
        .frame(width: 210 * scale, height: 71.4 * scale)
        .onChange(of: ring) { _, new in
            guard new == .done, !reduceMotion else { return }
            drawn = 0
            withAnimation(.timingCurve(0.2, 0.8, 0.3, 1, duration: Motion.ringFill)) { drawn = 1 }
        }
        .allowsHitTesting(false)
    }
}

/// The 请假条 a teammate holds up in front of their chest.
private struct SignCard: View {
    @Environment(\.sceneTheme) private var theme
    let scale: Double

    var body: some View {
        Text("请假条", bundle: .module)
            .font(.system(size: 27 * scale, weight: .bold))
            .foregroundStyle(Color(role: .fgAccent, in: theme))
            .frame(width: 108 * scale, height: 58 * scale)
            .background(Color(role: .bgCanvas, in: theme), in: card)
            .overlay(card.stroke(Color(role: .fgAccent, in: theme), lineWidth: 4 * scale))
    }

    /// The card as the design draws it in the rig's points: 108 by 58, corners of 9.
    private var card: RoundedRectangle {
        RoundedRectangle(cornerSize: CGSize(width: 9 * scale, height: 9 * scale))
    }
}

/// The venue's art, exported from the approved home design (`SceneArt/render.mjs`).
struct SceneArt: View {
    enum Layer {
        case day
        /// The dark tint and the lamps, over everything on the scene.
        case night
        /// A part of the venue people stand behind.
        case front(Int)

        var name: String {
            switch self {
            case .day: "day"
            case .night: "night"
            case .front(let index): "front-\(index)"
            }
        }
    }

    let scene: SceneTheme
    let layer: Layer

    var body: some View {
        Image(uiImage: UIImage(named: "\(scene.rawValue)-\(layer.name)", in: .module, with: nil) ?? UIImage())
            .resizable()
            .accessibilityHidden(true)
    }
}

/// A scene's venue as home draws it, filling the screen with nobody on it: what the scene pick's
/// reveal shows as its card rises, before home takes over.
public struct SceneBackdrop: View {
    private let scene: SceneTheme

    public init(scene: SceneTheme) {
        self.scene = scene
    }

    public var body: some View {
        GeometryReader { proxy in
            SceneArt(scene: scene, layer: .day)
                .frame(width: proxy.size.width, height: Stage.height * proxy.size.width / StageLayout.width)
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
        }
        .background(Color(role: .bgCanvas, in: scene))
    }
}
#endif

#if os(iOS)
extension StageStatus {
    /// The ring around the head and under the feet: closed once checked in (练了 or 请假条), grey
    /// with the moon on a planned rest day, open otherwise.
    var ring: RingStatus {
        switch self {
        case .trained, .disclaimer: .done
        case .restDay: .restDay
        case .notYet: .open
        }
    }
}
#endif
