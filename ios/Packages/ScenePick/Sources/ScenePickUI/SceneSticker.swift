#if canImport(SwiftUI)
import DesignSystem
import DesignSystemUI
import ScenePickDomain
import SwiftUI

/// 冠军专属: the sticker on the 战报's last page where last week's crown winner (or, with no
/// crown, the captain) picks where the squad trains next week (approved 2026-10-22). A white
/// card tilted 2° left: the scenes as tiles (scrolling sideways past five), a line saying when
/// the squad last trained at the one chosen, and 「确认」. It is the page's only interactive piece
/// and never part of 存图. `onPicked` gets the reveal to play once the pick is saved.
public struct SceneSticker: View {
    @Environment(\.sceneTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let picker: ScenePicker
    private let onPicked: (Unboxing, SceneTheme) -> Void

    public init(picker: ScenePicker, onPicked: @escaping (Unboxing, SceneTheme) -> Void) {
        self.picker = picker
        self.onPicked = onPicked
    }

    // The prototype's sticker: 300 wide inside its padding of 14 (12 at the bottom), as CSS's
    // content box measures it, so 328 across; its blocks 12 apart.
    static let width = 300.0
    private static let inset = 14.0
    private static let bottomInset = 12.0
    private static let corner = 16.0
    private static let tileGap = 6.0
    private static let lineHeight = 16.0
    private static let headerGap = 2.0
    /// CSS's `ease` over 0.2 s, as the line above the button opens.
    private static let open = Animation.timingCurve(0.25, 0.1, 0.25, 1, duration: 0.2)

    public var body: some View {
        VStack(spacing: 0) {
            header
            SceneTileRow(picker: picker, height: 68, spacing: Self.tileGap)
                .padding(.top, Space.s)
            lastTrained
            Button {
                Task {
                    if let reveal = await picker.confirm(), let scene = picker.selection { onPicked(reveal, scene) }
                }
            } label: {
                Text(copy: "确认", bundle: .module).loadingLabel(picker.phase == .saving).frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle(.regular))
            .disabled(!picker.canConfirm)
            .animation(Self.open, value: picker.canConfirm)
            .padding(.top, Space.s)
            .accessibilityIdentifier("scenePick.confirm")
        }
        .frame(width: Self.width)
        .padding(.horizontal, Self.inset)
        .padding(.top, Self.inset)
        .padding(.bottom, Self.bottomInset)
        .background(
            Color(role: .bgCanvas, in: theme), in: RoundedRectangle(cornerRadius: Self.corner, style: .continuous)
        )
        .rotationEffect(.degrees(-2))
    }

    private var header: some View {
        VStack(spacing: Self.headerGap) {
            HStack(spacing: Space.xxs) {
                Crown()
                    .stroke(style: StrokeStyle(lineWidth: 2.2, lineJoin: .round))
                    .frame(width: 13, height: 13)
                    .accessibilityHidden(true)
                Text(copy: "冠军专属", bundle: .module)
                    .typeStyle(TypeRamp.tabSelected)
            }
            .foregroundStyle(Color(role: .fgAccent, in: theme))
            .frame(height: Self.lineHeight)
            Text(copy: "下周去哪练？", bundle: .module)
                .typeStyle(TypeRamp.headline)
                .foregroundStyle(Color(role: .fgDefault, in: theme))
                .frame(height: 24)
                .accessibilityAddTraits(.isHeader)
        }
    }

    /// 「小队 N 周前在这里练过」 and the like: closed until a tile is chosen, then opening 8 under
    /// the tiles.
    private var lastTrained: some View {
        Group {
            if let last = picker.selectionLastTrained {
                LastTrainedLine(last: last)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: picker.selectionLastTrained == nil ? 0 : Self.lineHeight, alignment: .top)
        .clipped()
        .padding(.top, picker.selectionLastTrained == nil ? 0 : Space.xs)
        .animation(reduceMotion ? nil : Self.open, value: picker.selectionLastTrained)
    }
}

/// The picker's scenes side by side, a tap choosing one: on the sticker, and on sign-up's
/// 这周在哪练？. Up to five share the row; with more (a limited scene like the winter 雪场 on
/// top of the five) the row scrolls sideways, five and a half tiles across so the half tile
/// says there is more (Tracy, 2026-11-10). `height` is each face's.
public struct SceneTileRow: View {
    private let picker: ScenePicker
    private let height: Double
    private let spacing: Double

    /// The tiles that fit the row before it scrolls.
    static let fitting = 5
    /// Room around a scrolling row for a chosen tile's lift (raised 4, ringed 4, scaled 1.06 and
    /// tilted 4°), which a scroll view would otherwise clip.
    private static let liftRoom = 12.0

    public init(picker: ScenePicker, height: Double, spacing: Double) {
        (self.picker, self.height, self.spacing) = (picker, height, spacing)
    }

    public var body: some View {
        if picker.options.count <= Self.fitting {
            HStack(alignment: .top, spacing: spacing) { tiles }
        } else {
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: spacing) {
                    // Each tile two elevenths of the row: five and a half across.
                    tiles.containerRelativeFrame(.horizontal, count: Self.fitting * 2 + 1, span: 2, spacing: spacing)
                }
                .scrollTargetLayout()
                .padding(.vertical, Self.liftRoom)
            }
            .contentMargins(.horizontal, Self.liftRoom, for: .scrollContent)
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.viewAligned)
            .padding(-Self.liftRoom)
            .accessibilityIdentifier("scenePick.row")
        }
    }

    private var tiles: some View {
        ForEach(picker.options) { option in
            SceneTile(
                scene: option.scene, name: option.scene.name, isOpened: option.isOpened,
                isSelected: picker.selection == option.scene, height: height
            ) {
                picker.select(option.scene)
            }
            .accessibilityLabel(option.isOpened ? option.scene.name : SceneName.boxed(option.scene))
            .accessibilityIdentifier("scenePick.\(option.scene.rawValue)")
        }
    }
}

/// When the squad last trained at the chosen scene, the number in Barlow: on the sticker, and
/// on squad settings' picker.
public struct LastTrainedLine: View {
    @Environment(\.sceneTheme) private var theme
    let last: LastTrained

    public init(last: LastTrained) {
        self.last = last
    }

    public var body: some View {
        Group {
            switch last {
            case .thisWeek: Text(copy: "这周就在这儿练", bundle: .module)
            case .never: Text(copy: "小队还没来过", bundle: .module)
            case .weeksAgo(let weeks):
                // Text's own modifiers, so the number stays a Text to interpolate.
                let style = TypeRamp.scoreCaption
                let number = Text(verbatim: "\(weeks)").font(.wildcard(style)).tracking(style.tracking)
                    .foregroundStyle(Color(role: .fgDefault, in: theme))
                Text(copy: "小队 \(number) 周前在这里练过", bundle: .module)
            }
        }
        .typeStyle(TypeRamp.caption)
        .foregroundStyle(Color(role: .fgMuted, in: theme))
        .lineLimit(1)
    }
}

/// The sticker's crown, on a 24-point grid.
struct Crown: Shape {
    func path(in rect: CGRect) -> Path {
        let points = [(3.0, 8.0), (7.5, 12), (12, 5), (16.5, 12), (21, 8), (19, 19), (5, 19)]
        var path = Path()
        path.addLines(
            points.map { CGPoint(x: rect.minX + $0.0 / 24 * rect.width, y: rect.minY + $0.1 / 24 * rect.height) })
        path.closeSubpath()
        return path
    }
}

/// A carton's name for VoiceOver, which says it is still closed.
enum SceneName {
    static func boxed(_ scene: SceneTheme) -> Text {
        Text(copy: "\(scene.name)，还没开过", bundle: .module)
    }
}
#endif
