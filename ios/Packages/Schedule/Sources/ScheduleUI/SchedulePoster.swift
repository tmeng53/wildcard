#if os(iOS)
import AvatarDomain
import AvatarUI
import Contracts
import DesignSystem
import DesignSystemUI
import ScheduleDomain
import SwiftUI

/// The poster's colours: the scene's on a week, the brand's graphite on the 每周模板, which is
/// the member's own and never follows the squad's scene.
struct PosterColors: Equatable {
    /// The card.
    let fill: ColorRole
    /// Type on the card, and the held lane's fill.
    let ink: ColorRole
    /// Type on the held lane, and the marks' glyphs.
    let onInk: ColorRole
    /// A mark's disc on the held lane.
    let heldDisc: ColorRole
    /// The lanes' stripes and today's shade.
    let shade: ColorRole

    static let scene = PosterColors(
        fill: .bgAccent, ink: .bgCanvas, onInk: .fgAccent, heldDisc: .bgAccentSubtle, shade: .fgDefault)
    static let brand = PosterColors(
        fill: .bgBrand, ink: .fgOnBrand, onInk: .bgBrand, heldDisc: .bgBrandPage, shade: .fgOnBrand)
}

/// The week as the 出赛表's 3:4 poster (`WeekPoster`) in the scene's color: who and which dates,
/// the week's number, a swim lane a day, the member's character in the corner doing the scene's
/// sport, the titles the weekly awards gave them as stickers (their 颁奖词 sit under the poster),
/// and the week's 饮食小目标 and count along the bottom. Drawn at 360 × 480 points and scaled to
/// fit, so the saved picture and the screen are the same drawing.
struct SchedulePoster: View {
    /// The poster's own size, in points; 3:4.
    static let size = CGSize(width: layout.width ?? 0, height: layout.height)
    static let layout = WeekPosterLayout.poster

    let content: PosterContent
    let player: CharacterPlayer?
    /// Saving: the one pose the character holds, since a picture can't move.
    var still: (drawing: FigureDrawing, placements: [Placement])?
    var onTapLane: (Int) -> Void = { _ in }
    var onTapFuel: () -> Void = {}

    @Environment(\.sceneTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Positions from the approved design, in poster points.
    private let numberOpacity = 0.9
    /// The line over the first lane.
    private let lanesRule: Double = 2
    /// Each title sticker leans a little, like it was slapped on.
    private let stickerTilts: [Double] = [3, -2, 2]
    private let stickerHeight: Double = 28

    private var colors: PosterColors { content.isTemplate ? .brand : .scene }

    var body: some View {
        WeekPoster(
            title: content.isTemplate
                ? content.nickname
                : "\(content.nickname) · \(ScheduleLabels.dates(content.weekStart, content.weekEnd))",
            heading: content.isTemplate
                ? .named(Text("每周模板", bundle: .module), systemImage: ScheduleLabels.templateSymbol)
                : .week(content.weekNumber),
            layout: Self.layout, fill: colors.fill, ink: colors.ink
        ) {
            // The scene's props stand on a week; the 每周模板 is the member's own.
            if !content.isTemplate {
                PosterArt(theme: theme)
            }
        } rows: {
            lanes
        } character: {
            character
        } overlay: {
            stickers
        } strip: {
            PosterBottomBar(content: content, theme: theme, colors: colors, onTapFuel: onTapFuel)
        }
        .animation(.wildcard(Motion.change, reduceMotion: reduceMotion), value: content)
    }

    /// White on the scene's color or the graphite: the poster's ink.
    private var ink: Color { Color(role: colors.ink, in: theme) }

    // MARK: Lanes

    private var lanes: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(ink.opacity(numberOpacity))
                .frame(height: lanesRule)
            ForEach(content.lanes) { lane in
                PosterLane(lane: lane, theme: theme, colors: colors, onTap: onTapLane)
            }
        }
    }

    // MARK: Character, titles

    @ViewBuilder
    private var character: some View {
        if let still {
            CharacterCanvas(drawing: still.drawing, placements: still.placements)
                .aspectRatio(still.drawing.width / still.drawing.height, contentMode: .fit)
        } else if let player {
            CharacterView(player: player)
        }
    }

    private var stickers: some View {
        VStack(alignment: .trailing, spacing: Space.xs - 2) {
            ForEach(Array(content.titles.enumerated()), id: \.element) { position, title in
                HStack(spacing: Space.xxs + 1) {
                    Image(systemName: "star.fill")
                        .font(.system(size: Sizing.smallIcon - 2, weight: .semibold))
                        .accessibilityHidden(true)
                    Text(verbatim: title.title)
                        .typeStyle(TypeRamp.footnoteEmphasis)
                        .lineLimit(1)
                }
                .foregroundStyle(Color(role: .fgAccent, in: theme))
                .padding(.leading, Space.xs + 1)
                .padding(.trailing, Space.s)
                .frame(height: stickerHeight)
                .background(ink, in: Capsule())
                .rotationEffect(.degrees(stickerTilts[position % stickerTilts.count]))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("头衔：\(title.title)", bundle: .module))
                .accessibilityIdentifier("schedule.title.\(position)")
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.trailing, Space.s)
        .padding(.top, Space.s)
        .allowsHitTesting(false)
    }
}
#endif
